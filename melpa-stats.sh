#!/bin/sh -ex

instantiate () {
    echo -n "Instantiated count "
    nix-instantiate -E "
      with import ./. { config = { allowBroken = true; }; };
      emacsPackagesNg.melpaPackages
    " 2>/dev/null | wc -l
}

(
    cd master
    echo "============================================
          On master"
    nix-store --option keep-derivations false --gc 2>/dev/null
    time instantiate
)


(
    cd patch-crib
    echo "============================================
          On emacs-updater-elisp"
    nix-store --option keep-derivations false --gc 2>/dev/null
    time instantiate
)
