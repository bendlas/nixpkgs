{ lib, newScope, pkgs, fetchurl, fetchpatch }:

lib.makeScope newScope (self: with self; {
  inherit (pkgs) stdenv
    fastjar libtool pkg-config
    automake autoconf zlib libffi zip
    unzip;

  jikes_1_22 = stdenv.mkDerivation rec {
    pname = "jikes";
    version = "1.22";
    src = fetchurl {
      url = "mirror://sourceforge/jikes/Jikes/${version}/jikes-${version}.tar.bz2";
      # sha256 = "1qqldrp74pzpy5ly421srqn30qppmm9cvjiqdngk8hf47dv2rc0c";
      hash = "sha256-DLAsdjvEQTSfbTjKzVKt92IwLM46COJp8fdfcm5uFOM=";
    };
  };

  classpath_0_93 = stdenv.mkDerivation rec {
    pname = "classpath";
    version = "0.93";
    src = fetchurl {
      url = "mirror://gnu/classpath/classpath-${version}.tar.gz";
      # sha256 = "0i99wf9xd3hw1sj2sazychb9prx8nadxh2clgvk3zlmb28v0jbfz";
      hash = "sha256-3y0JNhKr0j/mfpQJ2JuyqOebFmT+Ky2kDhyO1pPjKUU=";
    };

    # DONE add patches https://git.savannah.gnu.org/cgit/guix.git/tree/gnu/packages/java-bootstrap.scm?id=b31a49cb5ea036a9869f3c2cd40d0f8b99af01f9#n108
    patches = [
      (fetchpatch {
        url = "https://git.savannah.gnu.org/cgit/guix.git/plain/gnu/packages/patches/classpath-miscompilation.patch";
        hash = "sha256-hrd7ff2NvyKWPuXzTkOecNtee+W0Qk7zp8jc+6sG7IQ=";
      })
      (fetchpatch {
        url = "https://git.savannah.gnu.org/cgit/guix.git/plain/gnu/packages/patches/classpath-aarch64-support.patch";
        hash = "sha256-EI4BPE/z96Dpw7gK00ehKpWimkr1hKZBVRv/pr/tfts=";
      })
    ];

    nativeBuildInputs = [ jikes_1_22 fastjar libtool pkg-config ];
    configureFlags = [
      "JAVAC=${jikes_1_22}/bin/jikes"
      "--disable-Werror"
      "--disable-gmp"
      "--disable-gtk-peer"
      "--disable-gconf-peer"
      "--disable-plugin"
      "--disable-dssi"
      "--disable-alsa"
      "--disable-gjdoc"
    ];
    postInstall = ''
      make install-data
    '';
  };

  jamvm_1_5_1 = stdenv.mkDerivation rec {
    pname = "jamvm";
    version = "1.5.1";
    src = fetchurl {
      url = "mirror://sourceforge/jamvm/jamvm/JamVM%20${version}/jamvm-${version}.tar.gz";
      # sha256 = "06lhi03l3b0h48pc7x58bk9my2nrcf1flpmglvys3wyad6yraf36";
      hash = "sha256-ZjiVvWnK86H9pq9e6oJj2Qpf01yo9MMuIhCsQQeIkBo=";
    };
    postUnpack = ''
      rm $sourceRoot/lib/classes.zip
    '';
    patches = [
      ./jamvm151-fix-buffer-overflow-during-class-loading.patch
      (fetchpatch {
        url = "https://git.savannah.gnu.org/cgit/guix.git/plain/gnu/packages/patches/jamvm-1.5.1-aarch64-support.patch";
        hash = "sha256-ZuhHBDbysqxz6ee8PvdryPTjXZvr/r9dOB6OpU9TuJk=";
      })
      (fetchpatch {
        url = "https://git.savannah.gnu.org/cgit/guix.git/plain/gnu/packages/patches/jamvm-1.5.1-armv7-support.patch";
        hash = "sha256-l5rWRHnXZCjcvopTrFVZlACkef4/hw03pLLUininiV0=";
      })
    ];
    ## FIXME only necessary for arm support?
    preConfigure = ''
      autoreconf -vif
    '';
    configureFlags = [
      "--with-classpath-install-dir=${classpath_0_93}"
      "--disable-int-caching"
      "--enable-runtime-reloc-checks"
      "--enable-ffi"
    ];
    nativeBuildInputs = [ autoconf automake libtool zip ];
    buildInputs = [  jikes_1_22 classpath_0_93 zlib libffi ];
    # dontStrip = true;
    separateDebugInfo = true;
  };

  ant_1_8_4 = stdenv.mkDerivation rec {
    pname = "ant";
    version = "1.8.4";
    src = fetchurl {
      url = "mirror://apache/ant/source/apache-ant-${version}-src.tar.bz2";
      # sha256 = "1cg0lga887qz5iizh6mlkxp01lciymrhmp7wzxpl6zpnldxmzrjx";
      hash = "sha256-XeZfe6P2fkNv//zcCnP1kdEAbp+0GvhjLB8fhNSj4LE=";
    };
    nativeBuildInputs = [ jikes_1_22 jamvm_1_5_1 unzip zip ];
    env = {
      JAVA_HOME = jamvm_1_5_1;
      JAVACMD = "${jamvm_1_5_1}/bin/jamvm";
      JAVAC = "${jikes_1_22}/bin/jikes";
      CLASSPATH = "${jamvm_1_5_1}/lib/rt.jar";
      ANT_OPTS = "-Dbuild.compiler=jikes";
      BOOTJAVAC_OPTS = "-nowarn";
      HOME = "/tmp";
    };
    patchPhase = ''
      sed 's/^\("''${JAVACMD}" \)/\1-Xnocompact -Xnoinlining /' -i bootstrap.sh
      sed 's/depends="jars,test-jar"/depends="jars"/g' -i build.xml
    ''
    ## debugging snippet, for starting jamvm in gdb
    ## used for developing ./jamvm151-fix-buffer-overflow-during-class-loading.patch
    ## might come in useful if better detection discovers more overflows in the future
    # + ''
    #   sed 's#^\("''${JAVACMD}" \)#${pkgs.gdb}/bin/gdb -iex "set directories ${
    #     pkgs.runCommand "jamvm-src" {} ''
    #       mkdir -p $out
    #       tar -xzf ${jamvm_1_5_1.src} -C $out --strip-components=1 
    #     ''
    #   }/src:\$cdir:\$cwd" -iex "set debug-file-directory ${jamvm_1_5_1.debug}/lib/debug:/run/current-system/sw/lib/debug" --args \1#' -i bootstrap.sh
    # ''
    ;
    ## plus the necessary build script to run from nix-shell
    ## ± nix-shell . -A jdkBootstrapLibre.ant_1_8_4 --run 'eval "$shellPhase"'
    # shellPhase = ''
    #   cd /tmp/foo
    #   rm -rf apache-ant-1.8.4
    #   unpackPhase
    #   cd apache-ant-1.8.4
    #   eval "$patchPhase"
    #   eval "$buildPhase"
    # '';
    buildPhase = ''
      mkdir -p $out
      touch $HOME/.ant.properties
      # cp build.xml $out
      bash -x bootstrap.sh -Ddist.dir=$out
    '';
  };


})
