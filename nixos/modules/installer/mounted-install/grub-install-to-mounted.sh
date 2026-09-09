#! @runtimeShell@
# SPDX-License-Identifier: MIT
#
# Install GRUB onto a *mounted* root, cross-architecture safe: the only
# "foreign" work is running the build host's GRUB utilities (grub-mkimage /
# grub-install), which embed the target firmware modules and never execute any
# target-architecture binary.  This mirrors what `bootctl install` / uboot do
# for the other boot loaders, but for GRUB.
#
# Two layouts are supported:
#   * EFI  (--grub-target ends in -efi): build a core image with grub-mkimage
#           and drop it at the UEFI fallback path EFI/BOOT/BOOT<ARCH>.EFI, with
#           modules + grub.cfg beside it.  No EFI variables are touched.
#   * BIOS/MBR (--grub-target ends in -pc): grub-install writes the core image
#           into the gap / embedding area of --device and modules under
#           <boot-dir>/grub; we then write <boot-dir>/grub/grub.cfg.
#
# The NixOS menu entries are generated here (not via grub-mkconfig) by reading
# the toplevel's kernel / initrd / kernel-params, exactly like the extlinux
# path.  Specialisations get their own submenu entries.

set -euo pipefail

grubTool=@grubTool@
grubPlatform=@grubPlatform@

usage() {
  cat <<USAGE
Usage: $0 --root <mounted-root> --system <toplevel> --grub-target <platform>
         [ --esp <efi-mount> ] [ --boot-dir <boot-dir> ]
         [ --removable ] [ --no-removable ]
         [ --device <disk-or-partition> ] [ --boot-device <grub-device> ]

Install GRUB for the given NixOS toplevel into a mounted root.

  --root          Mount point of the target root (required).
  --system        NixOS toplevel store path (required).
  --grub-target   GRUB platform, e.g. aarch64-efi, x86_64-efi, i386-pc (required).
  --esp           ESP mount point (for EFI; default: <root>@grubEsp@).
  --boot-dir      GRUB boot directory (default: <root>@grubBootDir@).
  --removable     Install to the UEFI fallback path (default for EFI).
  --no-removable  Also install to EFI/<distro>/grub<arch>.efi.
  --device        Block device for BIOS/MBR install (e.g. /dev/sda).
  --boot-device   GRUB device spec for the boot partition, e.g. '(hd0,gpt2)'
                  or 'search --fs-uuid <uuid>'.  If omitted, the UUID of the
                  mounted boot directory is discovered via blkid.
USAGE
}

root=""
system=""
esp=""
bootDir=""
removable=1
device=""
bootDevice=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --system) system="$2"; shift 2 ;;
    --grub-target) grubPlatform="$2"; shift 2 ;;
    --esp) esp="$2"; shift 2 ;;
    --boot-dir) bootDir="$2"; shift 2 ;;
    --removable) removable=1; shift ;;
    --no-removable) removable=0; shift ;;
    --device) device="$2"; shift 2 ;;
    --boot-device) bootDevice="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$root" ]; then echo "error: --root is required" >&2; usage >&2; exit 1; fi
if [ -z "$system" ]; then echo "error: --system is required" >&2; usage >&2; exit 1; fi
if [ -z "$grubPlatform" ]; then echo "error: --grub-target is required" >&2; usage >&2; exit 1; fi

root=$(readlink -f "$root")
system=$(readlink -f "$system")

isEfi=0
case "$grubPlatform" in
  *-efi) isEfi=1 ;;
esac

if [ "$isEfi" -eq 1 ]; then
  [ -z "$esp" ] && esp="${root}/@grubEsp@"
  [ -z "$bootDir" ] && bootDir="${root}/@grubBootDir@"
else
  [ -z "$bootDir" ] && bootDir="${root}/@grubBootDir@"
  if [ -z "$device" ]; then
    echo "error: BIOS/MBR GRUB install requires --device (the disk/partition)" >&2
    exit 1
  fi
fi

bootDir=$(readlink -f "$bootDir")
[ "$isEfi" -eq 1 ] && esp=$(readlink -f "$esp")

efiArch=$(echo "$grubPlatform" | sed -E 's/-efi$//; s/^./\U&/')
archUpper=$(echo "$efiArch" | tr '[:lower:]' '[:upper:]')
bootArch=$(echo "$archUpper" | sed -E 's/^(X86_64|AARCH64|ARM64)$/\1/')

# --- discover the boot filesystem device (for `set root=...` in grub.cfg) ---
bootFsSearch=""
if [ -n "$bootDevice" ]; then
  case "$bootDevice" in
    search*) bootFsSearch="$bootDevice" ;;
    '('*) bootFsSearch="set root=$bootDevice" ;;
    *) bootFsSearch="set root=($bootDevice)" ;;
  esac
else
  # Host-side discovery: the mounted boot directory's backing partition keeps
  # its UUID on the target, so a `search --fs-uuid` generated here is valid.
  uuid=$("${grubTool}/bin/grub-probe" --target=fs_uuid "$bootDir" 2>/dev/null \
         || @blkid@/bin/blkid -o value -s UUID "$bootDir" 2>/dev/null \
         || true)
  if [ -n "$uuid" ]; then
    bootFsSearch="search --set=root --fs-uuid $uuid"
  fi
fi
[ -z "$bootFsSearch" ] && bootFsSearch="set root=(hd0,1)"

# --- copy kernel + initrd into <boot-dir>/kernels (self-contained boot) ---
kernelsDir="$bootDir/kernels"
mkdir -p "$kernelsDir"
declare -A copied
copyToKernelsDir() {
  local src
  src=$(readlink -f "$1")
  local name
  name=$(echo "$src" | sed -E 's#/nix/store/##; s#/#-#g')
  local dst="$kernelsDir/$name"
  if [ ! -e "$dst" ]; then
    cp "$src" "$dst.tmp" && mv "$dst.tmp" "$dst"
  fi
  copied["$dst"]=1
  echo "/kernels/$name"
}

add_entry() {
  local name="$1" path="$2" opts="$3"
  [ -e "$path/kernel" ] || return 0
  [ -e "$path/initrd" ] || return 0
  local kernel initrd params
  kernel=$(copyToKernelsDir "$path/kernel")
  initrd=$(copyToKernelsDir "$path/initrd")
  params="init=$(readlink -f "$path/init") $(cat "$path/kernel-params")"
  cat <<EOF
menuentry "$name" $opts {
  $bootFsSearch
  linux $kernel $params
  initrd $initrd
}
EOF
}

# --- build the grub.cfg ---
conf="# Automatically generated by install-to-mounted-root; DO NOT EDIT.
set timeout=5
set default=0

"

add_generation() {
  local label="$1" path="$2" opts="$3"
  conf="${conf}$(add_entry "$label" "$path" "$opts")"
  # specialisations
  local link
  for link in "$path"/specialisation/*; do
    [ -e "$link" ] || continue
    local cfgName sublabel
    cfgName=$(cat "$link/configuration-name" 2>/dev/null || true)
    if [ -n "$cfgName" ]; then
      sublabel="$cfgName"
    else
      sublabel="$(basename "$link")"
    fi
    conf="${conf}submenu \"$label - $sublabel\" {
$(add_entry "$label - $sublabel" "$link" "")
}
"
  done
}

add_generation "@distroName@" "$system" ""

# --- install the GRUB core image + modules ---
if [ "$isEfi" -eq 1 ]; then
  # EFI: relative prefix so grub finds its config next to the fallback binary.
  coreDir="$esp/EFI/BOOT"
  prefixDir="$coreDir/grub"
  mkdir -p "$prefixDir/$grubPlatform"
  fallback="$coreDir/BOOT${archUpper}.EFI"
  modulesDir="$grubTool/lib/grub/$grubPlatform"

  if [ ! -d "$modulesDir" ]; then
    echo "error: GRUB modules not found at $modulesDir (wrong --grub-target?)" >&2
    exit 1
  fi

  # Modules needed to read partitions/filesystems and boot the kernel.
  mods="part_gpt part_msdos fat ext2 btrfs xfs lvm search search_fs_uuid"
  mods="$mods search_label configfile normal boot chain gzio font gfxterm"
  mods="$mods linux"
  case "$grubPlatform" in
    *-efi) mods="$mods efi_gop efi_uga" ;;
  esac

  "${grubTool}/bin/grub-mkimage" -O "$grubPlatform" -p "/EFI/BOOT" -o "$fallback" $mods

  cp -r "$modulesDir/." "$prefixDir/$grubPlatform/"

  if [ "$removable" -eq 0 ]; then
    # Also install to the distro-named EFI path (still no NVRAM).
    distroDir="$esp/EFI/@distroId@"
    mkdir -p "$distroDir"
    cp "$fallback" "$distroDir/grub${archUpper}.efi"
  fi

  printf '%s' "$conf" > "$prefixDir/grub.cfg"
else
  # BIOS/MBR: grub-install writes the core image to the device and modules to
  # <boot-dir>/grub; we provide grub.cfg.
  "${grubTool}/bin/grub-install" --target="$grubPlatform" \
    --boot-directory="$bootDir" --no-floppy --force "$device"
  printf '%s' "$conf" > "$bootDir/grub/grub.cfg"
fi

echo "GRUB ($grubPlatform) installed for $system"
