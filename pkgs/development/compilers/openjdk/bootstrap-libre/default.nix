{ lib, newScope, pkgs, fetchurl, fetchpatch, fetchzip }:

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
    # TODO port jar repack
  };

  ecj_3_2_2 = stdenv.mkDerivation rec {
    pname = "ecj";
    version = "3.2.2";
    src = fetchzip {
      stripRoot = false;
      url = "http://archive.eclipse.org/eclipse/downloads/drops/R-${version}-200702121330/ecjsrc.zip";
      # sha256 = "05hj82kxd23qaglsjkaqcj944riisjha7acf7h3ljhrjyljx8307";
      # hash = "sha256-BwzUJfUyQ0kHPI6po6DUMWZCkmRYTanpU3iI1qdAEhY=";
      hash = "sha256-Hdt/yYaZOQOV8bKIQz+xouX8iPr2eV3z6zh9R376I3o=";
    };
    env.CLASSPATH = "${jamvm_1_5_1}/lib/rt.jar:${
      lib.concatStringsSep ":"
        (map (j: "${ant_1_8_4}/lib/${j}")
          [ "ant-antlr.jar" "ant-apache-bcel.jar" "ant-apache-bsf.jar" "ant-apache-log4j.jar"
            "ant-apache-oro.jar" "ant-apache-regexp.jar" "ant-apache-resolver.jar" "ant-apache-xalan2.jar"
            "ant-commons-logging.jar" "ant-commons-net.jar" "ant-jai.jar" "ant-javamail.jar" "ant-jdepend.jar"
            "ant-jmf.jar" "ant-jsch.jar" "ant-junit.jar" "ant-junit4.jar" "ant-launcher.jar" "ant-netrexx.jar"
            "ant-swing.jar" "ant.jar" ])}";
    nativeBuildInputs = [ jikes_1_22 fastjar ];
    buildPhase = ''
      echo > manifest "Manifest-Version: 1.0
      Main-Class: org.eclipse.jdt.internal.compiler.batch.Main
      "
      jikes $(find . -name "*.java")
      fastjar cvfm ecj-bootstrap.jar manifest .
    '';
    installPhase = ''
      mkdir -p $out/share/java $out/bin
      cp ecj-bootstrap.jar $out/share/java
      substitute ${./ecj-javac.sh.in} $out/bin/javac \
        --subst-var-by shell "${stdenv.shell}" \
        --subst-var-by java "${jamvm_1_5_1}/bin/jamvm" \
        --subst-var-by ecjJar $out/share/java/ecj-bootstrap.jar \
        --subst-var-by bootClasspath "$(JARS=(${classpath_0_93}/share/classpath/{glibj.zip,tools.zip}); IFS=:; echo "''${JARS[*]}")"
      chmod +x $out/bin/javac
    '';
  };

  classpath_0_99 = stdenv.mkDerivation rec {
    pname = "classpath";
    version = "0.99";
    src = fetchurl {
      url = "mirror://gnu/classpath/classpath-${version}.tar.gz";
      sha256 = "1j7cby4k66f1nvckm48xcmh352b1d1b33qk7l6hi7dp9i9zjjagr";
      # hash = "";
    };

    patches = [
      (fetchpatch {
        url = "https://git.savannah.gnu.org/cgit/guix.git/plain/gnu/packages/patches/classpath-aarch64-support.patch";
        hash = "sha256-EI4BPE/z96Dpw7gK00ehKpWimkr1hKZBVRv/pr/tfts=";
      })
    ];
    nativeBuildInputs = [ fastjar libtool pkg-config ];
    configureFlags = [
      "JAVAC=${ecj_3_2_2}/bin/javac"
      "JAVA=${jamvm_1_5_1}/bin/jamvm"
      "--with-ecj-jar=${ecj_3_2_2}/share/java/ecj-bootstrap.jar"
      "GCJ_JAVAC_TRUE=no"
      "ac_cv_prog_java_works=yes"
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

  jdk5_jamvm_classpath = pkgs.runCommand "jdk5-jamvm-classpath" {
    passthru.home = jdk5_jamvm_classpath;
  } ''
      classpathTool() {
        substitute ${./classpath-tool.sh.in} "$out/bin/$1" \
          --subst-var-by shell "${stdenv.shell}" \
          --subst-var-by java "${jamvm_1_5_1}/bin/jamvm" \
          --subst-var-by classpath "${classpath_0_99}" \
          --subst-var-by toolPkg "$1" \
          --subst-var-by mainClass "$2"
        chmod +x "$out/bin/$1"
      }
      mkdir -p $out/bin $out/lib $out/jre/lib
      classpathTool javah Main
      classpathTool rmic Main
      classpathTool rmid Main
      classpathTool orbd Main
      classpathTool rmiregistry Main
      classpathTool native2ascii Native2ASCII
      ln -s ${jamvm_1_5_1}/bin/jamvm $out/bin/java
      ln -s ${ecj_3_2_2}/bin/javac $out/bin/javac
      ln -s ${fastjar}/bin/fastjar $out/bin/jar
      ln -s ${ecj_3_2_2}/lib/tools.zip $out/lib/tools.jar
      ln -s ${classpath_0_99}/share/classpath/glibj.zip $out/jre/lib/rt.jar
  '';

  inherit (pkgs) fetchurl lib wget cpio file libxslt procps which perl
    coreutils binutils cacert libjpeg libpng giflib lcms2
    kerberos attr alsaLib cups gtk2 setJavaClassPath;

  inherit (pkgs.xorg) libX11 libXtst lndir libXt;

  icedtea_2_5_5 = lib.callPackageWith self ./icedtea {
    bootjdk = jdk5_jamvm_classpath;
    autoconf = pkgs.autoconf269;
    ant = ant_1_8_4;
  };

})
