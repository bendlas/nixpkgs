{
  stdenv,
  lib,
  fetchFromGitHub,
  cmake,
  pkg-config,
  libsForQt5,
  dtkgui,
  gsettings-qt,
  gtk3,
  xorg,
  iconv,
}:

stdenv.mkDerivation rec {
  pname = "dde-appearance";
  version = "1.1.29";

  src = fetchFromGitHub {
    owner = "linuxdeepin";
    repo = pname;
    rev = version;
    hash = "sha256-M39EugV0uGCIaXK4isTQpHd6Rh2Vl6sg3Jp8JIEFEE4=";
  };

  postPatch = ''
    substituteInPlace src/service/impl/appearancemanager.cpp \
      src/service/modules/{api/compatibleengine.cpp,subthemes/customtheme.cpp,background/backgrounds.cpp} \
      misc/dconfig/org.deepin.dde.appearance.json \
      fakewm/dbus/deepinwmfaker.cpp \
      --replace "/usr/share" "/run/current-system/sw/share"

    for file in $(grep -rl "/usr/bin/dde-appearance"); do
      substituteInPlace $file --replace "/usr/bin/dde-appearance" "$out/bin/dde-appearance"
    done

    substituteInPlace src/service/modules/api/themethumb.cpp \
      --replace "/usr/lib/deepin-api" "/run/current-system/sw/lib/deepin-api"

    substituteInPlace fakewm/dbus/deepinwmfaker.cpp \
      --replace "/usr/lib/deepin-daemon" "/run/current-system/sw/lib/deepin-daemon"

    substituteInPlace src/service/modules/api/locale.cpp \
      --replace "/usr/share/locale/locale.alias" "${iconv}/share/locale/locale.alias"
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    libsForQt5.wrapQtAppsHook
  ];

  buildInputs = [
    dtkgui
    gsettings-qt
    gtk3
    libsForQt5.kconfig
    libsForQt5.kwindowsystem
    libsForQt5.kglobalaccel
    xorg.libXcursor
    xorg.xcbutilcursor
  ];

  cmakeFlags = [
    "-DDSG_DATA_DIR=/run/current-system/sw/share/dsg"
    "-DSYSTEMD_USER_UNIT_DIR=${placeholder "out"}/lib/systemd/user"
  ];

  meta = with lib; {
    description = "Program used to set the theme and appearance of deepin desktop";
    homepage = "https://github.com/linuxdeepin/dde-appearance";
    license = licenses.lgpl3Plus;
    platforms = platforms.linux;
    teams = [ teams.deepin ];
  };
}
