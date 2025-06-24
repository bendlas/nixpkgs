{
  lib,
  stdenv,
  callPackage,
  vscode-generic,
  fetchurl,
  nixosTests,
  commandLineArgs ? "",
  useVSCodeRipgrep ? stdenv.isDarwin,
}:

let
  pname = "void-editor";
  version = "1.99.30044";

  inherit (stdenv.hostPlatform) system;

  throwSystem = throw "Unsupported system: ${system}";

  archive_fmt = if stdenv.isDarwin then "zip" else "tar.gz";

  mkFetchurl =
    { plat, hash }:
    fetchurl {
      url = "https://github.com/voideditor/binaries/releases/download/${version}/Void-${plat}-${version}.${archive_fmt}";
      inherit hash;
    };

  sources = {
    x86_64-linux = mkFetchurl {
      plat = "linux-x64";
      hash = "sha256-e+uXS1Jxa+dzl+Qg4MEDYl7XFFNlOT7O96oWB2bAagQ=";
    };
    aarch64-linux = mkFetchurl {
      plat = "darwin-x64";
      hash = "sha256-0sgY8dcxJeev48YILI8zEWKWv25zvRBoMOBDOEDnCkw=";
    };
    x86_64-darwin = mkFetchurl {
      plat = "linux-arm64";
      hash = "sha256-013b3v80cWsyJTu5ZO/DNZjnc+VM9OoJ9zzKymAJT1E=";
    };
    aarch64-darwin = mkFetchurl {
      plat = "darwin-arm64";
      hash = "sha256-wTqeEaevv7a0DiCiB2MbGaHOmquYzXDfCdFCMndynu8=";
    };
    armv7l-linux = mkFetchurl {
      plat = "linux-armhf";
      hash = "sha256-pwF7SC4VfTTOPC9xKFXaj6Df8HrVMbgPyQYcJQeCC34=";
    };
  };

  sourceRoot = lib.optionalString (!stdenv.isDarwin) ".";
in
(callPackage vscode-generic rec {
  inherit
    sourceRoot
    commandLineArgs
    useVSCodeRipgrep
    pname
    version
    ;

  # Please backport all compatible updates to the stable release.
  # This is important for the extension ecosystem.
  executableName = "void";
  longName = "Void Editor";
  shortName = "void";

  src = sources.${system} or throwSystem;

  tests = nixosTests.vscodium;

  updateScript = ./update-void-editor.sh;

  meta = with lib; {
    description = ''
      Void is the open-source Cursor alternative.
    '';
    longDescription = ''
      Open source source code editor fork of VSCode adding integrated
      agentic code assitant features, akin to Cursor (i.e., code-cursor).
    '';
    homepage = "https://voideditor.com";
    downloadPage = "https://github.com/voideditor/binaries/releases";
    license = licenses.apsl20;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with maintainers; [ jskrzypek ];
    mainProgram = "void";
    platforms = builtins.attrNames sources;
  };
})
// {
  inherit sources;
}
