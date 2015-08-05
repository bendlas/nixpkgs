{ stdenv, qemu, kmod, utillinux, pkgs}:

with stdenv.lib;
let
  static-libpath = concatStringsSep " " (map (p: "-L ${p}/lib") (with pkgs; [
    glib zlib 
  ]));
in stdenv.mkDerivation {
  name = "user-static-${qemu.name}";
  inherit (qemu) src patches;
  buildInputs = with pkgs; (
    [ python zlib pkgconfig glib ncurses perl pixman attr libcap
      vde2 texinfo libuuid flex bison makeWrapper lzo snappy # libseccomp
      libcap_ng gnutls
    ]);
    #++ optionals (hasSuffix "linux" stdenv.system) [ alsaLib libaio ]);
    
  configureFlags = [
    "--target-list=arm-linux-user"
    "--enable-user"
    "--disable-system"
    #"--enable-seccomp"
    #"--disable-blobs"
    #"--disable-tools"
    #"--disable-debug-info"
    "--disable-pie"
    "--static"
  ]; # ++ optional (hasSuffix "linux" stdenv.system) "--enable-linux-aio";
  makeFlagsArray = [ "LDFLAGS+=\"${static-libpath}\"" ];
  fixupPhase = false;
}
