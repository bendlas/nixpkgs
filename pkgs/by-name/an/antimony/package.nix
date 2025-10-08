{
  lib,
  stdenv,
  fetchFromGitHub,
  libpng,
  python3,
  libGLU,
  libGL,
  libsForQt5,
  ncurses,
  cmake,
  flex,
  lemon,
  makeDesktopItem,
  copyDesktopItems,
}:

let
  gitRev = "28d444402b88a51aa8a14dfdbe5869101fb73426";
  gitBranch = "develop";
  gitTag = "0.9.3";
in
stdenv.mkDerivation {
  pname = "antimony";
  version = "2025-10-03";

  src = fetchFromGitHub {
    owner = "mkeeter";
    repo = "antimony";
    rev = gitRev;
    sha256 = "sha256-RKxPIIs7ByjMLp32zDAtK0IYYAk1MaMo6JX9SZSTfpQ=";
  };

  patches = [ ./paths-fix.patch ];

  postPatch = ''
    sed -i "s,/usr/local,$out,g" \
    app/CMakeLists.txt app/app/app.cpp app/app/main.cpp
    sed -i "s,python3,${python3.executable}," CMakeLists.txt
  '';

  postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
    install -Dm644 $src/deploy/icon.svg $out/share/icons/hicolor/scalable/apps/antimony.svg
    install -Dm644 ${./mimetype.xml} $out/share/mime/packages/antimony.xml
  '';

  buildInputs = [
    libpng
    python3
    python3.pkgs.boost
    libGLU
    libGL
    libsForQt5.qtbase
    ncurses
  ];

  nativeBuildInputs = [
    cmake
    flex
    lemon
    libsForQt5.wrapQtAppsHook
    copyDesktopItems
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "antimony";
      desktopName = "Antimony";
      comment = "Tree-based Modeler";
      genericName = "CAD Application";
      exec = "antimony %f";
      icon = "antimony";
      categories = [
        "Graphics"
        "Science"
        "Engineering"
      ];
      mimeTypes = [
        "application/x-extension-sb"
        "application/x-antimony"
      ];
      startupWMClass = "antimony";
    })
  ];

  cmakeFlags = [
    "-DGITREV=${gitRev}"
    "-DGITTAG=${gitTag}"
    "-DGITBRANCH=${gitBranch}"
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  ];

  meta = {
    description = "Computer-aided design (CAD) tool from a parallel universe";
    mainProgram = "antimony";
    homepage = "https://github.com/mkeeter/antimony";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ rnhmjoj ];
    platforms = lib.platforms.linux;
  };
}
