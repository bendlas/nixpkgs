{
  lib,
  buildGoModule,
  fetchFromGitHub,
  fetchpatch2,
  installShellFiles,
}:

let
  config-module = "github.com/f1bonacc1/process-compose/src/config";
in
buildGoModule rec {
  pname = "process-compose";
  version = "1.64.1";

  src = fetchFromGitHub {
    owner = "F1bonacc1";
    repo = "process-compose";
    rev = "v${version}";
    hash = "sha256-qv/fVfuQD7Nan5Nn1RkwXoGZuPYSRWQaojEn6MCF9BQ=";
    # populate values that require us to use git. By doing this in postFetch we
    # can delete .git afterwards and maintain better reproducibility of the src.
    leaveDotGit = true;
    postFetch = ''
      cd "$out"
      git rev-parse --short HEAD > $out/COMMIT
      # in format of 0000-00-00T00:00:00Z
      date -u -d "@$(git log -1 --pretty=%ct)" "+%Y-%m-%dT%H:%M:%SZ" > $out/SOURCE_DATE_EPOCH
      find "$out" -name .git -print0 | xargs -0 rm -rf
    '';
  };

  patches = [
    # Fix a linker issue with dlopen on x86_64-darwin
    # https://github.com/f1bonacc1/process-compose/pull/342
    (fetchpatch2 {
      url = "https://github.com/F1bonacc1/process-compose/commit/af82749c5dacaa20f2c3b07ca4e081d1b38e40c4.patch";
      hash = "sha256-5Hgvwn2GEp/lINPefxXdJUGb2TJfufqAPm+/3gdi6XY=";
    })
  ];

  # ldflags based on metadata from git and source
  preBuild = ''
    ldflags+=" -X ${config-module}.Commit=$(cat COMMIT)"
    ldflags+=" -X ${config-module}.Date=$(cat SOURCE_DATE_EPOCH)"
  '';

  ldflags = [
    "-X ${config-module}.Version=v${version}"
    "-s"
    "-w"
  ];

  nativeBuildInputs = [
    installShellFiles
  ];

  vendorHash = "sha256-qkfJo+QGqcqiZMLuWbj0CpgRWxbqTu6DGAW8pBu4O/0=";

  doCheck = false;

  postInstall = ''
    mv $out/bin/{src,process-compose}

    installShellCompletion --cmd process-compose \
      --bash <($out/bin/process-compose completion bash) \
      --zsh <($out/bin/process-compose completion zsh) \
      --fish <($out/bin/process-compose completion fish)
  '';

  meta = {
    description = "Simple and flexible scheduler and orchestrator to manage non-containerized applications";
    homepage = "https://github.com/F1bonacc1/process-compose";
    changelog = "https://github.com/F1bonacc1/process-compose/releases/tag/v${version}";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ thenonameguy ];
    mainProgram = "process-compose";
  };
}
