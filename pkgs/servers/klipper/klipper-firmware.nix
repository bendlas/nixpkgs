{
  stdenv,
  lib,
  pkg-config,
  pkgsCross,
  bintools-unwrapped,
  libffi,
  libusb1,
  wxGTK32,
  python3,
  gcc-arm-embedded,
  klipper,
  avrdude,
  stm32flash,
  mcu ? "mcu",
  firmwareConfig ? ./simulator.cfg,
}:
stdenv.mkDerivation rec {
  name = "klipper-firmware-${mcu}-${version}";
  version = klipper.version;
  src = klipper.src;

  nativeBuildInputs = [
    python3
    pkgsCross.avr.stdenv.cc
    gcc-arm-embedded
    bintools-unwrapped
    libffi
    libusb1
    avrdude
    stm32flash
    pkg-config
    wxGTK32 # Required for bossac
  ];

  preBuild = "cp ${firmwareConfig} ./.config";

  postPatch = ''
    patchShebangs .
  '';

  makeFlags = [
    "V=1"
    "KCONFIG_CONFIG=${firmwareConfig}"
    "WXVERSION=3.2"
  ];

  inherit mcu;

  installPhase = ''
    installOut=$out/share/klipper/firmware/$mcu
    mkdir -p $installOut
    cp ./.config $installOut/config
    cp out/klipper.bin $installOut/ || true
    cp out/klipper.elf $installOut/ || true
    cp out/klipper.uf2 $installOut/ || true
  '';

  dontFixup = true;

  meta = with lib; {
    inherit (klipper.meta) homepage license;
    description = "Firmware part of Klipper";
    maintainers = with maintainers; [ vtuan10 ];
    platforms = platforms.linux;
  };
}
