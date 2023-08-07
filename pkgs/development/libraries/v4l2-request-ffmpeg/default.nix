{ runCommandNoCC, git, cacert
, ffmpeg_5-full
# , fetchFromGitHub
, lib
, udev
}:

(ffmpeg_5-full.override {
  withSdl2 = true;
}).overrideAttrs (old: rec {
  pname = "v4l2-request-ffmpeg";
  version = "5.1.2";

  # src = fetchFromGitHub {
  #   owner = "jernejsk";
  #   repo = "FFmpeg";
  #   rev = "v4l2-request-hwaccel-${version}";
  #   sha256 = "sha256-fT+UBfiZUJtH/HHfCub1jWoaRNhLWg3gCnmDwfEY76k=";
  # };

  src = runCommandNoCC "ffmpeg-src" {
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-32GNXYwgRD/hdhc7qCsvBsjO5VU7QLzbtBmo1372S90=";
    url = "https://github.com/jernejsk/FFmpeg";
    inherit version;
    nativeBuildInputs = [ git ];
    GIT_SSL_CAINFO = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  } ''
    git clone "$url" repo
    cd repo
    git checkout -b work origin/v4l2-request-n$version
    git -c "user.name=Your Name" -c "user.email=you@example.com" \
      merge --no-edit origin/v4l2-drmprime-n$version
    git -c "user.name=Your Name" -c "user.email=you@example.com" \
      merge --no-edit origin/vf-deinterlace-v4l2m2m-n$version
    rm -rf .git
    cp -r . $out
  '';

  buildInputs = old.buildInputs ++ [ udev ];

  configureFlags = old.configureFlags ++ [
    "--extra-version=v4l2-request"
    "--enable-v4l2-request"
    "--enable-neon"
    "--enable-libudev"
    # "--enable-rkmpp"
  ];

  meta = with lib; {
    description = "${old.meta.description} (jernejsk fork)";
    homepage = "https://github.com/jernejsk/FFmpeg";
    license = licenses.gpl3;
    maintainers = with maintainers; [ bendlas ];
  };
})
