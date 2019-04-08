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
    printf %s "$(cat $sourceRoot/chromium_version.txt)" > $out
  '';
}
