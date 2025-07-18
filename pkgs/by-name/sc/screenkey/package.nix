{
  lib,
  fetchFromGitLab,
  wrapGAppsHook3,
  xorg,
  gobject-introspection,
  gtk3,
  libappindicator-gtk3,
  slop,
  python3,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "screenkey";
  version = "1.5";
  pyproject = true;

  src = fetchFromGitLab {
    owner = "screenkey";
    repo = "screenkey";
    rev = "v${version}";
    hash = "sha256-kWktKzRyWHGd1lmdKhPwrJoSzAIN2E5TKyg30uhM4Ug=";
  };

  nativeBuildInputs = [
    wrapGAppsHook3
    # for setup hook
    gobject-introspection
  ];

  buildInputs = [
    gtk3
    libappindicator-gtk3
  ];

  build-system = with python3.pkgs; [ setuptools ];

  dependencies = with python3.pkgs; [
    babel
    pycairo
    pygobject3
    dbus-python
  ];

  # Prevent double wrapping because of wrapGAppsHook3
  dontWrapGApps = true;

  preFixup = ''
    makeWrapperArgs+=(
      --prefix PATH ":" "${lib.makeBinPath [ slop ]}"
      "''${gappsWrapperArgs[@]}"
      )
  '';

  # screenkey does not have any tests
  doCheck = false;

  pythonImportsCheck = [ "Screenkey" ];

  # Fix CDLL python calls for non absolute paths of xorg libraries
  postPatch = ''
    substituteInPlace Screenkey/xlib.py \
      --replace-fail libX11.so.6 ${lib.getLib xorg.libX11}/lib/libX11.so.6 \
      --replace-fail libXtst.so.6 ${lib.getLib xorg.libXtst}/lib/libXtst.so.6
  '';

  meta = with lib; {
    homepage = "https://www.thregr.org/~wavexx/software/screenkey/";
    description = "Screencast tool to display your keys inspired by Screenflick";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    maintainers = [ maintainers.rasendubi ];
    mainProgram = "screenkey";
  };
}
