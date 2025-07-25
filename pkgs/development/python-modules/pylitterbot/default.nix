{
  lib,
  aiohttp,
  aioresponses,
  buildPythonPackage,
  deepdiff,
  fetchFromGitHub,
  poetry-core,
  poetry-dynamic-versioning,
  pycognito,
  pyjwt,
  pytest-aiohttp,
  pytest-freezegun,
  pytestCheckHook,
  pythonOlder,
}:

buildPythonPackage rec {
  pname = "pylitterbot";
  version = "2024.2.2";
  pyproject = true;

  disabled = pythonOlder "3.10";

  src = fetchFromGitHub {
    owner = "natekspencer";
    repo = "pylitterbot";
    tag = "v${version}";
    hash = "sha256-FKBgvP3qXT3nKHn5R9pp4nYNX+mO4vfDi5fzQ5+y1Nc=";
  };

  pythonRelaxDeps = [ "deepdiff" ];

  build-system = [
    poetry-core
    poetry-dynamic-versioning
  ];

  dependencies = [
    aiohttp
    deepdiff
    pycognito
    pyjwt
  ];

  nativeCheckInputs = [
    aioresponses
    pytest-aiohttp
    pytest-freezegun
    pytestCheckHook
  ];

  pythonImportsCheck = [ "pylitterbot" ];

  meta = with lib; {
    description = "Modulefor controlling a Litter-Robot";
    homepage = "https://github.com/natekspencer/pylitterbot";
    changelog = "https://github.com/natekspencer/pylitterbot/releases/tag/${src.tag}";
    license = with licenses; [ mit ];
    maintainers = with maintainers; [ fab ];
  };
}
