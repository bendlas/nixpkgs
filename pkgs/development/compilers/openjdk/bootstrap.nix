{ stdenv
, runCommand, linkFarm, symlinkJoin
, fetchurl, zlib, fastjar, gcj

, version
}:

assert stdenv.hostPlatform.libc == "glibc";

# let
#   fetchboot = version: arch: sha256: fetchurl {
#     name = "openjdk${version}-bootstrap-${arch}-linux.tar.xz";
#     url  = "http://tarballs.nixos.org/openjdk/2018-03-31/${version}/${arch}-linux.tar.xz";
#     inherit sha256;
#   };

#   src = if stdenv.buildPlatform.system == "x86_64-linux" then
#     (if version == "10"    then fetchboot "10" "x86_64" "08085fsxc1qhqiv3yi38w8lrg3vm7s0m2yvnwr1c92v019806yq2"
#     else if version == "8" then fetchboot "8"  "x86_64" "18zqx6jhm3lizn9hh6ryyqc9dz3i96pwaz8f6nxfllk70qi5gvks"
#     else throw "No bootstrap jdk for version ${version}")
#   else if stdenv.buildPlatform.system == "i686-linux" then
#     (if version == "10"    then fetchboot "10" "i686" "1blb9gyzp8gfyggxvggqgpcgfcyi00ndnnskipwgdm031qva94p7"
#     else if version == "8" then fetchboot "8"  "i686" "1yx04xh8bqz7amg12d13rw5vwa008rav59mxjw1b9s6ynkvfgqq9"
#     else throw "No bootstrap for version")
#   else throw "No bootstrap jdk for system ${stdenv.buildPlatform.system}";

#   bootstrap = runCommand "openjdk-bootstrap" {
#     passthru.home = "${bootstrap}/lib/openjdk";
#   } ''
#     tar xvf ${src}
#     mv openjdk-bootstrap $out

#     LIBDIRS="$(find $out -name \*.so\* -exec dirname {} \; | sort | uniq | tr '\n' ':')"

#     find "$out" -type f -print0 | while IFS= read -r -d "" elf; do
#       isELF "$elf" || continue
#       patchelf --set-interpreter $(cat "${stdenv.cc}/nix-support/dynamic-linker") "$elf" || true
#       patchelf --set-rpath "${stdenv.cc.libc}/lib:${stdenv.cc.cc.lib}/lib:${zlib}/lib:$LIBDIRS" "$elf" || true
#     done
#   '';
# in bootstrap

let
  ecj = stdenv.mkDerivation {
    name =  "ecj-4.6.1-gcj";
    buildInputs = [ zlib ];
    buildCommand = ''
      mkdir -p $out/bin
      ${gcj}/bin/gcj -Wl,-Bsymbolic -findirect-dispatch -lgcj -o $out/bin/ecj \
                     --main=org.eclipse.jdt.internal.compiler.batch.Main \
                     ${
          fetchurl {
            #url = "http://central.maven.org/maven2/org/eclipse/jdt/core/compiler/ecj/4.6.1/ecj-4.6.1.jar";
            #sha256 = "1q5dxv28izkg23wrfiyzazvd15z8ldhpnkplffg4dd51yisxmpcw";
            url = "ftp://sourceware.org/pub/java/ecj-latest.jar";
            sha256 = "98fd128f1d374d9e42fd9d4836bdd249c6d511ebc6c0df17fbc1b9df96c3d781";
          }
      }
    '';
  };
  result = symlinkJoin {
    name = "java-bootstrap-gcj";
    paths = [
      gcj.cc
      (linkFarm "java-bootstrap-gcj" [
         { name = "lib/jvm/bin/javac"; path = "${ecj}/bin/ecj"; }
         { name = "lib/jvm/bin/fastjar"; path = "${fastjar}/bin/fastjar"; }
       ])
    ];
  };
in result // { home = "${result}/lib/jvm"; }
