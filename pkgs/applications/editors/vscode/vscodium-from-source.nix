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
        outputHash = "sha256-ndV6hqDO0MBYi9DN5wOD06cFIVrL/jO0SKey4tARONo=";
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
        for p in $(find -name package-lock.json)
        do
          echo "Prefetching $p ..."
          ${prefetch-npm-deps}/bin/prefetch-npm-deps "$p" "$out/$(dirname $p)"
          echo "... finished prefetching $p"
        done
      '';

  env = {
    # NODE_OPTIONS = "--openssl-legacy-provider";
    # NODE_ENV = "development";

    # skip unnecessary binary downloads
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

    # ensure the correct node-gyp (from nixpkgs) is used
    NIX_NODEJS_BUILDNPMPACKAGE = "1";
    npm_config_nodedir = nodejs;
    npm_config_node_gyp = "${nodejs}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js";
    npm_config_offline = true;
    npm_config_progress = false;

    # for --fixup-lockfile
    prefetchNpmDeps = "${prefetch-npm-deps}/bin/prefetch-npm-deps";
    forceGitDeps = true;

  };
  nativeBuildInputs = [
    nodejs
    nodejs.python
    pkg-config
    makeWrapper
    git
    jq
    moreutils
    openssh
  ];

  buildInputs =
    lib.optionals (!stdenv.hostPlatform.isDarwin) [ libsecret ]
    ++ [
      libx11
      libxkbfile
      libkrb5
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      cctools
    ];

  # akin to `. get-repo.sh`
  postUnpack = ''
    cp -R ${finalAttrs.vscodeSrc} $sourceRoot/vscode
    chmod -R +w $sourceRoot/vscode
  '';

  preConfigure = ''
    export HOME=$TMPDIR/home
    mkdir -p $HOME
    mkdir -p $TMPDIR
    cp -R $npmCache $TMPDIR/cache
    chmod -R +w $TMPDIR/cache
  '';

  configurePhase = ''
    runHook preConfigure
  ''
  ## unpack all of the prefetched node_modules folders
  # + ''
  #   ( cd vscode
  #     for p in $(find -name package-lock.json -exec dirname {} \;)
  #     do (
  #       echo "Setting up $p/node_modules"
  #       cd $p
  #       if [ -e node_modules ]
  #       then
  #         echo >&2 "File exists $p/node_modules"
  #         exit 0
  #       fi
  #       npm ci --ignore-scripts --cache $TMPDIR/cache/$p
  #       if [ -e node_modules ]
  #       then
  #         patchShebangs node_modules
  #       else
  #         echo >&2 "No $p/node_modules, skipping patchShebangs"
  #       fi

  #     )
  #     done )
  # ''
  + ''
    ( cd vscode
      find -name package-lock.json -exec dirname {} \; | ${parallel}/bin/parallel --will-cite --line-buffer '
        p="{}"
        echo "Setting up $p/node_modules"
        cd $p
        if [ -e node_modules ]
        then
          echo >&2 "File exists $p/node_modules"
          exit 0
        fi
        npm ci --ignore-scripts --cache $TMPDIR/cache/$p
        if [ -e node_modules ]
        then
          . $stdenv/setup
          patchShebangs node_modules
        else
          echo >&2 "No $p/node_modules, skipping patchShebangs"
        fi
      '
    )
  ''
  ## put ripgrep binary into bin so postinstall does not try to download it
  + ''
    find -path "*@vscode/ripgrep" -type d \
      -execdir mkdir -p {}/bin \; \
      -execdir ln -s ${ripgrep}/bin/rg {}/bin/rg \;
  ''
  ## pre-seed node-gyp
  + ''
    mkdir -p $HOME/.node-gyp/${nodejs.version}
    echo 11 > $HOME/.node-gyp/${nodejs.version}/installVersion
    ln -sfv ${nodejs}/include $HOME/.node-gyp/${nodejs.version}
  ''
  ## node-pty build fix
  + ''
    find -path vscode/node_modules/node-pty/scripts/gen-compile-commands.js \
         -exec substituteInPlace {} \
                 --replace-fail "npx node-gyp" "$npm_config_node_gyp" \
               \;
  ''
  ## run postinstall scripts
  + ''
    find vscode -name package.json -type f | ${parallel}/bin/parallel --will-cite --line-buffer '
      if jq -e ".scripts.postinstall" {} >-
      then
        echo >&2 "Running postinstall script in $(dirname {})"
        npm --prefix=$(dirname {}) run postinstall
      fi
      exit 0
    '
  ''
  # ## rebuild native binaries
  # + ''
  #   echo >&2 "Rebuilding from source in ./remote"
  #   npm --prefix vscode/remote rebuild --build-from-source
  # ''
  + ''
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    export SHOULD_BUILD="yes"
    export SHOULD_BUILD_REH="yes"
    export SHOULD_BUILD_REH_WEB="yes"
    export CI_BUILD="no"
    export OS_NAME="linux"
    export VSCODE_ARCH="${vsBuildTarget}"
    export VSCODE_QUALITY="stable"
    export RELEASE_VERSION="${finalAttrs.version}"

    . build.sh    

    runHook postBuild
  '';

  # buildPhase = ''
  #   runHook preBuild

  #   npm run gulp vscode-reh-web-${vsBuildTarget}-min

  #   runHook postBuild
  # '';

  # installPhase = ''
  #   runHook preInstall

  #   mkdir -p $out
  #   cp -R -T ../vscode-reh-web-${vsBuildTarget} $out
  #   ln -sf ${nodejs}/bin/node $out

  #   runHook postInstall
  # '';


})


