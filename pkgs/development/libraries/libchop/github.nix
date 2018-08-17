{ callPackage, fetchFromGitHub }:

let

  sourcePackage = fetchFromGitHub {
    owner = "rootfs";
    repo = "libchop";
    rev = "25750ab5ef82fd3cfce5205d5f1ef07b47098091";
    sha256 = "1v1mr47cvf4rylq14m3rah70769p00myfbxf56qabcmc6jaikgmj";
  };
  releasePackage = callPackage "${sourcePackage}/release.nix" {};

in

  releasePackage.build
