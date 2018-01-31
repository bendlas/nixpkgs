let
  tpkgs = import ./default.nix {};
  hpkgs = import <nixpkgs> {};
in
(tpkgs.emacsPackagesGen
  # hpkgs.emacs26-nox
  (hpkgs.emacsPackages.emacs)
).json-mode
