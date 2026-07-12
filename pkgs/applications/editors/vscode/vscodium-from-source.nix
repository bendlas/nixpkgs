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
  curl,
  pkg-config,
  runCommand,
  nodejs_24,
  node-gyp,
  libsecret,
  libkrb5,
  libx11,
  libxkbfile,
  ripgrep,
  cctools,
  nixosTests,
  fetch-npm-deps-reentrant,
  parallel,
}:
let

  nodejs = nodejs_24;

  system = stdenv.hostPlatform.system;

  # vscodium's build.sh expects the *arch* component only (x64/arm64); it
  # prepends the platform (linux/darwin) itself when composing output paths
  # such as VSCode-linux-${vsBuildArch} and vscode-reh-web-linux-${vsBuildArch}.
  vsBuildArch =
    {
      x86_64-linux = "x64";
      aarch64-linux = "arm64";
      x86_64-darwin = "x64";
      aarch64-darwin = "arm64";
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
        inherit (finalAttrs) nativeBuildInputs;
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-qcty/V4ukT64zKZlR8b0wf84S2g72FhGUkOMrmfBGGo=";
        env = {
          FORCE_EMPTY_CACHE = true;
          FORCE_GIT_DEPS = true;
          NODE_ENV = "development";
          npm_config_progress = false;
          npm_config_cafile = "${cacert}/etc/ssl/certs/ca-bundle.crt";
        };
      } ''
        runPhase unpackPhase
        export HOME=$TMPDIR/home
        mkdir $out
        for p in $(find -name package-lock.json)
        do (
          echo "Prefetching $p"
          ${fetch-npm-deps-reentrant.prefetch-npm-deps}/bin/prefetch-npm-deps "$p" "$out"
        )
        done
        rm "$out/package-lock.json"
      '';

  ## Electron headers for the desktop build's native modules.
  ## vscode's build/npm/preinstall.ts (installHeaders) downloads these via
  ## node-gyp from https://electronjs.org/headers; we pre-seed them instead so
  ## the build is offline. The version MUST match vscode's .npmrc target.
  electronHeaders =
    runCommand "vscodium-electron-headers-42.3.0" {
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = "sha256-zkyERMk3KmM0TYM3G5n9EN/3wTWnEiHMlwj5vx1g4aE=";
      nativeBuildInputs = [ curl ];
      env = { TARGET = "42.3.0"; CURL_CA_BUNDLE = "${cacert}/etc/ssl/certs/ca-bundle.crt"; };
    } ''
      curl -fsSL --cacert ${cacert}/etc/ssl/certs/ca-bundle.crt "https://electronjs.org/headers/v$TARGET/node-v$TARGET-headers.tar.gz" -o headers.tgz
      tar -xzf headers.tgz
      mkdir -p "$out/$TARGET"
      cp -R "node_headers/include" "$out/$TARGET/include"
      cp -R "node_headers/src" "$out/$TARGET/src" 2>/dev/null || true
    '';

  ## Node headers for the remote (REH) build's native modules.
  ## vscode's build/npm/preinstall.ts (installHeaders) downloads these from
  ## nodejs.org for the version pinned in remote/.npmrc (target="24.15.0").
  nodeHeaders =
    runCommand "vscodium-node-headers-24.15.0" {
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = "sha256-5W+AGDLccxgfu3fRZh9Lx216nSaC6qP71knPUzjsAv0=";
      nativeBuildInputs = [ curl ];
      env = { TARGET = "24.15.0"; CURL_CA_BUNDLE = "${cacert}/etc/ssl/certs/ca-bundle.crt"; };
    } ''
      curl -fsSL --cacert ${cacert}/etc/ssl/certs/ca-bundle.crt "https://nodejs.org/dist/v$TARGET/node-v$TARGET-headers.tar.gz" -o headers.tgz
      tar -xzf headers.tgz
      mkdir -p "$out/$TARGET"
      cp -R "node-v$TARGET/include" "$out/$TARGET/include"
      cp -R "node-v$TARGET/src" "$out/$TARGET/src" 2>/dev/null || true
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
    # The npmCache FOD pre-seeds the full offline cache. We pin
    # prebuild-install to the cached 7.1.2 in preConfigure so `npm ci`
    # does not re-resolve its "^7.1.2" range to a newer, uncached patch.
    # Keep the build strictly offline.
    npm_config_offline = true;
    npm_config_progress = false;

    # For packages whose install scripts run
    #   $prefetchNpmDeps --fixup-lockfile package-lock.json || [ -n "$forceGitDeps" ]
    # during `npm ci`. Setting `prefetchNpmDeps` lets the fixup run for git deps,
    # and `forceGitDeps` makes the guard succeed even if it cannot (offline).
    prefetchNpmDeps = "${fetch-npm-deps-reentrant.prefetch-npm-deps}/bin/prefetch-npm-deps";
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
    curl
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
    # Export the (shell-expanded) cache path so that `npm ci` invocations
    # without an explicit --cache (e.g. build/npm/preinstall.ts) use the
    # populated cache instead of npm's default cache location.
    export npm_config_cache=$TMPDIR/cache
    # node-gyp stores downloaded headers in its "dev dir". We pre-seed it with
    # the electron + node headers so the native module builds (node-pty, etc.)
    # compile offline instead of trying to fetch them from the network.
    export npm_config_devdir=$TMPDIR/home/.cache/node-gyp
    mkdir -p "$npm_config_devdir/42.3.0"
    cp -R "$electronHeaders/42.3.0" "$npm_config_devdir/42.3.0"
    mkdir -p "$npm_config_devdir/24.15.0/include"
    cp -R "$nodeHeaders/24.15.0/include/node" "$npm_config_devdir/24.15.0/include/node"

    # build/npm/preinstall.ts runs `npm ci` inside build/npm/gyp and then
    # `node-gyp install` to download electron/node headers. We have already
    # installed build/npm/gyp's node-gyp (see the configurePhase loop) and
    # pre-seeded the headers above, so disable that step to keep the offline
    # build from re-running npm ci (which wipes the .bin/node-gyp symlink)
    # and attempting a network download.
    substituteInPlace vscode/build/npm/preinstall.ts \
      --replace-fail 'installHeaders();' '/* installHeaders() skipped: headers pre-seeded offline */'

    # prepare_vscode.sh runs `npm ci` (with install scripts enabled) in the vscode
    # root after copying a minimal .npmrc over vscode/.npmrc. Unlike our
    # configurePhase `npm ci --ignore-scripts`, this invocation re-evaluates the
    # dependency tree and re-resolves the prebuild-install range, then fails
    # offline trying to fetch its package metadata (ENOTCACHED). Native modules are
    # built later via electron-rebuild / node-gyp (headers pre-seeded), so skipping
    # the install scripts here is safe and matches the offline-capable path.
    substituteInPlace prepare_vscode.sh \
      --replace-fail 'CXX=clang++ npm ci && break' 'CXX=clang++ npm ci --ignore-scripts && break' \
      --replace-fail 'npm ci && break' 'npm ci --ignore-scripts && break'

    # The vscode lockfiles declare prebuild-install as a floating range (e.g.
    # "^7.1.2" in the root/remote lockfiles, "^7.0.1" in build/). At build time
    # `npm ci` re-resolves those ranges to the newest published patch (7.1.3),
    # which is not in the offline npmCache and breaks the build with ENOTCACHED.
    # Each lockfile already carries a resolved prebuild-install entry at the exact
    # version the FOD cached (7.1.2 or 7.1.1), so pin every range in that
    # lockfile to its own resolved version. prebuild-install is only ever invoked
    # by native-module install scripts, which we skip via --ignore-scripts, so its
    # only requirement is a consistent, cached version.
    find . -name package-lock.json | while IFS= read -r lock; do
      ver=$(node -e 'const p=(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).packages)||{};for(const k of Object.keys(p)){if(k.endsWith("/prebuild-install")&&p[k].version){console.log(p[k].version);break;}}' "$lock")
      [ -n "$ver" ] || continue
      sed -i -E "s/\"prebuild-install\": \"[^\"]*7\.[0-9]+\.[0-9]+\"/\"prebuild-install\": \"$ver\"/g" "$lock"
    done
  '';

  configurePhase = ''
    runHook preConfigure
  ''
  ## unpack all of the prefetched node_modules folders
  + ''
    ( cd vscode
      for p in $(find -name package-lock.json -not -path '*/extensions/copilot/*' -exec dirname {} \;)
      do (
        echo "Setting up $p/node_modules"
        cd $p
        if [ -e node_modules ]
        then
          echo >&2 "File exists $p/node_modules"
          exit 0
        fi
        npm ci --ignore-scripts --cache $TMPDIR/cache
        if [ -e node_modules ]
        then
          patchShebangs node_modules
        else
          echo >&2 "No $p/node_modules, skipping patchShebangs"
        fi
      )
      done )
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
  + ''
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    export SHOULD_BUILD="yes"
    # the REH (headless remote) build needs a separate `remote` rebuild that is
    # currently not wired up here; it is not required for the desktop + web
    # editions, so skip it for now.
    export SHOULD_BUILD_REH="no"
    export SHOULD_BUILD_REH_WEB="yes"
    export CI_BUILD="no"
    export OS_NAME="${if stdenv.hostPlatform.isDarwin then "osx" else "linux"}"
    export VSCODE_ARCH="${vsBuildArch}"
    export VSCODE_QUALITY="stable"
    export RELEASE_VERSION="${finalAttrs.version}"

    . build.sh

    runHook postBuild
  '';

  outputs = [ "out" "web" ];

  installPhase = ''
    runHook preInstall

    # Desktop build (VSCode-linux-${vsBuildArch}). The electron binary is *not*
    # downloaded during the build (ELECTRON_SKIP_BINARY_DOWNLOAD=1); the
    # electron recombination (symlinking in the nixpkgs electron) is handled
    # separately afterwards.
    mkdir -p "$out"
    cp -R -T "VSCode-linux-${vsBuildArch}" "$out"

    # Web server build (vscode-reh-web-linux-${vsBuildArch}).
    mkdir -p "$web"
    cp -R -T "vscode-reh-web-linux-${vsBuildArch}" "$web"
    ln -sf "${nodejs}/bin/node" "$web/node"

    runHook postInstall
  '';

  passthru.npmCache = finalAttrs.npmCache;
  passthru.electronHeaders = finalAttrs.electronHeaders;
  passthru.nodeHeaders = finalAttrs.nodeHeaders;

  meta = {
    description = "Open source build of VS Code, built from source (desktop and web editions)";
    longDescription = ''
      VSCodium is an open source build of Microsoft's VS Code editor, without
      the Microsoft branding, telemetry and licensing. This package is built
      from source and provides both the desktop (Electron) application and the
      web/remote server build.
    '';
    homepage = "https://github.com/VSCodium/vscodium";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      bobby285271
    ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "code";
  };
})
