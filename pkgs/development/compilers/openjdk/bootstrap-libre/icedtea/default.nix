{ stdenv, lib, fetchFromGitHub, ant, wget, zip, unzip, cpio, file, libxslt
, zlib, pkg-config, libjpeg, libpng, giflib, lcms2, gtk2, kerberos, attr
, alsaLib, procps, automake, autoconf, cups, which, perl, coreutils, binutils
, cacert, setJavaClassPath
, lndir, libX11, libXtst, libXt
, bootjdk
}:

let

  icedteaSrc = fetchFromGitHub {
    owner = "icedtea-git";
    repo = "icedtea";
    rev = "icedtea-2.6.28";
    hash = "sha256-2XyAQmiK9YKpvgPKl11ratjSgNEE453jHyiWox0oyAk=";
  };

  jdkSrc = fetchFromGitHub {
    owner = "openjdk";
    repo = "jdk7u";
    rev = "jdk7u351-ga";
    hash = "sha256-m/5s/rJEu8e3Biz1HnNWjs5OPHPjIyu5gp10uBgwzUA=";
  };


  /**
   * The JRE libraries are in directories that depend on the CPU.
   */
  architecture =
    if stdenv.system == "i686-linux" then
      "i386"
    else if stdenv.system == "x86_64-linux" then
      "amd64"
    else
      throw "icedtea requires i686-linux or x86_64 linux";

  icedtea = stdenv.mkDerivation {

    name = icedteaSrc.rev;
    src = icedteaSrc;

    outputs = [ "out" "jre" ];

    # TODO: Probably some more dependencies should be on this list but are being
    # propagated instead
    buildInputs = [
      bootjdk ant wget zip unzip cpio file libxslt procps automake
      autoconf which perl coreutils lndir
      zlib libjpeg libpng giflib lcms2 kerberos attr alsaLib cups
      libX11 libXtst gtk2 libXt
    ];

    nativeBuildInputs = [
      pkg-config
    ];

    configureFlags = [
      "--enable-bootstrap"
      "--disable-downloading"

      "--disable-system-sctp"
      "--disable-system-pcsc"
      # "--enable-system-lcms"
      # "--enable-nss"

      "--disable-tests" # TODO run in check phase instead

      "--without-rhino"
      "--with-pax=paxctl"
      "--with-jdk-home=${bootjdk.home}"
      "--with-openjdk-src-dir=${jdkSrc}"

    ];

    ## FIXME also need to patch some source files
    postPatch = ''
      substituteInPlace acinclude.m4 --replace-fail 'attr/xattr.h' 'sys/xattr.h'
    '';

    preConfigure = ''
      export configureFlags="$configureFlags --with-parallel-jobs=$NIX_BUILD_CORES"
      ./autogen.sh
    '';

    preBuild = ''
      make stamps/extract.stamp

      substituteInPlace openjdk/corba/make/common/shared/Defs-utils.gmk --replace-fail '/bin/echo' '${coreutils}/bin/echo'
      substituteInPlace openjdk/jdk/make/common/shared/Defs-utils.gmk --replace-fail '/bin/echo' '${coreutils}/bin/echo'

      patch -p0 < ${./cppflags-include-fix.patch}
      patch -p0 < ${./fix-java-home.patch}

      touch openjdk/jdk/src/solaris/classes/sun/awt/fontconfigs/linux.fontconfig.Gentoo.properties
    '';

    patches = [
      ./0001-make-jpeg-6b-optional.patch
    ];

    NIX_NO_SELF_RPATH = true;

    enableParallelBuilding = true;
    makeFlags = [
      "ALSA_INCLUDE=${alsaLib}/include/alsa/version.h"
      "ALT_UNIXCOMMAND_PATH="
      "ALT_USRBIN_PATH="
      "ALT_DEVTOOLS_PATH="
      "ALT_COMPILER_PATH="
      "ALT_CUPS_HEADERS_PATH=${cups.dev}/include"
      "ALT_OBJCOPY=${binutils}/bin/objcopy"
      "SORT=${coreutils}/bin/sort"
      "UNLIMITED_CRYPTO=1"
    ];

    installPhase = ''
      mkdir -p $out/lib/icedtea $out/share $jre/lib/icedtea

      cp -av openjdk.build/j2sdk-image/* $out/lib/icedtea

      # Move some stuff to top-level.
      mv $out/lib/icedtea/include $out/include
      mv $out/lib/icedtea/man $out/share/man

      # jni.h expects jni_md.h to be in the header search path.
      ln -s $out/include/linux/*_md.h $out/include/

      # Remove some broken manpages.
      rm -rf $out/share/man/ja*

      # Remove crap from the installation.
      rm -rf $out/lib/icedtea/demo $out/lib/icedtea/sample

      # Move the JRE to a separate output.
      mv $out/lib/icedtea/jre $jre/lib/icedtea/
      mkdir $out/lib/icedtea/jre
      lndir $jre/lib/icedtea/jre $out/lib/icedtea/jre

      # The following files cannot be symlinked, as it seems to violate Java security policies
      rm $out/lib/icedtea/jre/lib/ext/*
      cp $jre/lib/icedtea/jre/lib/ext/* $out/lib/icedtea/jre/lib/ext/

      rm -rf $out/lib/icedtea/jre/bin
      ln -s $out/lib/icedtea/bin $out/lib/icedtea/jre/bin

      # Remove duplicate binaries.
      for i in $(cd $out/lib/icedtea/bin && echo *); do
        if [ "$i" = java ]; then continue; fi
        if cmp -s $out/lib/icedtea/bin/$i $jre/lib/icedtea/jre/bin/$i; then
          ln -sfn $jre/lib/icedtea/jre/bin/$i $out/lib/icedtea/bin/$i
        fi
      done

      # Generate certificates.
      pushd $jre/lib/icedtea/jre/lib/security
      rm cacerts
      perl ${./generate-cacerts.pl} $jre/lib/icedtea/jre/bin/keytool ${cacert}/etc/ssl/certs/ca-bundle.crt
      popd

      ln -s $out/lib/icedtea/bin $out/bin
      ln -s $jre/lib/icedtea/jre/bin $jre/bin
    '';

    # FIXME: this is unnecessary once the multiple-outputs branch is merged.
    preFixup = ''
      prefix=$jre stripDirs "$stripDebugList" "''${stripDebugFlags:--S}"
      patchELF $jre
      propagatedNativeBuildInputs+=" $jre"

      # Propagate the setJavaClassPath setup hook from the JRE so that
      # any package that depends on the JRE has $CLASSPATH set up
      # properly.
      mkdir -p $jre/nix-support
      echo -n "${setJavaClassPath}" > $jre/nix-support/propagated-native-build-inputs

      # Set JAVA_HOME automatically.
      mkdir -p $out/nix-support
      cat <<EOF > $out/nix-support/setup-hook
      if [ -z "\$JAVA_HOME" ]; then export JAVA_HOME=$out/lib/icedtea; fi
      EOF
    '';

    meta = {
      description = "Free Java development kit based on OpenJDK 7.0 and the IcedTea project";
      longDescription = ''
        Free Java environment based on OpenJDK 7.0 and the IcedTea project.
        - Full Java runtime environment
        - Needed for executing Java Webstart programs and the free Java web browser plugin.
      '';
      homepage = http://icedtea.classpath.org;
      maintainers = with lib.maintainers; [ bendlas ];
      platforms = lib.platforms.linux;
    };

    passthru = {
      inherit architecture;
      home = "${icedtea}/lib/icedtea";
    };
  };
in icedtea
