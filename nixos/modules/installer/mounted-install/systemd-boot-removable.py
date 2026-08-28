#! @python3@/bin/python3 -B
# SPDX-License-Identifier: MIT
"""
Populate a mounted EFI System Partition (ESP) for *removable* media booting
with systemd-boot, in a way that is safe to run on a cross-architecture build
host.

This is the offline, cross-arch counterpart of `bootctl install`:

  * The target-architecture ``systemd-boot<arch>.efi`` is copied to the
    UEFI fallback path (``EFI/BOOT/BOOT<ARCH>.EFI``) so that firmware boots it
    when no NVRAM boot entry exists -- exactly what you want for USB sticks or
    SD cards.  EFI variables are never touched.
  * A ``loader/loader.conf`` and a single Boot Loader Specification (BLS)
    type#1 entry are generated from the toplevel's ``boot.json`` bootspec, and
    the kernel / initrd / devicetree are copied into ``EFI/nixos/``.

Only the *default* generation (the toplevel being installed) is written; later
generations are managed by the normal ``systemd-boot`` builder running on the
target after first boot.

The script reads only files from the Nix store of the build host and performs
plain byte copies, so it does not execute any target-architecture binaries.
"""

import argparse
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

# Replaced at build time.
EFI_ARCH = "@efiArch@"
SYSTEMD = Path("@systemd@")
DISTRO_NAME = "@distroName@"
STORE_DIR = "@storeDir@"

# Subdirectory of the ESP that holds kernels/initrds (matches the normal
# systemd-boot builder, so a later ``bootctl update`` on the target keeps the
# same layout).
NIXOS_DIR = Path("EFI/nixos")


def boot_path(file_path: Path) -> Path:
    """Map a /nix/store/<hash>-name/... path to its ESP destination.

    Mirrors ``boot_path()`` in ``systemd-boot-builder.py`` so the naming stays
    consistent with what the on-target builder would produce.
    """
    file_path = file_path.resolve()
    suffix = file_path.name
    store_subdir = file_path.relative_to(STORE_DIR).parts[0]
    if suffix == store_subdir:
        return NIXOS_DIR / f"{suffix}.efi"
    return NIXOS_DIR / f"{store_subdir}-{suffix}.efi"


def copy_boot_file(src: Path, esp: Path) -> Path:
    """Copy a store file into the ESP, returning its path relative to the ESP."""
    dst_rel = boot_path(src)
    dst = esp / dst_rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        return dst_rel
    tmp = dst.with_name(dst.name + ".tmp")
    shutil.copyfile(src, tmp)
    os.replace(tmp, dst)
    return dst_rel


def install_systemd_boot_efi(esp: Path) -> None:
    """Copy the target-arch systemd-boot binary to the fallback and canonical
    locations.  No NVRAM variables are modified."""
    efi_bin = SYSTEMD / f"lib/systemd/boot/efi/systemd-boot{EFI_ARCH}.efi"
    if not efi_bin.is_file():
        sys.exit(
            f"error: systemd-boot EFI binary not found at {efi_bin} "
            f"(is this platform supported by systemd-boot?)"
        )
    fallback = esp / "EFI" / "BOOT" / f"BOOT{EFI_ARCH.upper()}.EFI"
    canonical = esp / "EFI" / "systemd" / f"systemd-boot{EFI_ARCH}.efi"
    fallback.parent.mkdir(parents=True, exist_ok=True)
    canonical.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(efi_bin, fallback)
    shutil.copyfile(efi_bin, canonical)


def write_loader_conf(esp: Path, timeout: str, editor: bool, console_mode: str) -> None:
    conf_dir = esp / "loader"
    conf_dir.mkdir(parents=True, exist_ok=True)
    lines = [f"timeout {timeout}", "default nixos-*"]
    if not editor:
        lines.append("editor 0")
    lines.append(f"console-mode {console_mode}")
    (conf_dir / "loader.conf").write_text("\n".join(lines) + "\n")


def write_entry_doc(esp: Path, doc: dict, label_suffix: str = "") -> str:
    """Write a single BLS entry from a bootspec *document*; return its filename.

    A bootspec document bundles ``org.nixos.bootspec.v1`` with the
    ``org.nixos.systemd-boot`` and ``org.nixos.extra-initrd.v1`` extensions.
    The toplevel's ``boot.json`` is such a document, and so is each value of its
    ``org.nixos.specialisation.v1`` map -- so both the main configuration and
    every system specialisation are written with this same routine.
    """
    v1 = doc["org.nixos.bootspec.v1"]
    sb = doc.get("org.nixos.systemd-boot", {})
    extra = doc.get("org.nixos.extra-initrd.v1", {})

    label = v1["label"]
    init = v1["init"]
    kparams = v1.get("kernelParams", [])
    kernel = Path(v1["kernel"]) if "kernel" in v1 else None
    initrd = Path(v1["initrd"]) if "initrd" in v1 else None
    extra_initrds = [Path(x) for x in extra.get("paths", [])]
    sort_key = sb.get("sortKey", "nixos")
    devicetree = sb.get("devicetree")

    title = DISTRO_NAME if not label_suffix else f"{DISTRO_NAME} ({label_suffix})"
    entry_lines = [
        f"title {title}",
        f"version {label}",
    ]

    (esp / NIXOS_DIR).mkdir(parents=True, exist_ok=True)

    if kernel is not None:
        kernel_dst = copy_boot_file(kernel, esp)
        entry_lines.append(f"linux /{kernel_dst}")

    if initrd is not None:
        initrd_dst = copy_boot_file(initrd, esp)
        entry_lines.append(f"initrd /{initrd_dst}")

    for ei in extra_initrds:
        ei_dst = copy_boot_file(ei, esp)
        entry_lines.append(f"initrd /{ei_dst}")

    options = " ".join([f"init={init}"] + list(kparams))
    entry_lines.append(f"options {options}")

    if devicetree:
        dt_dst = copy_boot_file(Path(devicetree), esp)
        entry_lines.append(f"devicetree /{dt_dst}")

    entry_lines.append(f"sort-key {sort_key}")

    contents = "\n".join(entry_lines) + "\n"
    digest = hashlib.sha256(contents.encode()).hexdigest()
    entry_name = f"nixos-{digest}.conf"

    entries_dir = esp / "loader" / "entries"
    entries_dir.mkdir(parents=True, exist_ok=True)
    (entries_dir / entry_name).write_text(contents)
    return entry_name


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Install systemd-boot to a mounted ESP for removable media "
        "(cross-architecture, no NVRAM).",
    )
    parser.add_argument("--esp", required=True, help="mount point of the ESP")
    parser.add_argument("--system", required=True, help="NixOS toplevel store path")
    parser.add_argument("--timeout", required=True, help="loader timeout value")
    parser.add_argument(
        "--editor",
        choices=["1", "0"],
        default="1",
        help="enable the boot loader editor",
    )
    parser.add_argument(
        "--console-mode", default="auto", help="console-mode for loader.conf"
    )
    args = parser.parse_args()

    esp = Path(args.esp)
    system = Path(args.system)

    if not esp.is_dir():
        sys.exit(f"error: ESP mount point {esp} is not a directory")
    if not system.is_dir():
        sys.exit(f"error: toplevel {system} is not a directory")

    install_systemd_boot_efi(esp)
    write_loader_conf(
        esp,
        timeout=args.timeout,
        editor=(args.editor == "1"),
        console_mode=args.console_mode,
    )

    boot_json = system / "boot.json"
    if not boot_json.is_file():
        sys.exit(f"error: bootspec not found: {boot_json}")
    with boot_json.open() as f:
        doc = json.load(f)

    entry_name = write_entry_doc(esp, doc)
    print(f"systemd-boot installed to {esp} (entry: loader/entries/{entry_name})")

    # System specialisations are embedded in the bootspec as their own
    # documents; give each its own BLS entry (kernel/initrd are shared on the
    # ESP via content-addressed names).
    for name, spec_doc in doc.get("org.nixos.specialisation.v1", {}).items():
        sp_entry = write_entry_doc(esp, spec_doc, label_suffix=name)
        print(f"  specialisation '{name}': loader/entries/{sp_entry}")


if __name__ == "__main__":
    main()
