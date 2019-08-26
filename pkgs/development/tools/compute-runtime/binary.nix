{ stdenv, pkgs, lib, fetchurl, dpkg, patchelf }:

with builtins;
with lib;
let
  version = "19.32.13826";
  sources = {
    igc-core = [ "1.0.10-2407" "e144824902f4a583f47145463ad7aeda16bbe21d4af645b2a87bc88c7f5251d2" { }];
    igc-opencl = [ "1.0.10-2407" "708c892c9c9052392b960df29c0bbe3f326a00b4b9b54c1b50408bfaaf09f7dd" {
      buildInputs = [ pkgs.opencl-clang self.igc-core ];
    }];
    ocloc = [ version  "290ae5c8d34a4febf31ec820adb9305ba167a7aa84939eb427de4828f3dd8155" {
      buildInputs = [ self.igc-opencl ];
    }];
    opencl = [ version "eec6a91c74a7a62d785541641f4c38486c02aaac87b564645557869ef2ad59c6" {
      postInstall = ''
        mkdir -p $out/etc/OpenCL/vendors
        echo $out/lib/intel-opencl/libigdrcl.so > $out/etc/OpenCL/vendors/intel.icd
      '';
      buildInputs = [ pkgs.intel-gmmlib self.igc-opencl ];
    }];
  };
  pkgVer = pkg: elemAt (getAttr pkg sources) 0;
  sha = pkg: elemAt (getAttr pkg sources) 1;
  extraArgs = pkg: elemAt (getAttr pkg sources) 2;
  url = pkg:
    "https://github.com/intel/compute-runtime/releases/download/${version}/intel-${pkg}_${pkgVer pkg}_amd64.deb";
  intelPackage = name: stdenv.mkDerivation ({
    name = "${name}-${pkgVer name}";
    src = fetchurl {
      url = url name;
      sha256 = sha name;
    };
    nativeBuildInputs = [ dpkg ];
    unpackPhase = ''
      dpkg-deb --info $src
      dpkg-deb --extract $src .
    '';
    buildPhase = ''
      for sofile in $(find . -type f -executable -or  -name "lib*.so*"); do
        chmod +x $sofile
        patchelf --set-rpath $out/lib:$LP $sofile
      done
      for binary in $(find . -path "*/bin/*"); do
        patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $binary
      done
    '';
    installPhase = ''
      mv usr/local $out
      eval "$postInstall"
    '';
    dontPatchELF = true;
    preferLocalBuild = true;
    LP = makeLibraryPath (with pkgs; [
      zlib stdenv.cc.cc.lib 
    ] ++ (extraArgs name).buildInputs or []);
  } // extraArgs name);
  self = mapAttrs (name: props: intelPackage name) sources;
in self
                      
