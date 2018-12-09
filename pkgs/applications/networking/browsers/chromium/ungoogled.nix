let
  inherit (import ../../../../../default.nix {}) fetchFromGitHub runCommand;
  version = builtins.readFile ./ungoogled-version;
  pkg = fetchFromGitHub {
    owner = "Eloston";
    repo = "ungoogled-chromium";
    rev = version;
    sha256 = builtins.readFile ./ungoogled-sha256;
  };
in
pkg // {
  chromiumVersion = runCommand "chromium-version" {
    src = pkg;
  } ''
    unpackPhase
    VER=$(awk -F "=" '/chromium_version/ {print $2}' $sourceRoot/version.ini | sed -e 's/^[[:space:]]*//')
    printf %s "$VER" > $out
  '';
}
