{ lib
, boto3
, botocore
, buildPythonPackage
, click
, configparser
, fetchFromGitHub
, fetchpatch
, fido2
, lxml
, poetry-core
, pyopenssl
, pytestCheckHook
, pythonOlder
, requests
, requests-kerberos
, toml
}:

buildPythonPackage rec {
  pname = "aws-adfs";
  version = "2.4.0";
  format = "pyproject";

  disabled = pythonOlder "3.6";

  src = fetchFromGitHub {
    owner = "venth";
    repo = pname;
    rev = "refs/tags/${version}";
    hash = "sha256-Ya8mI++mraZ1VE0OjBpLoP7IdbJq8aGFNpUir6nQ3J0=";
  };

  nativeBuildInputs = [
    poetry-core
  ];

  propagatedBuildInputs = [
    boto3
    botocore
    click
    configparser
    fido2
    lxml
    pyopenssl
    requests
    requests-kerberos
  ];

  # patches = [
  #   # Apply new fido2 api (See: venth/aws-adfs#243)
  #   (fetchpatch {
  #     url = "https://github.com/venth/aws-adfs/commit/09836d89256f3537270d760d8aa30ab9284725a8.diff";
  #     hash = "sha256-pAAJvOa43BXtyWvV8hsLe2xqd5oI+vzndckRTRol61s=";
  #   })
  # ];

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace 'boto3 = "^1.20.50"' 'boto3 = "*"' \
      --replace 'botocore = ">=1.12.6"' 'botocore = "*"' \
      --replace 'configparser = "5.2"' 'configparser = "*"'
  '';

  nativeCheckInputs = [
    pytestCheckHook
    toml
  ];

  preCheck = ''
    export HOME=$(mktemp -d);
  '';

  pythonImportsCheck = [
    "aws_adfs"
  ];

  meta = with lib; {
    description = "Command line tool to ease AWS CLI authentication against ADFS";
    homepage = "https://github.com/venth/aws-adfs";
    license = licenses.psfl;
    maintainers = with maintainers; [ bhipple ];
  };
}
