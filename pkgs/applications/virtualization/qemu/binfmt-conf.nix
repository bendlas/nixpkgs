{ stdenv, callPackage, kmod, utillinux, glibc }:

let
  qemu = callPackage ./user-static.nix {};
in stdenv.mkDerivation {
  name = "binfmt-conf-${qemu.name}";
  inherit (qemu) src;
  phases = [ "unpackPhase" "installPhase" "fixupPhase" ];
  installPhase = ''
    mkdir -p $out/share/qemu/binfmt-emulators $out/bin
    substitute scripts/qemu-binfmt-conf.sh $out/share/qemu/binfmt-conf.sh \
      --replace "/usr/local/bin/" "/dev/shm/qemu-binfmt-emulators/" \
      --replace "/sbin/modprobe" "${kmod}/bin/modprobe" \
      --replace " mount " " ${utillinux}/bin/mount "
    #cp -a ${qemu}/bin $out/share/qemu/binfmt-emulators
    for f in $(echo ${qemu}/bin/*); do #`echo $out/share/qemu/binfmt-emulators/*`; do # */
      cp $f prc
      echo "Chmoding $f"
      chmod +w prc
      echo "Patching $f"
      patchelf --set-interpreter /dev/shm/qemu-binfmt-emulators/ld-2.21.so prc
      cp prc $out/share/qemu/binfmt-emulators/$(basename $f)
    done
    echo "#!${stdenv.shell}
mkdir -p /dev/shm/qemu-binfmt-emulators
cp -a $(echo $out/share/qemu/binfmt-emulators/*) ${glibc}/lib/ld-2.21.so  /dev/shm/qemu-binfmt-emulators
sh $out/share/qemu/binfmt-conf.sh
" > $out/bin/enable-qemu-binfmt
    echo "#!${stdenv.shell}
sh -c 'echo -1 > /proc/sys/fs/binfmt_misc/status'
rm -r /dev/shm/qemu-binfmt-emulators
" > $out/bin/disable-qemu-binfmt
    chmod +x $out/bin/enable-qemu-binfmt $out/bin/disable-qemu-binfmt
  '';
}
