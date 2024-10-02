{ fetchFromGitHub, lib, stdenv, ncompress, libX11 }:

stdenv.mkDerivation rec {
  pname = "stalin";
  version = "0.12-unstable-2020-09-27";

  src = fetchFromGitHub {
    owner = "barak";
    repo = "stalin";
    rev = "351282466006515ae0a33467e51588ced042022b";
    hash = "sha256-GoR2+9W7DQODO9/n0sWubjUbJh8XlOYNgqCXdOra7b8=";
  };

  buildInputs = [ ncompress libX11 ];

  buildPhase = "./build ";

  installPhase = ''
    mkdir -p "$out/bin"
    cp stalin "$out/bin"

    mkdir -p "$out/man/man1"
    cp stalin.1 "$out/man/man1"

    mkdir -p "$out/share/emacs/site-lisp"
    cp stalin.el "$out/share/emacs/site-lisp"

    mkdir -p "$out/doc/stalin-${version}"
    cp README "$out/doc/stalin-${version}"

    mkdir -p "$out/share/stalin-${version}/include"
    cp "include/"* "$out/share/stalin-${version}/include"

    substituteInPlace "$out/bin/stalin" \
      --replace "$PWD/include/stalin" "$out/share/stalin-${version}/include/stalin"
    substituteInPlace "$out/bin/stalin" \
      --replace "$PWD/include" "$out/share/stalin-${version}/include"
  '';

  meta = {
    homepage = "https://github.com/barak/stalin";
    license = lib.licenses.gpl2Plus;
    description = "Optimizing Scheme compiler";

    maintainers = [ ];
    platforms = ["i686-linux"];  # doesn't want to work on 64-bit platforms
  };
}
