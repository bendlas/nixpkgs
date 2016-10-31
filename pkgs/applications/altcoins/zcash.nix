{ stdenv, fetchFromGitHub, runCommand
, fetchurl, ncurses, pkgconfig, automake, autoconf, libtool, autoconf-archive, utillinux
, zlib, db62, boost162, openssl_1_1_0, gmp, procps, gtest, gmock, libsodium }:
let
  version = "v1.0.1";
  sha256 = "0w198gq9gcxss7k1f0lg37658xqk9b7ypk5b504pgnkby4cab2yv";

  ## From depends/packages/libsnark.mk
  snarkVersion = "2e6314a9f7efcd9af1c77669d7d9a229df86a777";
  snarkSha256 = "0k4jhgc251d3ymga0sc1wiqhgklayr5d94n15jlb3n2lnqra07d5";

  boost = boost162;
  db = db62;
  openssl = openssl_1_1_0;

  libsnark = stdenv.mkDerivation {
    name = "libsnark-${snarkVersion}";
    src = fetchFromGitHub {
      owner = "zcash";
      repo = "libsnark";
      rev = snarkVersion;
      sha256 = snarkSha256;
    };
    buildInputs = [ gmp boost openssl procps zlib libsodium ];
    buildPhase = ''
      CXXFLAGS="-fPIC -DBINARY_OUTPUT -DNO_PT_COMPRESSION=1 -ggdb" make lib CURVE=ALT_BN128 MULTICORE=1 NO_PROCPS=1 NO_GTEST=1 NO_DOCS=1 STATIC=1 NO_SUPERCOP=1 FEATUREFLAGS=-DMONTGOMERY_OUTPUT OPTFLAGS="-O2 -march=x86-64"
    '';
    installPhase = ''
      make install STATIC=1 PREFIX=$out CURVE=ALT_BN128 NO_SUPERCOP=1
    '';
  };

  libboost_system_mt = runCommand "libboost_system_mt" {} ''
    mkdir -p $out/lib
    ln -s ${boost}/lib/libboost_system.a $out/lib/libboost_system-mt.a
  '';

  ## Sprout keys, lifted from zcutils/fetch-params.sh
  paramsDir = runCommand "zcash-params" {} ''
    mkdir $out
    ln -s ${fetchurl {
      url = https://z.cash/downloads/sprout-verifying.key;
      sha256 = "4bd498dae0aacfd8e98dc306338d017d9c08dd0918ead18172bd0aec2fc5df82";
    }} $out/sprout-verifying.key
    ln -s ${fetchurl {
      url = https://z.cash/downloads/sprout-proving.key;
      sha256 = "8bc20a7f013b2b58970cddd2e7ea028975c88ae7ceb9259a5344a16bc2c0eef7";
    }} $out/sprout-proving.key
  '';
in
stdenv.mkDerivation {

  name = "zcash-${version}";

  src = fetchFromGitHub {
    owner = "zcash";
    repo = "zcash";
    inherit sha256;
    rev = version;
  };

  nativeBuildInputs = [
    automake autoconf pkgconfig libtool autoconf-archive utillinux
    <nixpkgs/pkgs/build-support/setup-hooks/separate-debug-info.sh>
  ];
  buildInputs = [ zlib db ncurses boost openssl gmp libsnark libsodium
                  libboost_system_mt gtest gmock ];

  outputs = [ "out" "debug" ];

  postUnpack = ''
    (cd $sourceRoot
     rm build-aux/m4/ax*.m4)
  '';

  configurePhase = ''
    ./autogen.sh
    ./configure --with-gui=no --enable-hardening \
      --host=x86_64-unknown-linux-gnu --build=x86_64-unknown-linux-gnu \
      --prefix=$out --with-boost=${boost} \
      CPPFLAGS="-I${libsnark}/include" \
      CXXFLAGS="-fwrapv -fno-strict-aliasing"
  '';

  makeFlags = [ "V=1" ];

  postInstall = ''
    cat > $out/bin/zcash-install-params << 'EOF'
      #!${stdenv.shell} -e

      PD=$HOME/.zcash-params
      if [ -e $PD ]
      then echo "ERROR $PD already exists!"
           exit 1
      else ln -s ${paramsDir} $PD
      fi
    EOF
    chmod +x $out/bin/zcash-install-params
  '';

}
