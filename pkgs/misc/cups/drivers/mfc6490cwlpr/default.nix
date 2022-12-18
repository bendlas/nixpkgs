{ stdenv
, lib
, fetchurl
, rpm2targz
, dpkg
, makeWrapper
, coreutils
, file
, gawk
, ghostscript
, gnused
, pkgsi686Linux
}:

stdenv.mkDerivation rec {
  pname = "mfc6490cwlpr";
  version = "1.1.2-2";

  src = fetchurl {
    url = "https://download.brother.com/welcome/dlf006179/${pname}-${version}.i386.rpm";
    sha256 = "sha256-IjgpGwu3LiOoCBPjooDH4K2IQHok9fSEnmsU7zxoiNk=";
  };
  unpackPhase = ''
    mkdir -p $out
    rpm2tar -O $src | tar -x -C $out --strip-components=1
  '';

  # src = fetchurl {
  #   url = "https://download.brother.com/welcome/dlf006180/${pname}-${version}.i386.deb";
  #   sha256 = "sha256-0m4ULFJonMpnOE08nSEZMsIl+s9OLZv2AHnsNqhSY9w=";
  # };
  # unpackPhase = ''
  #   dpkg-deb -x $src $out
  # '';

  nativeBuildInputs = [
    dpkg rpm2targz
    makeWrapper
  ];

  dontBuild = true;

  installPhase = ''
    
  '';

  # installPhase = ''
  #   dir=$out/opt/brother/Printers/mfc9140cdn

  #   patchelf --set-interpreter ${pkgsi686Linux.glibc.out}/lib/ld-linux.so.2 $dir/lpd/brmfc9140cdnfilter

  #   wrapProgram $dir/inf/setupPrintcapij \
  #     --prefix PATH : ${lib.makeBinPath [
  #       coreutils
  #     ]}

  #   substituteInPlace $dir/lpd/filtermfc9140cdn \
  #     --replace "BR_CFG_PATH=" "BR_CFG_PATH=\"$dir/\" #" \
  #     --replace "BR_LPD_PATH=" "BR_LPD_PATH=\"$dir/\" #"

  #   wrapProgram $dir/lpd/filtermfc9140cdn \
  #     --prefix PATH : ${lib.makeBinPath [
  #       coreutils
  #       file
  #       ghostscript
  #       gnused
  #     ]}

  #   substituteInPlace $dir/lpd/psconvertij2 \
  #     --replace '`which gs`' "${ghostscript}/bin/gs"

  #   wrapProgram $dir/lpd/psconvertij2 \
  #     --prefix PATH : ${lib.makeBinPath [
  #       gnused
  #       gawk
  #     ]}
  # '';

  meta = with lib; {
    description = "Brother MFC-9140CDN LPR printer driver";
    homepage = "http://www.brother.com/";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.unfree;
    maintainers = with maintainers; [ hexa ];
    platforms = [ "i686-linux" "x86_64-linux" ];
  };
}
