{ lib
, stdenv
, fetchurl
, rpm2targz
, dpkg
, makeWrapper
, coreutils
, gnugrep
, gnused
, mfc6490cwlpr
, pkgsi686Linux
, psutils
}:

stdenv.mkDerivation rec {
  pname = "mfc6490cwcupswrapper";
  version = "1.1.2-2";

  src = fetchurl {
    url = "https://download.brother.com/welcome/dlf006182/${pname}-${version}.i386.deb";
    sha256 = "sha256-sbuNEJMwvd7cPeN+BwZwLhPWOFSWtPkMQFaGeD4MUtc=";
  };
  unpackPhase = ''
    dpkg-deb -x $src $out
  '';
  # src = fetchurl {
  #   url = "https://download.brother.com/welcome/dlf006181/${pname}-${version}.i386.rpm";
  #   sha256 = "sha256-w8hKTGpRZghzCZ/zzIuwqoLcV7/6chqRsQgRFqWrkAw=";
  # };
  # unpackPhase = ''
  #   mkdir -p $out
  #   # rpm2tar -O $src | tar -x -C $out --strip-components=1
  #   rpm2tar -O $src | tar -t
  # '';

  nativeBuildInputs = [
    dpkg rpm2targz
    makeWrapper
  ];

  dontBuild = true;

  installPhase = ''
    echo install
  '';

  # installPhase = ''
  #   lpr=${mfc6490cdnlpr}/opt/brother/Printers/mfc9140cdn
  #   dir=$out/opt/brother/Printers/mfc9140cdn

  #   interpreter=${pkgsi686Linux.glibc.out}/lib/ld-linux.so.2
  #   patchelf --set-interpreter "$interpreter" "$dir/cupswrapper/brcupsconfpt1"

  #   substituteInPlace $dir/cupswrapper/cupswrappermfc9140cdn \
  #     --replace "mkdir -p /usr" ": # mkdir -p /usr" \
  #     --replace '/opt/brother/''${device_model}/''${printer_model}/lpd/filter''${printer_model}' "$lpr/lpd/filtermfc9140cdn" \
  #     --replace '/usr/share/ppd/Brother/brother_''${printer_model}_printer_en.ppd' "$dir/cupswrapper/brother_mfc9140cdn_printer_en.ppd" \
  #     --replace '/usr/share/cups/model/Brother/brother_''${printer_model}_printer_en.ppd' "$dir/cupswrapper/brother_mfc9140cdn_printer_en.ppd" \
  #     --replace '/opt/brother/Printers/''${printer_model}/' "$lpr/" \
  #     --replace 'nup="psnup' "nup=\"${psutils}/bin/psnup" \
  #     --replace '/usr/bin/psnup' "${psutils}/bin/psnup"

  #   mkdir -p $out/lib/cups/filter
  #   mkdir -p $out/share/cups/model

  #   ln $dir/cupswrapper/cupswrappermfc9140cdn $out/lib/cups/filter
  #   ln $dir/cupswrapper/brother_mfc9140cdn_printer_en.ppd $out/share/cups/model

  #   sed -n '/!ENDOFWFILTER!/,/!ENDOFWFILTER!/p' "$dir/cupswrapper/cupswrappermfc9140cdn" | sed '1 br; b; :r s/.*/printer_model=mfc9140cdn; cat <<!ENDOFWFILTER!/'  | bash > $out/lib/cups/filter/brother_lpdwrapper_mfc9140cdn
  #   sed -i "/#! \/bin\/sh/a PATH=${lib.makeBinPath [ coreutils gnused gnugrep ]}:\$PATH" $out/lib/cups/filter/brother_lpdwrapper_mfc9140cdn
  #   chmod +x $out/lib/cups/filter/brother_lpdwrapper_mfc9140cdn
  #   '';

  meta = with lib; {
    description = "Brother MFC-9140CDN CUPS wrapper driver";
    homepage = "http://www.brother.com/";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
    maintainers = with maintainers; [ hexa ];
  };
}
