{ stdenv, lib, python, fetchurl, fetchpatch, fixDarwinDylibNames, nativeBuildRoot }:

import ./base.nix {
  version = "64.1";
  sha256 = "1rlnwa57dzclm80dxff1lf6indi34h8s4dbzq5wncf8vsnwvgwcj";
} { inherit stdenv lib fetchurl fixDarwinDylibNames nativeBuildRoot;
    icuPython = python; }
