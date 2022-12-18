{ stdenv, lib, runCommand, fetchurl, rpm2targz, buildFHSUserEnvBubblewrap, writeScript }:
let
  system = stdenv.hostPlatform.system;
  # interpreter = "${stdenv.cc.libc}/lib/ld-linux${lib.optionalString stdenv.is64bit "-x86-64"}.so.2";
  # patchPhase = ''
  #   ln -sf $out/local/Brother/sane/brsaneconfig3 bin/brsaneconfig3
  #   patchelf --set-interpreter ${interpreter} local/Brother/sane/brsaneconfig3
  # '';
  pname = "brscan3";
  version = "0.2.13-1";

  brscan3 = pkgs: pkgs.runCommand "${pname}-${version}-raw" rec {
    inherit pname version;

    src = {
      "i686-linux" = fetchurl {
        url = "https://download.brother.com/welcome/dlf006643/${pname}-${version}.i386.rpm";
        sha256 = "5586fe264c7bd715e598b5d444f2851464ffe72857f2f48486466e7e2957f792";
      };
      "x86_64-linux" = fetchurl {
        url = "https://download.brother.com/welcome/dlf006644/${pname}-${version}.x86_64.rpm";
        sha256 = "b462dbded2d0f7ae511057bd3cb6f8379042b75d996eef2675998a4559cc5556";
      };
    }."${system}" or (throw "Unsupported system: ${system}");

    nativeBuildInputs = [ rpm2targz ];

  } ''
    mkdir -p $out/share
    rpm2tar -O $src | tar -x -C $out --strip-components=2
    echo $out > $out/share/brscan3-store-path
  '';
in buildFHSUserEnvBubblewrap {
  name = "brsaneconfig3";
  runScript = "/bin/brsaneconfig3";
  ## use the trampoline, if you need to shell into the fhsenv
  # runScript = writeScript "trampoline" ''
  #   #!/bin/sh
  #   exec "$@"
  # '';
  # pathsToLink = [ "/local" ];
  # extraBwrapArgs = [
  # ];
  extraBuildCommands = ''
    ln -s $(cat $out/usr/share/brscan3-store-path)/local $out/usr/local
  '';
  targetPkgs = pkgs: [
    (brscan3 pkgs)
  ];
}
