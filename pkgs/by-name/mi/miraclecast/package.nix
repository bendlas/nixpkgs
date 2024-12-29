{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  glib,
  readline,
  pcre,
  systemd,
  udev,
  iproute2,
}:

stdenv.mkDerivation {
  pname = "miraclecast";
  version = "1.0-20240713";

  src = fetchFromGitHub {
    owner = "albfan";
    repo = "miraclecast";
    rev = "937747fd4de64a33bccf5adb73924c435ceb821b";
    hash = "sha256-y37+AOz8xYjtDk9ITxMB7UeWeMpDH+b6HQBczv+x5zo=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    glib
    pcre
    readline
    systemd
    udev
    iproute2
  ];

  mesonFlags = [
    "-Drely-udev=true"
    "-Dbuild-tests=true"
    "-Dip-binary=${iproute2}/bin/ip"
  ];

  meta = with lib; {
    description = "Connect external monitors via Wi-Fi";
    homepage = "https://github.com/albfan/miraclecast";
    license = licenses.lgpl21Plus;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
