# Variants of packages to develop / test against
let pkgs = import ./default.nix { }; in
with pkgs;
let
  ccacheStdenv = ( overrideCC stdenv (ccacheWrapper.override {
    extraConfig = ''
      export CCACHE_COMPRESS=1
      export CCACHE_DIR=/var/cache/ccache-chromium
      export CCACHE_UMASK=007
    '';
  })); in pkgs // rec {
  emacs-empty = emacsPackages.emacsWithPackages (_: []);
  chromiumWidevine = pkgs.chromium.override {
    enablePepperFlash = true;
    enableWideVine = true;
    pulseSupport = true;
  };
  chromiumVaapi = chromium.override {
    useVaapi = true;
    enableWideVine = false;
    enablePepperFlash = false;
    proprietaryCodecs = true;
  };
  dwarf-fortress = pkgs.dwarf-fortress.override {
    theme = "phoebus";
    enableDFHack = true;
    enableSoundSense = true;
    enableStoneSense = true;
    enableTWBT = true;
  };
  aarch64-cross = import ./default.nix {
    crossSystem = lib.systems.examples.aarch64-multiplatform;
    config = (import /etc/nixos/nixpkgs-config.nix // {
      oraclejdk.accept_license = true;
      packageOverrides = pkgs: {
        chromium = pkgs.chromium.override {
          useVaapi = true;
          enableWideVine = false;
          enablePepperFlash = false;
          proprietaryCodecs = true;
        };
      };
    });
  };
  systems = {
    rpi3 = ./rpi3.nix;
    test = import ./nixos {
      configuration = ../bendlas-nixos-config/test-config.nix;
    };
  };

  kernel = systems.test.config.boot.kernelPackages.kernel.dev;

  clojure-jfx = pkgs.clojure.override {
    jdk = pkgs.jdk11;
  };

  lein-prj = (pkgs.stdenv.mkDerivation {
    name = "asdf";
    buildInputs = with pkgs;
    [
      # Clojure
      jdk8
      leiningen
    ];
  });

  whoami = runCommand "whoami" {} ''
    id
    echo `id` > $out
  '';

  ccache-test = ccacheStdenv.mkDerivation {
    name = "ccache-test";
    MAIN_C = writeText "main.c" ''
      #include <stdio.h>

      int main(int argc, char **argv) {
        printf("Hello World\n");
        return(0);
      }
    '';
    buildCommand = ''
      mkdir -p $out/bin
      cc -o $out/bin/main $MAIN_C
    '';
  };
  ccacheUtillinux = utillinux.override { stdenv = ccacheStdenv; };

  testLazyPkgs = buildLazyBinaries {
    # nixpkgs = <nixpkgs>;
    catalog = {
      utillinux = [ "chcpu" "fstrim" "kill" "last" "ldattach" "lscpu" ];
    };
    installed = [ "fstrim" "kill" "less" "nmap" "chromium" "firefox" ];
  };
}
