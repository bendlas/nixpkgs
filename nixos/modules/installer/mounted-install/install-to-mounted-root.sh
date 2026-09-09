#! @runtimeShell@
# shellcheck shell=bash
#
# install-to-mounted-root: populate an already-prepared, mounted set of
# partitions with a NixOS system, in a way that is safe to run from a
# cross-architecture build host (e.g. install aarch64 NixOS from an x86_64
# machine).
#
# Unlike `nixos-install`, no target-architecture binaries are ever executed:
# the store is populated with host `nix --store`, and the boot loader is
# installed with build-architecture tooling.  Unlike the `sd-card` installer,
# nothing is written to a disk image and there is no "grow the root filesystem"
# first-boot service: the partitions are expected to already be partitioned,
# formatted and mounted by the caller.
#
# Usage:
#   install-to-mounted-root --root <mount-point> \
#       [--system <toplevel>] [--no-bootloader]
#       [--bootloader extlinux|systemd-boot|grub|none]
#       [--esp <esp-mount-point>] [--boot-dir <boot-dir>]
#       [--file-registration|--immediate]

set -e
shopt -s nullglob

export PATH=@path@:$PATH
umask 0022

# Defaults baked in at build time.
system="@defaultSystem@"
bootloader="@defaultBootloader@"
esp=""
bootDir=""
fileRegistration="@fileRegistration@"
grubDevice="@grubDevice@"

# Paths (baked) used by the file-registration mode.
storePathsFile="@storePathsFile@"
registrationFile="@registrationFile@"

usage() {
    cat >&2 <<EOF
usage: $0 --root <mount-point> [options]

Options:
  --root <dir>            Mount point of the target root filesystem (required).
  --system <toplevel>    NixOS toplevel store path to install
                          (default: the system this installer was built for).
  --no-bootloader        Skip boot loader installation.
  --bootloader <name>    Override the boot loader: extlinux | systemd-boot | grub | none.
  --grub-device <dev>    Override the GRUB install device (BIOS/MBR only),
                          defaulting to the one baked from the configuration.
  --esp <dir>            Mount point of the target ESP (default: <root>/@defaultEsp@).
                          Required for systemd-boot.
  --boot-dir <dir>       Boot directory for extlinux (default: <root>/@defaultBootDir@).
  --file-registration    Copy the closure with cp and write /nix-path-registration
                          (a first-boot service on the target loads the DB).
  --immediate            Register the store immediately with host nix --store
                          (the default for this installer).
  --debug                Enable trace output.
EOF
    exit 1
}

while [ "$#" -gt 0 ]; do
    i="$1"; shift 1
    case "$i" in
        --root)
            [ -n "$1" ] || { echo "$0: --root requires an argument" >&2; exit 1; }
            root="$1"; shift 1 ;;
        --system)
            [ -n "$1" ] || { echo "$0: --system requires an argument" >&2; exit 1; }
            system="$1"; shift 1 ;;
        --no-bootloader) bootloader="none" ;;
        --bootloader)
            [ -n "$1" ] || { echo "$0: --bootloader requires an argument" >&2; exit 1; }
            bootloader="$1"; shift 1 ;;
        --grub-device)
            [ -n "$1" ] || { echo "$0: --grub-device requires an argument" >&2; exit 1; }
            grubDevice="$1"; shift 1 ;;
        --esp)
            [ -n "$1" ] || { echo "$0: --esp requires an argument" >&2; exit 1; }
            esp="$1"; shift 1 ;;
        --boot-dir)
            [ -n "$1" ] || { echo "$0: --boot-dir requires an argument" >&2; exit 1; }
            bootDir="$1"; shift 1 ;;
        --file-registration) fileRegistration=1 ;;
        --immediate) fileRegistration=0 ;;
        --debug) set -x ;;
        --help|-h) usage ;;
        *) echo "$0: unknown option '$i'" >&2; usage ;;
    esac
done

if [ -z "${root:-}" ]; then
    echo "$0: --root is required" >&2
    exit 1
fi
if [ ! -e "$root" ]; then
    echo "$0: mount point '$root' does not exist" >&2
    exit 1
fi
root=$(realpath "$root")

# Resolve ESP and boot directory paths relative to the target root unless the
# caller gave absolute host paths.
if [ -z "$esp" ]; then esp="$root/@defaultEsp@"; fi
if [ -z "$bootDir" ]; then bootDir="$root/@defaultBootDir@"; fi

case "$bootloader" in
    extlinux|systemd-boot|grub|none) ;;
    *) echo "$0: unknown bootloader '$bootloader'" >&2; exit 1 ;;
esac

echo "installing NixOS to '$root'"
echo "  toplevel:     $system"
echo "  bootloader:   $bootloader"
echo "  registration: $([ "$fileRegistration" = 1 ] && echo 'file (first-boot)' || echo 'immediate (host nix)')"

# ---------------------------------------------------------------------------
# Populate the Nix store and (optionally) the system profile.
# ---------------------------------------------------------------------------
if [ "$fileRegistration" = 1 ]; then
    if [ "$system" != "@defaultSystem@" ]; then
        echo "$0: --file-registration only supports installing the system this" >&2
        echo "$0: installer was built for (got '$system', expected '@defaultSystem@')." >&2
        echo "$0: Use --immediate (the default for this attribute) to install a" >&2
        echo "$0: different closure, or build a dedicated file-registration installer." >&2
        exit 1
    fi
    echo "copying Nix store closure to $root/nix/store ..."
    mkdir -p "$root/nix/store"
    # closureInfo's store-paths list, one path per line.  xargs batches so we
    # stay well below ARG_MAX for large closures.
    xargs -d '\n' -a "$storePathsFile" cp -a --reflink=auto -t "$root/nix/store/"
    echo "writing $root/nix-path-registration ..."
    cp "$registrationFile" "$root/nix-path-registration"
else
    echo "populating Nix store and setting the system profile (host nix) ..."
    nix-env --store "$root" --extra-substituters "auto?trusted=1" \
        -p "$root/nix/var/nix/profiles/system" --set "$system"
fi

# Mark the target as a NixOS installation.
mkdir -m 0755 -p "$root/etc"
touch "$root/etc/NIXOS"

# ---------------------------------------------------------------------------
# Install the boot loader.
# ---------------------------------------------------------------------------
if [ "$bootloader" = "extlinux" ]; then
    echo "installing extlinux boot configuration to $bootDir ..."
    # -g 0 disables the generation scan so only the default entry (the toplevel
    # being installed) is written; otherwise the build host's own NixOS
    # generations would leak into the target's extlinux.conf.
    @extlinuxPopulateCmd@ -c "$system" -d "$bootDir" -g 0
elif [ "$bootloader" = "systemd-boot" ]; then
    if [ ! -d "$esp" ]; then
        echo "$0: ESP '$esp' is not a directory; mount the ESP and pass --esp." >&2
        exit 1
    fi
    echo "installing systemd-boot (removable, no NVRAM) to $esp ..."
    @systemdBootRemovable@ \
        --esp "$esp" \
        --system "$system" \
        --timeout "@systemdBootTimeout@" \
        --editor "@systemdBootEditor@" \
        --console-mode "@systemdBootConsoleMode@"
elif [ "$bootloader" = "grub" ]; then
    echo "installing GRUB ($@grubPlatform@) to $root ..."
    @grubInstaller@ \
        --root "$root" \
        --system "$system" \
        --grub-target "@grubPlatform@" \
        $([ "@grubRemovable@" = 1 ] && echo --removable || echo --no-removable) \
        $([ -n "$grubDevice" ] && echo --device "$grubDevice")
elif [ "$bootloader" = "none" ]; then
    echo "skipping boot loader installation"
fi

echo "installation finished."
