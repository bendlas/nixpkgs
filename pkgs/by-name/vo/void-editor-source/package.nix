{
  lib,
  stdenv,
  callPackage,
  fetchFromGitHub,
  nixosTests,
  commandLineArgs ? "",
  useVSCodeRipgrep ? stdenv.hostPlatform.isDarwin,
  nodejs,
  prefetch-npm-deps,
  jq,
  moreutils,
  git,
  pkg-config,
  cacert,
  runCommand,
  node-gyp,
  libsecret,
  libkrb5,
  xorg,
  ripgrep,
  cctools,
  makeWrapper,
}:

let
  pname = "void";
  version = "b5a41840a0ce29fe5a86b2fa07c26b07f92684d2";
  src = fetchFromGitHub {
    owner = "voideditor";
    repo = "void";
    rev = version;
    hash = "sha256-M9JIBKFPwmtRiwFKgcaD82smWPG0571O7vKVJuHmQSE=";
  };

  vsBuildTarget = {
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
    "x86_64-darwin" = "darwin-x64";
    "aarch64-darwin" = "darwin-arm64";
  }.${stdenv.hostPlatform.system} or "linux-x64";

  nodeModules = runCommand "void-node-modules" {
    inherit src;
    nativeBuildInputs = [ nodejs prefetch-npm-deps jq moreutils git ];
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-ubKENetjCzSZKXkVc9sXArHOd2Do4eU2RMM6702E7Ss==";
    env = {
      FORCE_EMPTY_CACHE = true;
      FORCE_GIT_DEPS = true;
      npm_config_progress = false;
      npm_config_cafile = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    };
  } ''
    runPhase unpackPhase
    export HOME=$TMPDIR/home
    mkdir -p $out
    for p in $(find . -name package-lock.json); do
      ${prefetch-npm-deps}/bin/prefetch-npm-deps "$p" "$out"
      local lockpath=$out/lockfiles/$p
      mkdir -p "$(dirname $lockpath)"
      mv $out/package-lock.json "$lockpath"
    done
  '';

in
stdenv.mkDerivation rec {
  inherit pname version src nodeModules;

  nativeBuildInputs = [
    nodejs
    nodejs.python
    pkg-config
    makeWrapper
    git
    jq
    moreutils
  ];

  buildInputs =
    lib.optionals (!stdenv.hostPlatform.isDarwin) [ libsecret ]
    ++ (with xorg; [
      libX11
      libxkbfile
      libkrb5
    ])
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      cctools
    ];

  env = {
    NODE_OPTIONS = "--openssl-legacy-provider";
    NODE_ENV = "development";

    # skip unnecessary binary downloads
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

    # ensure the correct node-gyp (from nixpkgs) is used
    NIX_NODEJS_BUILDNPMPACKAGE = "1";
    npm_config_nodedir = nodejs;
    npm_config_node_gyp = "${nodejs}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js";

    # use local npm cache (see <nixpkgs/pkgs/build-support/node/build-npm-package/hooks/npm-config-hook.sh>)
    npm_config_cache = nodeModules;
    npm_config_offline = true;
    npm_config_progress = false;

    # for --fixup-lockfile
    prefetchNpmDeps = "${prefetch-npm-deps}/bin/prefetch-npm-deps";
    forceGitDeps = true;
  };

  # remove all built-in extensions, as these are 3rd party extensions that
  # get downloaded from vscode marketplace
  postPatch =
    ''
      jq --slurp '.[0] * .[1]' "product.json" <(
        cat << EOF
      {
        "builtInExtensions": []
      }
      EOF
      ) | sponge product.json
      echo "Updated product.json"
    '' +
    ## build/lib/node.ts picks up nodejs version from remote/.npmrc
    ## and prefetches it into .build/node/v{version}/{target}/node
    ## so we pre-seed it here
    ''
      sed -i 's/target=.*/target="${nodejs.version}"/' remote/.npmrc
      mkdir -p .build/node/v${nodejs.version}/${vsBuildTarget}
      ln -s ${nodejs}/bin/node .build/node/v${nodejs.version}/${vsBuildTarget}/node
    '';

  preConfigure = ''
    export HOME=$TMPDIR/home
    mkdir -p $HOME
    mkdir -p $TMPDIR/cache/_cacache
    # ln -s $nodeModules/_cacache/* $TMPDIR/cache/_cacache
    # mkdir -p $TMPDIR/cache
    cp -R $nodeModules/_cacache $TMPDIR/cache
    chmod -R +w $TMPDIR/cache
    export npm_config_cache=$TMPDIR/cache
  '';

  configurePhase =
    ''
      runHook preConfigure
    ''
    ## unpack all of the prefetched node_modules folders
    + ''
      for p in $(find -name package-lock.json -exec dirname {} \;)
      do (
        echo "Setting up $p/node_modules"
        cd $p
        if [ -e node_modules ]
        then
          echo >&2 "File exists $p/node_modules"
          exit 0
        fi
        npm ci --ignore-scripts
        patchShebangs node_modules
      )
      done
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
      substituteInPlace remote/node_modules/node-pty/scripts/post-install.js \
        --replace-fail "npx node-gyp" "$npm_config_node_gyp"
    ''
    ## rebuild native binaries
    + ''
      echo >&2 "Rebuilding from source in ./remote"
      npm --offline --prefix ./remote rebuild --build-from-source
    ''
    ## run postinstall scripts
    + ''
      find -name package.json -type f -exec sh -c '
        if jq -e ".scripts.postinstall" {} >-
        then
          echo >&2 "Running postinstall script in $(dirname {})"
          npm --offline --prefix=$(dirname {}) run postinstall
        fi
        exit 0
      ' \;
    ''
    + ''
      runHook postConfigure
    '';

  buildPhase = ''
    runHook preBuild
    set -x
    # see https://github.com/voideditor/void-builder/blob/main/build.sh
    npm run buildreact
    npm run gulp compile-build-without-mangling
    npm run gulp compile-extension-media
    npm run gulp compile-extensions-build
    npm run gulp minify-vscode
    # npm run gulp vscode-linux-x64
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R -T ./vscode-linux-x64 $out
    runHook postInstall
  '';

  meta = with lib; {
    description = ''
      Void is the open-source Cursor alternative, built from source.
    '';
    longDescription = ''
      Open source source code editor fork of VSCode adding integrated
      agentic code assistant features, akin to Cursor (i.e., code-cursor).
      This package is built from source.
    '';
    homepage = "https://voideditor.com";
    license = licenses.asl20;
    maintainers = with maintainers; [ jskrzypek ];
    mainProgram = "void";
    platforms = [ "x86_64-linux" ];
  };
} 
