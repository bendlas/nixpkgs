{ stdenv, fetchsvn, buildFHSUserEnv

, fetchFromGitHub, pkgconfig, fuse }:

let

  buildenv = (buildFHSUserEnv {
    name = "buildenv";
    targetPkgs = pkgs: [ pkgs.gnumake pkgs.perl pkgs.autoconf ];
#    multiPkgs = pkgs: [ pkgs.dpkg ];
    runScript = "make";
    #extraBindMounts = [ "/data=/data" "/foo" ];
  }).env;

  vdfuse = stdenv.mkDerivation rec {
    name = "vdfuse-${rev}";
    rev = "30f2fddfe46b3f0b080a0be8ed22800ac65413f0";
    src = fetchFromGitHub {
      owner = "Thorsten-Sick";
      repo = "vdfuse";
      inherit rev;
      sha256 = "0qn3k2mrr0ysvnxmfmvj81fzvzcixkbq7ln2j9nxmbjkq1g85c7d";
    };
    buildInputs = [
      fuse
    ];
    nativeBuildInputs = [
      pkgconfig
    ];
  };

  enoch = stdenv.mkDerivation rec {
    name = "enoch-chameleon-${rev}";
    rev = "2891";
    src = fetchsvn {
      inherit rev;
      url = http://forge.voodooprojects.org/svn/chameleon;
      sha256 = "0bf946j35myv03zcrk4gqf7ny167lfg2xkxhrifc94mkbf73bqn0";
    };
    inherit buildenv vdfuse;
    buildPhase = ''
      $buildenv/bin/chroot-user
    '';
  };
in

enoch
