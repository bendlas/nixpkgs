#!/bin/sh

nix-shell --pure -p git "
  with import ./. { config = { }; };
  emacsWithPackages (epkgs: with epkgs; [ magit magithub cljsbuild-mode clojars nix-mode clj-refactor clojure-mode ])
" --run "HOME=/tmp emacs"
