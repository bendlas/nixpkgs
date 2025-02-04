{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel,
  kernelModuleMakeFlags,
}:

stdenv.mkDerivation rec {
  pname = "vhba";
  version = "20240917-unstable";

  src = fetchFromGitHub {
    owner = "cdemu";
    repo = "cdemu";
    rev = "ee6bba585d53891577089e9dd856eb733d8231f8";
    hash = "sha256-pCJYwFW2hkh6XTJ/YWgFunhf/F86KIYV6F7qp4io8P0=";
  };

  sourceRoot = "${src.name}/vhba-module";

  makeFlags = kernelModuleMakeFlags ++ [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "INSTALL_MOD_PATH=$(out)"
  ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  meta = with lib; {
    description = "Provides a Virtual (SCSI) HBA";
    homepage = "https://cdemu.sourceforge.io/about/vhba/";
    platforms = platforms.linux;
    license = licenses.gpl2Plus;
    maintainers = with lib.maintainers; [ bendlas ];
  };
}
