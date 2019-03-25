{ stdenv, fetchurl, fetchpatch, libvdpau, libGLU_combined, libva, pkgconfig }:
let
  archPatch = name: url: sha256:
    fetchpatch {
      inherit name url sha256;
    };
  # libvdpau08patch = (fetchurl { url = "http://sources.gentoo.org/cgi-bin/viewvc.cgi/gentoo-x86/x11-libs/libva-vdpau-driver/files/libva-vdpau-driver-0.7.4-libvdpau-0.8.patch?revision=1.1";
  #                               name = "libva-vdpau-driver-0.7.4-libvdpau-0.8.patch";
  #                               sha256 = "1n2cys59wyv8ylx9i5m3s6856mgx24hzcp45w1ahdfbzdv9wrfbl";
  #                             });
in
stdenv.mkDerivation rec {
  name = "libva-vdpau-driver-0.7.4";
  
  src = fetchurl {
    url = "https://www.freedesktop.org/software/vaapi/releases/libva-vdpau-driver/${name}.tar.bz2";
    sha256 = "1fcvgshzyc50yb8qqm6v6wn23ghimay23ci0p8sm8gxcy211jp0m";
  };

  # patches = [ ./glext85.patch
  #             (fetchurl { url = "http://sources.gentoo.org/cgi-bin/viewvc.cgi/gentoo-x86/x11-libs/libva-vdpau-driver/files/libva-vdpau-driver-0.7.4-VAEncH264VUIBufferType.patch?revision=1.1";
  #                         name = "libva-vdpau-driver-0.7.4-VAEncH264VUIBufferType.patch";
  #                         sha256 = "166svcav6axkrlb3i4rbf6dkwjnqdf69xw339az1f5yabj72pqqs";
  #                       }) ];

  ## see https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=libva-vdpau-driver-chromium
  patches = [
    (archPatch "libva-vdpau-driver-0.7.4-glext-missing-definition.patch"
               "https://git.archlinux.org/svntogit/packages.git/plain/libva-vdpau-driver/trunk/libva-vdpau-driver-0.7.4-glext-missing-definition.patch?id=30c0f732df74a8962a84295ea7589ad9051952cb"
               "776bfe4c101cdde396d8783029b288c6cd825d0cdbc782ca3d94a5f9ffb4558c")
    (archPatch "libva-vdpau-driver-0.7.4-libvdpau-0.8.patch"
               "https://git.archlinux.org/svntogit/packages.git/plain/libva-vdpau-driver/trunk/libva-vdpau-driver-0.7.4-libvdpau-0.8.patch?id=30c0f732df74a8962a84295ea7589ad9051952cb"
               "5e567b026b97dc0e207b6c05410cc1b7b77a58ceb5046801d0ea1a321cba3b9d")
    (archPatch "libva-vdpau-driver-0.7.4-VAEncH264VUIBufferType.patch"
               "https://git.archlinux.org/svntogit/packages.git/plain/libva-vdpau-driver/trunk/libva-vdpau-driver-0.7.4-VAEncH264VUIBufferType.patch?id=30c0f732df74a8962a84295ea7589ad9051952cb"
               "1ae32b8e5cca1717be4a63f09e8c6bd84a3e9b712b933816cdb32bb315dbda98")
    (archPatch "sigfpe-crash.patch"
               "https://bugs.freedesktop.org/attachment.cgi?id=142296"
               "15snqf60ib0xb3cnav5b2r55qv8lv2fa4p6jwxajh8wbvqpw0ibz")
    (archPatch "fallback-x.patch"
               "https://aur.archlinux.org/cgit/aur.git/plain/fallback-x.patch?h=libva-vdpau-driver-chromium&id=d2135e8d7f50f236d88760c699b7cd616b7bdac1"
               "0jxmpg81fzk9abv793rdr5mc9mzgjvhrldadz9v7zmjjzggg9ysi")
    (archPatch "implement-vaquerysurfaceattributes.patch"
               "https://aur.archlinux.org/cgit/aur.git/plain/implement-vaquerysurfaceattributes.patch?h=libva-vdpau-driver-chromium&id=d2135e8d7f50f236d88760c699b7cd616b7bdac1"
               "1dapx3bqqblw6l2iqqw1yff6qifam8q4m2rq343kwb3dqhy2ymy5")
  ];

  nativeBuildInputs = [ pkgconfig ];
  buildInputs = [ libvdpau libGLU_combined libva ];

    # patch -p0 < ${libvdpau08patch}  # use -p0 instead of -p1
  preConfigure = ''
    sed -i -e "s,LIBVA_DRIVERS_PATH=.*,LIBVA_DRIVERS_PATH=$out/lib/dri," configure
  '';

  meta = {
    homepage = https://cgit.freedesktop.org/vaapi/vdpau-driver/;
    license = stdenv.lib.licenses.gpl2Plus;
    description = "VDPAU driver for the VAAPI library";
    platforms = stdenv.lib.platforms.linux;
  };
}
