{ stdenv, lib, fetchFromGitHub, fuse,
  withChromium ? false,
  chromeExtensionId ? "" }:

let
  commonManifest = {
    name = "com.rsnous.tabfs";
    description = "TabFS";
    path = "@out@/bin/tabfs";
    type = "stdio";
    allowed_extensions = ["tabfs@rsnous.com"];
  };
in
stdenv.mkDerivation rec {
  pname = "tabfs";
  version = "5f6cad2c71889ba2fd11c0249852f6e0e1c220d4";

  src = fetchFromGitHub {
    owner = "osnr";
    repo = "TabFS";
    rev = version;
    sha256 = "13wfi8wm9ibnrh8gf5iimkfr5vmhsgsqw1qkpdbajvcs1rimqg0l";
  };

  preBuild = ''
    makeFlagsArray+=('CFLAGS+=-I${fuse}/include -L${fuse}/lib $(CFLAGS_EXTRA)')
    cd fs/
  '';

  passAsFile = [
    "firefoxManifest"
    "chromiumManifest"
    "chromiumExtensionPatch"
  ];

  chromiumExtensionPatch = ''
diff --git a/extension/manifest.json b/extension/manifest.json
index 022cf27..3f4e715 100644
--- a/extension/manifest.json
+++ b/extension/manifest.json
@@ -14,11 +14,5 @@
   "background": {
     "scripts": ["vendor/browser-polyfill.js", "background.js"],
     "persistent": true
-  },
-
-  "browser_specific_settings": {
-    "gecko": {
-      "id": "tabfs@rsnous.com"
-    }
   }
 }
'';

  firefoxManifest = builtins.toJSON commonManifest;
  chromiumManifest = lib.optionalString withChromium
    (builtins.toJSON (commonManifest // {
      allowed_origins = [ "chrome-extension://${chromeExtensionId}/" ];
    }));

  postBuild = ''
    cd ..
    substituteAll $firefoxManifestPath firefox.json
    ${lib.optionalString withChromium "substituteAll $chromiumManifestPath chromium.json"}
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib/mozilla/native-messaging-hosts $out/share/tabfs/extension-firefox
    install -Dm0755 fs/tabfs $out/bin
    install -Dm0644 firefox.json $out/lib/mozilla/native-messaging-hosts/com.rsnous.tabfs.json
    cp -r extension/* $out/share/tabfs/extension-firefox
  '' + lib.optionalString withChromium ''
    install -Dm644 chromium.json $out/etc/chromium/native-messaging-hosts/com.rsnous.tabfs.json
    patch -p1 < "$chromiumExtensionPatchPath"
    mkdir -p $out/share/tabfs/extension-chromium
    cp -r extension/* $out/share/tabfs/extension-chromium
  '';

  meta = with stdenv.lib; {
    description = "Mount your browser tabs as a filesystem.";
    license = licenses.gpl3;
    platforms = stdenv.lib.platforms.linux;
    homepage = "https://omar.website/tabfs/";
  };
}
