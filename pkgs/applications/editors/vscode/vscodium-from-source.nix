{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchpatch,
  fetchurl,
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
  zip,
  electron,
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

  # build/gulpfile.reh.ts reads remote/.npmrc's `target=` and expects a node
  # binary at .build/node/v${nodeVersion}/${platform}-${arch}/node, where
  # ${platform} is process.platform (linux/darwin).
  nodeBuildTarget = "${if stdenv.hostPlatform.isDarwin then "darwin" else "linux"}-${vsBuildArch}";

in
stdenv.mkDerivation (finalAttrs:
  let
    # Upstream vscode publishes three built-in extensions only as GitHub
    # release assets; build/lib/builtInExtensions.ts falls back to fromGithub
    # for them. Vendor the exact release .vsix in fixed-output derivations and
    # point product.json at them (see preConfigure) so the bundler uses
    # fromVsix and never touches the network. The sha256 in product.json is
    # the release asset's checksum (hex), converted here to SRI for fetchurl.
    builtInExtensionVsix = lib.listToAttrs (map (ext: {
      name = ext.name;
      value = fetchurl {
        name = "${ext.name}-${ext.version}.vsix";
        url = "${ext.repo}/releases/download/v${ext.version}/${ext.name}.${ext.version}.vsix";
        hash = builtins.convertHash {
          hash = ext.sha256;
          hashAlgo = "sha256";
          toHashFormat = "sri";
        };
      };
    }) (lib.importJSON "${finalAttrs.vscodeSrc}/product.json").builtInExtensions);

    # The `vscode-*-packing` gulp task assembles the desktop app by merging the
    # compiled sources with an Electron distribution. @vscode/gulp-electron can
    # only ingest that distribution as a zip (it streams the entries through
    # gulp-vinyl-zip), so repackage the nixpkgs-provided Electron, which is
    # already patchelf'd for NixOS (interpreter, rpath, libvulkan), instead of
    # downloading the upstream prebuilt. ELECTRON_SKIP_BINARY_DOWNLOAD only
    # covers the npm `electron` package and does not stop this path; the zip is
    # served to @electron/get through ELECTRON_MIRROR (see preConfigure). The
    # version in the file name still comes from vscode's .npmrc so that
    # gulp-electron looks for the expected name.
    electronVersion = builtins.head (
      builtins.match ".*target=\"([0-9.]+)\".*" (
        builtins.replaceStrings [ "\n" ] [ " " ] (builtins.readFile "${finalAttrs.vscodeSrc}/.npmrc")
      )
    );
    electronPlatform = if stdenv.hostPlatform.isDarwin then "darwin" else "linux";
    electronArch =
      {
        x86_64-linux = "x64";
        aarch64-linux = "arm64";
        x86_64-darwin = "x64";
        aarch64-darwin = "arm64";
      }
      .${system} or (throw "Unsupported system ${system}");
    electronFile = "electron-v${electronVersion}-${electronPlatform}-${electronArch}.zip";
    # nixpkgs' Electron (a source build on Linux), which is already patched for
    # NixOS. This is not the 42.8.1 VSCodium pins; the version skew is accepted
    # for now (switch to electron_42 to stay on the 42 line).
    electronDist = electron.dist;
    electronZip = runCommand electronFile {
      nativeBuildInputs = [ zip ];
    } ''
      # The nix store is read-only: directories are 0555 and files 0444. If we
      # zipped it as-is, the archive would record those modes, and
      # gulp-electron's extraction (vinyl-fs) cannot write files into a 0555
      # directory -- it deadlocks instead of reporting an error, stalling the
      # package-linux-x64 task. Stage a writable copy so the zip carries the
      # normal 0755/0644 modes of an official Electron archive.
      mkdir dist
      cp -r ${electronDist}/. dist/
      chmod -R u+w dist
      cd dist
      zip -r -q $out .
    '';
  in
{
  pname = "vscodium";
  version = "1.135.06055";

  src = fetchFromGitHub {
    owner = "VSCodium";
    repo = "vscodium";
    rev = finalAttrs.version;
    hash = "sha256-5WRs2Uz2e9bjls9xgldNiWmv4Ttn89SU3OiTC9Heh7U=";
  };

  vscodeSrc = fetchFromGitHub {
    owner = "Microsoft";
    repo = "vscode";
    rev = (lib.importJSON "${finalAttrs.src}/upstream/stable.json").commit;
    hash = "sha256-HLI+6nAvFaQgc1wjzvqcRvblJUbK9Yh3Z50WNNX5990=";
  };

  ## fetchNpmDeps doesn't correctly process git dependencies
  ## presumably because of https://github.com/npm/cli/issues/5170
  ## therefore, we're fetching all the node_module folders into
  ## a single FOD, and unpack it in configurePhase
  npmCache =
    runCommand "vscodium-npm-cache"
      {
        src = finalAttrs.vscodeSrc;
        vscodiumSrc = finalAttrs.src;
        inherit (finalAttrs) nativeBuildInputs;
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-aouTYZ8ImITZ4Z954NzgaYID5wQlhlG9MQ7CxiSM5x8=";
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
        mkdir -p $HOME
        mkdir $out

        # First, prefetch the plain upstream lockfiles.
        for p in $(find -name package-lock.json)
        do (
          echo "Prefetching $p"
          ${fetch-npm-deps-reentrant.prefetch-npm-deps}/bin/prefetch-npm-deps "$p" "$out"
        )
        done

        # vscodium's prepare_vscode.sh rewrites several package-lock.json files
        # at build time (e.g. 20-keymap-use-custom-lib.patch swaps native-keymap
        # for @vscodium/native-keymap and bumps prebuild-install to a version
        # that is not present in the upstream lockfiles). Prefetch those patched
        # lockfiles too, otherwise the offline `npm ci` in prepare_vscode.sh
        # fails with ENOTCACHED. prefetch-npm-deps is reentrant: tarballs that
        # were already cached by the first pass are skipped.
        cp -R ${finalAttrs.src}/patches ./vscodium-patches
        cp -rp ${finalAttrs.src}/src/stable/. .
        cp -f ${finalAttrs.src}/LICENSE LICENSE.txt
        chmod -R u+w .

        export APP_NAME=VSCodium
        export APP_NAME_LC=vscodium
        export ASSETS_REPOSITORY=VSCodium/vscodium
        export BINARY_NAME=codium
        export GH_REPO_PATH=VSCodium/vscodium
        export ORG_NAME=VSCodium
        export GLOBAL_DIRNAME=vscodium
        export TUNNEL_APP_NAME=codium-tunnel
        export RELEASE_VERSION=${finalAttrs.version}
        export VSCODE_QUALITY=stable
        export OS_NAME=${if stdenv.hostPlatform.isDarwin then "osx" else "linux"}

        source ${finalAttrs.src}/utils.sh

        for f in ./vscodium-patches/*.json
        do
          [ -f "$f" ] && apply_actions "$f"
        done
        for f in ./vscodium-patches/*.patch
        do
          [ -f "$f" ] && apply_patch "$f"
        done
        if [ -d "./vscodium-patches/$OS_NAME" ]
        then
          for f in "./vscodium-patches/$OS_NAME"/*.patch
          do
            [ -f "$f" ] && apply_patch "$f"
          done
        fi
        for f in ./vscodium-patches/user/*.patch
        do
          [ -f "$f" ] && apply_patch "$f"
        done

        for p in $(find -name package-lock.json)
        do (
          echo "Prefetching patched $p"
          ${fetch-npm-deps-reentrant.prefetch-npm-deps}/bin/prefetch-npm-deps "$p" "$out"
        )
        done
        rm -f "$out/package-lock.json"
      '';

  ## Electron headers, exposed via passthru for downstream native module builds
  ## (the same convention nixpkgs' electron packages follow). Layout is
  ## `include/node`, i.e. headers for Electron's bundled Node. The build itself
  ## does not use them: native modules are compiled against the nodejs headers
  ## through node-gyp's --nodedir (see env below).
  electronHeaders = electron.headers;

  env = {
    # NODE_OPTIONS = "--openssl-legacy-provider";
    # NODE_ENV = "development";

    # skip unnecessary binary downloads
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

    # ensure the correct node-gyp (from nixpkgs) is used
    NIX_NODEJS_BUILDNPMPACKAGE = "1";
    npm_config_node_gyp = "${nodejs}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js";
    # Compile native modules against the nodejs headers instead of letting
    # node-gyp download Electron/Node headers. All the addons here are
    # node-addon-api (N-API), so node headers are valid for the Electron app as
    # well. This is node-gyp's preferred spelling since npm 11: unlike
    # `npm_config_nodedir` it is not an "unknown config" to npm (see
    # nodejs/node-gyp#3156), and node-gyp gives it precedence.
    npm_package_config_node_gyp_nodedir = nodejs;
    # The npmCache FOD pre-seeds the full offline cache. Keep the build
    # strictly offline so missing packages fail loudly instead of silently
    # reaching out to the network.
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
    # The Electron runtime is not embedded any more (see installPhase): the
    # launcher runs the nixpkgs `electron` package instead, so depend on it.
    # This also removes the need for the former `dontPatchELF`, which existed
    # only because patchELF's --shrink-rpath mangled the embedded Electron's
    # rpath.
    [ electron ]
    ++ lib.optionals (!stdenv.hostPlatform.isDarwin) [ libsecret ]
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

    # build/gulpfile.reh.ts derives the server node version from
    # remote/.npmrc's `target=` and downloads a matching node.js into
    # .build/node/v<version>/<platform>-<arch>/ if it is missing (the
    # vscode-reh-web-...-ci tasks depend on it). Pin the target to the nodejs we
    # build with and pre-seed that directory so the offline build skips the
    # download.
    sed -i 's|^target=.*|target="${nodejs.version}"|' $sourceRoot/vscode/remote/.npmrc
    mkdir -p $sourceRoot/vscode/.build/node/v${nodejs.version}/${nodeBuildTarget}
    ln -sf ${nodejs}/bin/node $sourceRoot/vscode/.build/node/v${nodejs.version}/${nodeBuildTarget}/node

    # VSCodium's shell scripts use `#!/usr/bin/env ...` shebangs, which do not
    # resolve in the Nix sandbox (there is no /usr/bin/env). Several are executed
    # directly during the build (e.g. undo_telemetry.sh, invoked by
    # prepare_vscode.sh), so rewrite the resolvable ones to their store paths.
    # node_modules is not populated yet; the configurePhase loop patches those.
    patchShebangs $sourceRoot
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
    # Native modules are compiled against the nodejs headers via node-gyp's
    # --nodedir (npm_package_config_node_gyp_nodedir in `env`), so node-gyp
    # never enters its "download headers into the dev dir" path and no dev-dir
    # pre-seeding is needed.

    # Vendor the GitHub-only built-in extensions (ms-vscode.js-debug and
    # friends) and add their `vsix` paths to product.json. fromVsix is checked
    # before the marketplace/GitHub branches in build/lib/builtInExtensions.ts,
    # and it verifies each file against product.json's sha256. The paths are
    # relative to the vscode root (where the gulp task runs).
    mkdir -p vscode/.build/vsix
    cp ${builtInExtensionVsix."ms-vscode.js-debug"} vscode/.build/vsix/ms-vscode.js-debug.vsix
    cp ${builtInExtensionVsix."ms-vscode.js-debug-companion"} vscode/.build/vsix/ms-vscode.js-debug-companion.vsix
    cp ${builtInExtensionVsix."ms-vscode.vscode-js-profile-table"} vscode/.build/vsix/ms-vscode.vscode-js-profile-table.vsix
    jq --argjson vsix '{"ms-vscode.js-debug":".build/vsix/ms-vscode.js-debug.vsix","ms-vscode.js-debug-companion":".build/vsix/ms-vscode.js-debug-companion.vsix","ms-vscode.vscode-js-profile-table":".build/vsix/ms-vscode.vscode-js-profile-table.vsix"}' \
      '.builtInExtensions |= map(if $vsix[.name] then .vsix = $vsix[.name] else . end)' \
      vscode/product.json > vscode/product.json.tmp
    mv vscode/product.json.tmp vscode/product.json

    # build/npm/preinstall.ts runs `npm ci` inside build/npm/gyp and then
    # `node-gyp install` to download electron/node headers. We have already
    # installed build/npm/gyp's node-gyp (see the configurePhase loop) and we
    # point node-gyp at the nodejs headers via --nodedir, so disable that step
    # to keep the offline build from re-running npm ci (which wipes the
    # .bin/node-gyp symlink) and attempting a network download.
    substituteInPlace vscode/build/npm/preinstall.ts \
      --replace-fail 'installHeaders();' '/* installHeaders() skipped: headers pre-seeded offline */'

    # prepare_vscode.sh runs `npm ci` (with install scripts enabled) in the vscode
    # root after copying a minimal .npmrc over vscode/.npmrc. That invocation
    # would run every install script, which is neither needed nor desirable for
    # the offline build, so skip them (matching the configurePhase pass). We
    # must rebuild the native addons right here though: this `npm ci` re-creates
    # the root node_modules, and packages that only ship a binding.gyp (e.g.
    # @vscode/spdlog) get no implicit node-gyp build when scripts are ignored,
    # so spdlog.node was missing. The listed packages are the ones
    # build/.moduleignore expects under build/Release; they are all
    # node-addon-api (N-API), so the nodejs headers used via --nodedir are fine
    # here.
    substituteInPlace prepare_vscode.sh \
      --replace-fail 'CXX=clang++ npm ci && break' 'CXX=clang++ npm ci --ignore-scripts && break' \
      --replace-fail 'npm ci && break' 'npm ci --ignore-scripts && break' \
      --replace-fail 'mv .npmrc.bak .npmrc' 'mv .npmrc.bak .npmrc && npm rebuild --build-from-source @vscode/spdlog @vscode/deviceid @vscode/fs-copyfile @vscode/sqlite3 @vscode/native-watchdog @vscodium/native-keymap @vscodium/policy-watcher kerberos'

    # Serve the repackaged nixpkgs Electron zip to @electron/get through
    # ELECTRON_MIRROR. @vscode/gulp-electron asks @electron/get for
    # electron-v<version>-<platform>-<arch>.zip and the matching SHASUMS256.txt;
    # the latter is validated, so provide both. The default mirror layout is
    # <mirror>/v<version>/<file>. @electron/get@5 downloads with Node's global
    # fetch, which rejects file:// URLs, so install a small --require shim that
    # teaches fetch to read them from disk. (ELECTRON_SKIP_BINARY_DOWNLOAD only
    # covers the npm `electron` package, not this gulp/@electron/get path.)
    electronMirror=$TMPDIR/electron-mirror
    electronSha256=$(sha256sum ${electronZip} | cut -d' ' -f1)
    mkdir -p "$electronMirror/v${electronVersion}"
    ln -s ${electronZip} "$electronMirror/v${electronVersion}/${electronFile}"
    printf '%s *%s\n' "$electronSha256" "${electronFile}" > "$electronMirror/v${electronVersion}/SHASUMS256.txt"
    # gulp-electron additionally validates the extracted artifact against
    # vscode/build/checksums/electron.txt (which holds the upstream asset's
    # hash). Replace that entry with the hash of our repackaged Electron.
    sed -i -E "s|^[0-9a-f]{64} \*${electronFile}$|$electronSha256 *${electronFile}|" \
      vscode/build/checksums/electron.txt
    cat > $TMPDIR/electron-fetch-file.cjs <<'VSCODIUM_EOF'
    const fs = require('fs');
    const { fileURLToPath } = require('url');
    const realFetch = globalThis.fetch;
    globalThis.fetch = function (input, init) {
      var url = typeof input === 'string' ? input : (input && input.url) || String(input);
      if (!url.startsWith('file://')) {
        return realFetch(input, init);
      }
      var p = fileURLToPath(url);
      if (!fs.existsSync(p)) {
        return Promise.resolve(new Response(null, { status: 404, statusText: 'Not Found' }));
      }
      var stat = fs.statSync(p);
      var body = require('stream').Readable.toWeb(fs.createReadStream(p));
      return Promise.resolve(new Response(body, {
        status: 200,
        statusText: 'OK',
        headers: { 'content-length': String(stat.size) },
      }));
    };
    VSCODIUM_EOF
    export ELECTRON_MIRROR="file://$electronMirror/"
    export ELECTRON_GET_NO_PROGRESS=1
    export NODE_OPTIONS="--require $TMPDIR/electron-fetch-file.cjs''${NODE_OPTIONS:+ $NODE_OPTIONS}"
    # build.sh assigns NODE_OPTIONS unconditionally, which would drop the
    # --require shim above. Make it append to the inherited value instead.
    chmod u+w build.sh
    substituteInPlace build.sh \
      --replace-fail 'export NODE_OPTIONS="--max-old-space-size=''${MAX_OLD_SPACE_SIZE}"' \
                     'export NODE_OPTIONS="--max-old-space-size=''${MAX_OLD_SPACE_SIZE} $NODE_OPTIONS"'

    # The desktop app does not embed Electron (see the electronZip handling
    # above and installPhase): it is started with the nixpkgs electron package,
    # so the app directory is not next to the Electron binary. The CLI starts
    # the GUI by re-execing process.execPath, which would make Electron load
    # its own default app instead; pass the app directory explicitly. Electron
    # keeps `--app=` in process.argv, hence the matching strip in argvHelper.
    substituteInPlace vscode/src/vs/code/node/cli.ts \
      --replace-fail 'child = spawn(process.execPath, spawnArgs, options);' \
                     "spawnArgs.unshift('--app=' + getAppRoot()); child = spawn(process.execPath, spawnArgs, options);"
    substituteInPlace vscode/src/vs/platform/environment/node/argvHelper.ts \
      --replace-fail 'let [, ...args] = processArgv;' \
                     "let [, ...args] = processArgv; args = args.filter(arg => !arg.startsWith('--app='));"
  '';

  configurePhase = ''
    runHook preConfigure
  ''
  ## unpack all of the prefetched node_modules folders
  + ''
    ( cd vscode
      # `build/rspack` is only used by the component-explorer / css-order dev
      # tooling and is not needed to build or package the editor. Its lockfile
      # records most of its tree as unresolved peer dependencies (no
      # `resolved`/`integrity`), so `npm ci` has to query the registry for them,
      # which the offline npm cache cannot satisfy (ENOTCACHED). Upstream
      # installs it separately for the fixture workflows, so skip it here.
      for p in $(find -name package-lock.json -not -path '*/extensions/copilot/*' -not -path '*/build/rspack/*' -not -path './build/package-lock.json' -exec dirname {} \;)
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
      done

      # `build/` has its own .npmrc (legacy-peer-deps) and lockfile, and the
      # VSCodium patch set makes it depend on @vscodium/vsce:
      # patches/00-vsce-use-custom-lib.patch rewrites build/lib/extensions.ts's
      # require('@vscode/vsce') to '@vscodium/vsce' and adds it to
      # build/package.json + build/package-lock.json. The generic loop above
      # runs before that patch is applied, so it would install @vscode/vsce and
      # the later gulp task would fail to find @vscodium/vsce. Apply just those
      # two file hunks, install from the patched lockfile, then restore the
      # files so prepare_vscode.sh can apply the full patch itself.
      (
        cp build/package.json build/package.json.vscodium-bak
        cp build/package-lock.json build/package-lock.json.vscodium-bak
        git apply --ignore-whitespace \
          --include='build/package.json' \
          --include='build/package-lock.json' \
          ../patches/00-vsce-use-custom-lib.patch
        ( cd build && npm ci --ignore-scripts --cache $TMPDIR/cache )
        if [ -e build/node_modules ]
        then
          patchShebangs build/node_modules
        fi
        mv -f build/package.json.vscodium-bak build/package.json
        mv -f build/package-lock.json.vscodium-bak build/package-lock.json
      )
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
  ## Rebuild the remote tree's native modules from source, the same way
  ## openvscode-server does. The `npm ci` above used --ignore-scripts, so
  ## binding.gyp-only packages (e.g. @vscode/spdlog) have no .node yet. The
  ## remote tree targets node (remote/.npmrc). The desktop tree is rebuilt in
  ## prepare_vscode.sh instead, because its node_modules is re-created there.
  + ''
    echo >&2 "Rebuilding native modules in vscode/remote"
    npm --prefix vscode/remote rebuild --build-from-source
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
    # build_cli.sh builds the Rust tunnel CLI (bin/codium-tunnel).
    # It is not guarded by anything except SHOULD_BUILD_CLI (which only
    # VSCodium's CI sets), and it reaches the network twice: it runs a bare
    # `npm pack @vscode/openssl-prebuilt@0.0.11` (not in any lockfile, so the
    # npmCache FOD has no copy) and then builds with rustup/cargo against
    # crates.io. Neither is available offline, and the desktop app does not
    # need it to launch: bin/codium is resources/linux/bin/code.sh driving
    # out/cli.js. Skip it; wire the Rust CLI up separately if tunnels are
    # wanted.
    export SHOULD_BUILD_CLI="no"
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

    # Desktop build (VSCode-linux-${vsBuildArch}). gulp-electron merges the
    # compiled sources with an Electron distribution; ship only the app payload
    # and drop that runtime, because the app is started with the nixpkgs
    # electron package (see bin/codium below). This keeps Electron's
    # rpath/patchelf handling inside the electron package.
    mkdir -p "$out/share/vscodium"
    cp -R -T "VSCode-linux-${vsBuildArch}/resources" "$out/share/vscodium/resources"

    mkdir -p "$out/bin"
    cat > "$out/bin/codium" <<'VSCODIUM_EOF'
    #!/bin/sh
    export ELECTRON_RUN_AS_NODE=1
    exec ${electron}/bin/electron "$out/share/vscodium/resources/app/out/cli.js" "$@"
    VSCODIUM_EOF
    chmod +x "$out/bin/codium"
    patchShebangs "$out/bin"

    # Web server build (vscode-reh-web-linux-${vsBuildArch}).
    mkdir -p "$web"
    cp -R -T "vscode-reh-web-linux-${vsBuildArch}" "$web"
    ln -sf "${nodejs}/bin/node" "$web/node"

    runHook postInstall
  '';

  passthru.npmCache = finalAttrs.npmCache;
  passthru.electronHeaders = finalAttrs.electronHeaders;
  passthru.electronZip = electronZip;
  passthru.electron = electron;
  passthru.builtInExtensionVsix = builtInExtensionVsix;

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
    mainProgram = "codium";
  };
})
