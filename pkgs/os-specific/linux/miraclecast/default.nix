{ stdenv, fetchFromGitHub, autoreconfHook, pkgconfig, udev, systemd, glib, readline,
  iproute, gstreamer }:

with stdenv.lib;
stdenv.mkDerivation rec {
  name = "miraclecast-1.0-git-20160402";

  src = fetchFromGitHub {
    owner = "albfan";
    repo = "miraclecast";
    rev = "c94be167c85c6ec8badd7ac79e3dea2e0b73225c";
    sha256 = "1hjga7z6sl9albk4iprcv4nx8r1xkm5cp4c034g3g8d3a4yx45lf";
  };

  patches = ./0001-nix-path-configuration.patch;

  IP = "${iproute}/bin/ip";
  GST_LAUNCH = "${gstreamer}/bin/gst-launch";
  postPatch = ''
    substituteInPlace res/miracle-gst.sh --subst-var GST_LAUNCH
    substituteInPlace src/dhcp/dhcp.c --subst-var IP
  '';
  postInstall = ''
    mkdir -p $out/share/miraclecast $out/etc/dbus-1/system.d
    cp res/*.sh $out/share/miraclecast
    cp res/org.freedesktop.miracle.conf $out/etc/dbus-1/system.d/
  '';

  # INFO: It is important to list 'systemd' first as for now miraclecast
  # links against a customized systemd. Otherwise, a systemd package from
  # a propagatedBuildInput could take precedence.
  buildInputs = [ systemd autoreconfHook pkgconfig udev glib readline ];

  meta = {
    homepage = https://github.com/albfan/miraclecast;
    description = "Connect external monitors via Wi-Fi";
    license = licenses.lgpl21Plus;
    maintainers = with maintainers; [ tstrobel ];
    platforms = platforms.linux;
  };
}
