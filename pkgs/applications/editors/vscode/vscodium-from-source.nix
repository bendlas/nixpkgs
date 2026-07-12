{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchpatch,
  buildGoModule,
  makeWrapper,
  cacert,
  moreutils,
  jq,
  git,
  openssh,
  pkg-config,
  runCommand,
  nodejs,
  node-gyp,
  libsecret,
  libkrb5,
  libx11,
  libxkbfile,
  ripgrep,
  cctools,
  nixosTests,
  prefetch-npm-deps,
  parallel,
}:
let

  system = stdenv.hostPlatform.system;

  vsBuildTarget =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      x86_64-darwin = "darwin-x64";
      aarch64-darwin = "darwin-arm64";
    }
    .${system} or (throw "Unsupported system ${system}");

in
stdenv.mkDerivation (finalAttrs: {
  pname = "vscodium";
  version = "1.126.04524";

  src = fetchFromGitHub {
    owner = "VSCodium";
    repo = "vscodium";
    rev = finalAttrs.version;
    hash = "sha256-1L/On6G8CQpeJlwhHkJr2YHNSXkwA4kgFjvTtNDrwuM=";
  };

  vscodeSrc = fetchFromGitHub {
    owner = "Microsoft";
    repo = "vscode";
    rev = (lib.importJSON "${finalAttrs.src}/upstream/stable.json").commit;
    hash = "sha256-oJ/e2o4XzPtxe4/Aua5aiR2/ERVs4YR9ErKiI6oWvRU=";
  };

  ## fetchNpmDeps doesn't correctly process git dependencies
  ## presumably because of https://github.com/npm/cli/issues/5170
  ## therefore, we're fetching all the node_module folders into
  ## a single FOD, and unpack it in configurePhase
  npmCache =
    runCommand "vscodium-npm-cache"
      {
        src = finalAttrs.vscodeSrc;
        # nativeBuildInputs = [ git ];
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-1AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        env = {
          FORCE_EMPTY_CACHE = true;
          FORCE_GIT_DEPS = true;
          NODE_ENV = "development";
          npm_config_progress = false;
          npm_config_cafile = "${cacert}/etc/ssl/certs/ca-bundle.crt";
        };
      }
      ''
        runPhase unpackPhase
        export HOME=$TMPDIR/home
        mkdir $out
        find -name package-lock.json | ${parallel}/bin/parallel --will-cite -j0 --line-buffer --retries 4 '
          echo "Prefetching {} ..."
          ${prefetch-npm-deps}/bin/prefetch-npm-deps "{}" "$out/$(dirname {})"
          echo "... finished prefetching {}"
        '
      '';

})


