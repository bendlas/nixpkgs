{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  cython,
  meson-python,
  ninja,
  setuptools,

  # dependencies
  numpy,
  scipy,
  nibabel,
  sympy,
  transforms3d,

  # optional-dependencies
  matplotlib,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  version = "0.6.1";
  pname = "nipy";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "nipy";
    repo = "nipy";
    tag = version;
    hash = "sha256-KGMGu0/0n1CzN++ri3Ig1AJjeZfkl4KzNgm6jdwXB7o=";
  };

  postPatch = ''
    patchShebangs nipy/_build_utils/cythoner.py
  '';

  build-system = [
    cython
    meson-python
    setuptools
    ninja
    numpy
  ];

  dependencies = [
    nibabel
    numpy
    scipy
    sympy
    transforms3d
  ];

  optional-dependencies.optional = [ matplotlib ];

  nativeCheckInputs = [ pytestCheckHook ] ++ optional-dependencies.optional;

  doCheck = false; # partial imports … circular dependencies. needs more time to figure out.

  pythonImportsCheck = [
    "nipy"
    "nipy.testing"
    "nipy.algorithms"
  ];

  meta = with lib; {
    homepage = "https://nipy.org/nipy";
    description = "Software for structural and functional neuroimaging analysis";
    downloadPage = "https://github.com/nipy/nipy";
    license = licenses.bsd3;
  };
}
