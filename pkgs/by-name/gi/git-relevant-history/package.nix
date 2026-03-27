{
  lib,
  fetchFromGitHub,
  unstableGitUpdater,
  python3,
  git,
  git-filter-repo,
}:

python3.pkgs.buildPythonApplication {
  pname = "git-relevant-history";
  version = "1.0.0-unstable-2026-03-25";
  format = "setuptools";
  src = fetchFromGitHub {
    owner = "bendlas";
    repo = "git-relevant-history";
    rev = "7a77a560afcfa6bee399157f781f2d5ebc3eefd3";
    hash = "sha256-uXlh6lXH7lImQMgG2fDIP9Mnmq7crOE3Le3KB+niswQ=";
  };
  propagatedBuildInputs = [
    git
    git-filter-repo
    python3.pkgs.docopt
  ];

  passthru.updateScript = unstableGitUpdater { tagPrefix = "v"; };

  meta = {
    description = "Extract only relevant history from git repo";
    homepage = "https://github.com/rainlabs-eu/git-relevant-history";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
    maintainers = [ lib.maintainers.bendlas ];
    mainProgram = "git-relevant-history";
  };
}
