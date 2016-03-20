{ stdenv, fetchFromGitHub, callPackage, lib
, gtk_doc, autoconf, automake, gettext, libtool, pkgconfig
, gst_all_1, libnice, orc, openssl, json_glib, libpulseaudio
, gnome3, vim, makeWrapper }: let

  gst-sctp = callPackage ./gst-sctp.nix { };
  libseed = callPackage ./libseed.nix {
    inherit (gnome3) gnome_common webkitgtk24x;
  };

in stdenv.mkDerivation {

  name = "openwebrtc-acb49d";
  # name = "openwebrtc-0.3.0";

  src = fetchFromGitHub {
    owner = "EricssonResearch";
    repo = "openwebrtc";
  #  rev = "6bbd82c7266b1ae3d0fae60b28886dc67108b768";
  #  sha256 = "17iswklf8942sl6bnzi7avqn3s4l1ssxqk3fn311chm3438hfjvi";
    rev = "acb49d301f5ab30e908b674d948ab662f193a11c";
    sha256 = "04g1vlvz5pwg14833y80kz8x0mmsj6cihjhy8k905r8zmqgqcjzp";
  };

  buildInputs = [
    gtk_doc autoconf automake gettext libtool pkgconfig
    libnice orc openssl json_glib libpulseaudio
    gst-sctp libseed
    vim ## bc of xxd
    makeWrapper
  ] ++ (with gst_all_1; [
    gstreamer gst-plugins-base gst-plugins-bad gst-plugins-good 
  ]);

  patchPhase = ''
    substituteInPlace owr/openwebrtc-0.3.pc.in \
      --replace "gstreamer-1.0" "gstreamer-1.0 gstreamer-gl-1.0"
    substituteInPlace configure.ac \
      --replace 'PKG_CHECK_MODULES(GSTREAMER, [gstreamer-1.0 >= $GST_REQUIRED gstreamer-rtp-1.0 >= $GST_REQUIRED gstreamer-video-1.0 >= $GST_REQUIRED gstreamer-app-1.0 >= $GST_REQUIRED])' 'PKG_CHECK_MODULES(GSTREAMER, [gstreamer-1.0 >= $GST_REQUIRED gstreamer-rtp-1.0 >= $GST_REQUIRED gstreamer-video-1.0 >= $GST_REQUIRED gstreamer-app-1.0 >= $GST_REQUIRED gstreamer-gl-1.0 >= $GST_REQUIRED])'
  '';

  postInstall = ''
    cat > $out/env <<EOF
    export GST_PLUGIN_SYSTEM_PATH_1_0="$GST_PLUGIN_SYSTEM_PATH_1_0"
    EOF
  '';
  postFixup = ''
    for exe in $(find $out/bin -type f -executable); do
      wrapProgram "$exe" \
        --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "$GST_PLUGIN_SYSTEM_PATH_1_0" \
        --prefix LD_LIBRARY_PATH : "$out/lib" \
        --prefix XDG_DATA_DIRS : "$out/share"
    done
  '';
  preConfigure = "sh autogen.sh";

}
