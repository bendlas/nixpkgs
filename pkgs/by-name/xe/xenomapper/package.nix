{
  python3,
  lib,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "xenomapper";
  version = "1.0.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "genomematt";
    repo = "xenomapper";
    rev = "v${version}";
    sha256 = "0mnmfzlq5mhih6z8dq5bkx95vb8whjycz9mdlqwbmlqjb3gb3zhr";
  };

  build-system = with python3.pkgs; [ setuptools ];

  dependencies = with python3.pkgs; [ statistics ];

  pythonImportsCheck = [
    "xenomapper.xenomapper"
    "xenomapper.mappability"
  ];

  meta = with lib; {
    homepage = "https://github.com/genomematt/xenomapper";
    description = "Utility for post processing mapped reads that have been aligned to a primary genome and a secondary genome and binning reads into species specific, multimapping in each species, unmapped and unassigned bins";
    license = licenses.gpl3;
    platforms = platforms.all;
    maintainers = [ maintainers.jbedo ];
  };
}
