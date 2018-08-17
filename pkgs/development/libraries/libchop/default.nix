{ fetchurl, fetchpatch, stdenv, zlib, bzip2, libgcrypt
, gdbm, gperf, tdb, gnutls, db4, libuuid
, lzo, pkgconfig, guile_2_0, avahi, gnulib, autoconf, automake
}:

stdenv.mkDerivation rec {
  name = "libchop-0.5.2";

  src = fetchurl {
    url = "mirror://savannah/libchop/${name}.tar.gz";
    sha256 = "0fpdyxww41ba52d98blvnf543xvirq1v9xz1i3x1gm9lzlzpmc2g";
  };

  patches = [
    ./gets-undeclared.patch ./size_t.patch
    (fetchpatch {
      url = https://github.com/rootfs/libchop/commit/25750ab5ef82fd3cfce5205d5f1ef07b47098091.patch;
      sha256 = "1njciq5b2bxc8y0ggck6mcznz6vkzii3h0qaafzah7z19y0z8vjn";
    })
  ];

  nativeBuildInputs = [ pkgconfig gperf gnulib autoconf automake ];

  buildInputs =
    [ zlib bzip2 lzo
      libgcrypt
      gdbm db4 tdb
      gnutls libuuid
      guile_2_0 avahi
    ];

  doCheck = false;

  # preConfigure = ''
  #   sed -re 's%@GUILE@%&/guile%' -i */Makefile.* Makefile.*
  # '';

  # postInstall = ''
  #   cp utils/chop-backup $out/bin
  #   cp utils/chop-file $out/bin
  # '';

  meta = with stdenv.lib; {
    description = "Tools & library for data backup and distributed storage";

    longDescription =
      '' Libchop is a set of utilities and library for data backup and
         distributed storage.  Its main application is chop-backup, an
         encrypted backup program that supports data integrity checks,
         versioning at little cost, distribution among several sites,
         selective sharing of stored data, adaptive compression, and more.
         The library itself, which chop-backup builds upon, implements
         storage techniques such as content-based addressing, content hash
         keys, Merkle trees, similarity detection, and lossless compression.
         It makes it easy to combine them in different ways.  The
         ‘chop-archiver’ and ‘chop-block-server’ tools, illustrated in the
         manual, provide direct access to these facilities from the command
         line.  It is written in C and has Guile (Scheme) bindings.
      '';

    homepage = https://www.nongnu.org/libchop/;
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [ ];
    platforms = platforms.gnu ++ platforms.linux;
  };
}
