{
  lib,
  stdenv,
  python,
  buildPythonPackage,
  pythonAtLeast,
  fetchFromGitHub,
  symlinkJoin,
  autoAddDriverRunpath,
  fetchpatch2,

  # build system
  cmake,
  jinja2,
  ninja,
  packaging,
  setuptools,
  setuptools-scm,

  # dependencies
  which,
  torch,
  outlines,
  psutil,
  ray,
  pandas,
  pyarrow,
  sentencepiece,
  numpy,
  transformers,
  xformers,
  xgrammar,
  numba,
  fastapi,
  uvicorn,
  pydantic,
  aioprometheus,
  pynvml,
  openai,
  pyzmq,
  tiktoken,
  torchaudio,
  torchvision,
  py-cpuinfo,
  lm-format-enforcer,
  prometheus-fastapi-instrumentator,
  cupy,
  cbor2,
  pybase64,
  gguf,
  einops,
  importlib-metadata,
  partial-json-parser,
  compressed-tensors,
  mistral-common,
  msgspec,
  numactl,
  tokenizers,
  oneDNN,
  blake3,
  depyf,
  opencv-python-headless,
  cachetools,
  llguidance,
  python-json-logger,
  python-multipart,
  llvmPackages,
  opentelemetry-sdk,
  opentelemetry-api,
  opentelemetry-exporter-otlp,
  bitsandbytes,
  flashinfer,
  py-libnuma,

  awscli,
  boto3,
  botocore,
  peft,
  pytest-asyncio,
  #tensorizer,

  # internal dependency - for overriding in overlays
  vllm-flash-attn ? null,

  cudaSupport ? torch.cudaSupport,
  cudaPackages ? { },
  rocmSupport ? torch.rocmSupport,
  rocmPackages ? { },
  gpuTargets ? [ ],
}:

let
  inherit (lib)
    lists
    strings
    trivial
    ;

  inherit (cudaPackages) flags;

  shouldUsePkg =
    pkg: if pkg != null && lib.meta.availableOn stdenv.hostPlatform pkg then pkg else null;

  rocmtoolkit_joined = symlinkJoin {
    name = "rocm-merged";

    paths = with rocmPackages; [
      rocm-core
      clr
      rccl
      miopen
      aotriton
      rocrand
      rocblas
      rocsparse
      hipsparse
      rocthrust
      rocprim
      hipcub
      roctracer
      rocfft
      rocsolver
      hipfft
      hiprand
      hipsolver
      hipblas-common
      hipblas
      hipblaslt
      rocminfo
      rocm-comgr
      rocm-device-libs
      rocm-runtime
      clr.icd
      hipify
    ];

    # Fix `setuptools` not being found
    postBuild = ''
      rm -rf $out/nix-support
    '';
  };

  # see CMakeLists.txt, grepping for GIT_TAG near cutlass
  # https://github.com/vllm-project/vllm/blob/v${version}/CMakeLists.txt
  cutlass = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "cutlass";
    tag = "v4.0.0";
    hash = "sha256-HJY+Go1viPkSVZPEs/NyMtYJzas4mMLiIZF3kNX+WgA=";
  };

  flashmla = stdenv.mkDerivation {
    pname = "flashmla";
    # https://github.com/vllm-project/FlashMLA/blob/${src.rev}/setup.py
    version = "1.0.0";

    # grep for GIT_TAG in the following file
    # https://github.com/vllm-project/vllm/blob/v${version}/cmake/external_projects/flashmla.cmake
    src = fetchFromGitHub {
      owner = "vllm-project";
      repo = "FlashMLA";
      rev = "575f7724b9762f265bbee5889df9c7d630801845";
      hash = "sha256-8WrKMl0olr0nYV4FRJfwSaJ0F5gWQpssoFMjr9tbHBk=";
    };

    dontConfigure = true;

    # flashmla normally relies on `git submodule update` to fetch cutlass
    buildPhase = ''
      rm -rf csrc/cutlass
      ln -sf ${cutlass} csrc/cutlass
    '';

    installPhase = ''
      cp -rva . $out
    '';
  };

  vllm-flash-attn' = lib.defaultTo (stdenv.mkDerivation {
    pname = "vllm-flash-attn";
    # https://github.com/vllm-project/flash-attention/blob/${src.rev}/vllm_flash_attn/__init__.py
    version = "2.7.4.post1";

    # grep for GIT_TAG in the following file
    # https://github.com/vllm-project/vllm/blob/v${version}/cmake/external_projects/vllm_flash_attn.cmake
    src = fetchFromGitHub {
      owner = "vllm-project";
      repo = "flash-attention";
      rev = "1c2624e53c078854e0637ee566c72fe2107e75f4";
      hash = "sha256-WWFhHEUSAlsXr2yR4rGlTQQnSafXKg8gO5PQA8HPYGE=";
    };

    dontConfigure = true;

    # vllm-flash-attn normally relies on `git submodule update` to fetch cutlass and composable_kernel
    buildPhase = ''
      rm -rf csrc/cutlass
      ln -sf ${cutlass} csrc/cutlass
    ''
    + lib.optionalString (rocmSupport) ''
      rm -rf csrc/composable_kernel;
      ln -sf ${rocmPackages.composable_kernel} csrc/composable_kernel
    '';

    installPhase = ''
      cp -rva . $out
    '';
  }) vllm-flash-attn;

  cpuSupport = !cudaSupport && !rocmSupport;

  # https://github.com/pytorch/pytorch/blob/v2.7.1/torch/utils/cpp_extension.py#L2343-L2345
  supportedTorchCudaCapabilities =
    let
      real = [
        "3.5"
        "3.7"
        "5.0"
        "5.2"
        "5.3"
        "6.0"
        "6.1"
        "6.2"
        "7.0"
        "7.2"
        "7.5"
        "8.0"
        "8.6"
        "8.7"
        "8.9"
        "9.0"
        "9.0a"
        "10.0"
        "10.0a"
        "10.1"
        "10.1a"
        "12.0"
        "12.0a"
      ];
      ptx = lists.map (x: "${x}+PTX") real;
    in
    real ++ ptx;

  # NOTE: The lists.subtractLists function is perhaps a bit unintuitive. It subtracts the elements
  #   of the first list *from* the second list. That means:
  #   lists.subtractLists a b = b - a

  # For CUDA
  supportedCudaCapabilities = lists.intersectLists flags.cudaCapabilities supportedTorchCudaCapabilities;
  unsupportedCudaCapabilities = lists.subtractLists supportedCudaCapabilities flags.cudaCapabilities;

  isCudaJetson = cudaSupport && cudaPackages.flags.isJetsonBuild;

  # Use trivial.warnIf to print a warning if any unsupported GPU targets are specified.
  gpuArchWarner =
    supported: unsupported:
    trivial.throwIf (supported == [ ]) (
      "No supported GPU targets specified. Requested GPU targets: "
      + strings.concatStringsSep ", " unsupported
    ) supported;

  # Create the gpuTargetString.
  gpuTargetString = strings.concatStringsSep ";" (
    if gpuTargets != [ ] then
      # If gpuTargets is specified, it always takes priority.
      gpuTargets
    else if cudaSupport then
      gpuArchWarner supportedCudaCapabilities unsupportedCudaCapabilities
    else if rocmSupport then
      rocmPackages.clr.gpuTargets
    else
      throw "No GPU targets specified"
  );

  mergedCudaLibraries = with cudaPackages; [
    cuda_cudart # cuda_runtime.h, -lcudart
    cuda_cccl
    libcusparse # cusparse.h
    libcusolver # cusolverDn.h
    cuda_nvtx
    cuda_nvrtc
    libcublas
  ];

  # Some packages are not available on all platforms
  nccl = shouldUsePkg (cudaPackages.nccl or null);

  getAllOutputs = p: [
    (lib.getBin p)
    (lib.getLib p)
    (lib.getDev p)
  ];

in

buildPythonPackage rec {
  pname = "vllm";
  version = "0.10.0";
  pyproject = true;

  # https://github.com/vllm-project/vllm/issues/12083
  disabled = pythonAtLeast "3.13";

  stdenv = torch.stdenv;

  src = fetchFromGitHub {
    owner = "vllm-project";
    repo = "vllm";
    tag = "v${version}";
    hash = "sha256-R9arpFz+wkDGmB3lW+H8d/37EoAQDyCWjLHJW1VTutk=";
  };

  patches = [
    # error: ‘BF16Vec16’ in namespace ‘vec_op’ does not name a type; did you mean ‘FP16Vec16’?
    # Reported: https://github.com/vllm-project/vllm/issues/21714
    # Fix from https://github.com/vllm-project/vllm/pull/21848
    (fetchpatch2 {
      name = "build-fix-for-arm-without-bf16";
      url = "https://github.com/vllm-project/vllm/commit/b876860c6214d03279e79e0babb7eb4e3e286cbd.patch";
      hash = "sha256-tdBAObFxliVUNTWeSggaLtS4K9f8zEVu22nSgRmMsDs=";
    })
    ./0002-setup.py-nix-support-respect-cmakeFlags.patch
    ./0003-propagate-pythonpath.patch
    ./0005-drop-intel-reqs.patch
  ];

  postPatch = ''
    # pythonRelaxDeps does not cover build-system
    substituteInPlace pyproject.toml \
      --replace-fail "torch ==" "torch >=" \
      --replace-fail "setuptools>=77.0.3,<80.0.0" "setuptools"

    # Pass build environment PYTHONPATH to vLLM's Python configuration scripts
    # Ignore the python version check because it hard-codes minor versions and
    # lags behind `ray`'s python interpreter support
    # Here I just took some random comment and added the line I want.
    # This really needs to be a patch.
    # I have _no_ idea how vllm builds on FHS systems. I don't see how torch
    # causes vllm to find HIP. Let's just tell cmake to find HIP.
    substituteInPlace CMakeLists.txt \
      --replace-fail '$PYTHONPATH' '$ENV{PYTHONPATH}' \
      --replace-fail \
        'set(PYTHON_SUPPORTED_VERSIONS' \
        'set(PYTHON_SUPPORTED_VERSIONS "${lib.versions.majorMinor python.version}"' \
      --replace-fail \
        '# Forward the non-CUDA device extensions to external CMake scripts.' \
        'find_package(HIP REQUIRED)'

    substituteInPlace csrc/quantization/compressed_tensors/int8_quant_kernels.cu \
      --replace-fail \
      'dst = std::clamp(dst, i8_min, i8_max);' \
      'dst = (dst < i8_min) ? i8_min : (dst > i8_max) ? i8_max : dst;' \
      --replace-fail \
      'int32_t dst = std::clamp(x, i8_min, i8_max);' \
      'int32_t dst = (x < i8_min) ? i8_min : (x > i8_max) ? i8_max : x;'


    substituteInPlace csrc/quantization/fused_kernels/quant_conversions.cuh \
      --replace-fail \
      'dst = std::clamp(dst, i8_min, i8_max);' \
      'dst = (dst < i8_min) ? i8_min : (dst > i8_max) ? i8_max : dst;'

    substituteInPlace setup.py \
      --replace-fail \
        'and torch.version.hip is not None' \
        ' ' \
      --replace-fail \
        'hipcc_version = get_hipcc_rocm_version()' \
        'hipcc_version = "0.0"'
  '';

  nativeBuildInputs = [
    which
  ]
  ++ lib.optionals rocmSupport [
    rocmtoolkit_joined
  ]
  ++ lib.optionals cudaSupport [
    cudaPackages.cuda_nvcc
    autoAddDriverRunpath
  ]
  ++ lib.optionals isCudaJetson [
    cudaPackages.autoAddCudaCompatRunpath
  ];

  build-system = [
    cmake
    jinja2
    ninja
    packaging
    setuptools
    setuptools-scm
    torch
  ];

  buildInputs =
    lib.optionals cpuSupport [
      oneDNN
    ]
    ++ lib.optionals (cpuSupport && stdenv.hostPlatform.isLinux) [
      numactl
    ]
    ++ lib.optionals cudaSupport (
      mergedCudaLibraries
      ++ (with cudaPackages; [
        nccl
        cudnn
        libcufile
      ])
    )
    ++ lib.optionals rocmSupport [ rocmtoolkit_joined ]
    ++ lib.optionals stdenv.cc.isClang [
      llvmPackages.openmp
    ];

  dependencies = [
    aioprometheus
    blake3
    cachetools
    cbor2
    depyf
    fastapi
    llguidance
    lm-format-enforcer
    numpy
    openai
    opencv-python-headless
    outlines
    pandas
    prometheus-fastapi-instrumentator
    psutil
    py-cpuinfo
    pyarrow
    pybase64
    pydantic
    python-json-logger
    python-multipart
    pyzmq
    ray
    sentencepiece
    tiktoken
    tokenizers
    msgspec
    gguf
    einops
    importlib-metadata
    partial-json-parser
    compressed-tensors
    mistral-common
    torch
    torchaudio
    torchvision
    transformers
    uvicorn
    xformers
    xgrammar
    numba
    opentelemetry-sdk
    opentelemetry-api
    opentelemetry-exporter-otlp
    bitsandbytes
    # vLLM needs Torch's compiler to be present in order to use torch.compile
    torch.stdenv.cc

    awscli
    boto3
    botocore
    peft
    pytest-asyncio
    #tensorizer
  ]
  ++ uvicorn.optional-dependencies.standard
  ++ aioprometheus.optional-dependencies.starlette
  ++ lib.optionals stdenv.targetPlatform.isLinux [
    py-libnuma
    psutil
  ]
  ++ lib.optionals cudaSupport [
    cupy
    pynvml
    flashinfer
  ];

  dontUseCmakeConfigure = true;
  cmakeFlags = [
  ]
  ++ lib.optionals rocmSupport [
    (lib.cmakeFeature "CMAKE_HIP_COMPILER" "${rocmPackages.clr.hipClangPath}/clang++")
    # TODO: this should become `clr.gpuTargets` in the future.
    #(lib.cmakeFeature "CMAKE_HIP_ARCHITECTURES" rocmPackages.rocblas.amdgpu_targets)
    (lib.cmakeFeature "CMAKE_HIP_ARCHITECTURES" "gfx1100")
    (lib.cmakeFeature "AMDGPU_TARGETS" "gfx1100")
  ]
  ++ lib.optionals cudaSupport [
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_CUTLASS" "${lib.getDev cutlass}")
    (lib.cmakeFeature "FLASH_MLA_SRC_DIR" "${lib.getDev flashmla}")
    (lib.cmakeFeature "VLLM_FLASH_ATTN_SRC_DIR" "${lib.getDev vllm-flash-attn'}")
    (lib.cmakeFeature "TORCH_CUDA_ARCH_LIST" "${gpuTargetString}")
    (lib.cmakeFeature "CUTLASS_NVCC_ARCHS_ENABLED" "${cudaPackages.flags.cmakeCudaArchitecturesString}")
    (lib.cmakeFeature "CUDA_TOOLKIT_ROOT_DIR" "${symlinkJoin {
      name = "cuda-merged-${cudaPackages.cudaMajorMinorVersion}";
      paths = builtins.concatMap getAllOutputs mergedCudaLibraries;
    }}")
    (lib.cmakeFeature "CAFFE2_USE_CUDNN" "ON")
    (lib.cmakeFeature "CAFFE2_USE_CUFILE" "ON")
    (lib.cmakeFeature "CUTLASS_ENABLE_CUBLAS" "ON")
  ]
  ++ lib.optionals cpuSupport [
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ONEDNN" "${lib.getDev oneDNN}")
  ];

  env =
    lib.optionalAttrs cudaSupport {
      VLLM_TARGET_DEVICE = "cuda";
      CUDA_HOME = "${lib.getDev cudaPackages.cuda_nvcc}";
    }
    // lib.optionalAttrs rocmSupport {
      VLLM_TARGET_DEVICE = "rocm";
      # Otherwise it tries to enumerate host supported ROCM gfx archs, and that is not possible due to sandboxing.
      #PYTORCH_ROCM_ARCH = lib.strings.concatStringsSep ";" rocmPackages.clr.gpuTargets;
      PYTORCH_ROCM_ARCH = "gfx1100";
      ROCM_PATH = "${rocmtoolkit_joined}";
      ROCM_HOME = "${rocmtoolkit_joined}";
    }
    // lib.optionalAttrs cpuSupport {
      VLLM_TARGET_DEVICE = "cpu";
    };

  preConfigure = ''
    # See: https://github.com/vllm-project/vllm/blob/v0.7.1/setup.py#L75-L109
    # There's also NVCC_THREADS but Nix/Nixpkgs doesn't really have this concept.
    export MAX_JOBS="$NIX_BUILD_CORES"
  '';

  pythonRelaxDeps = true;

  # The runtime check is checking for tensorizer, which isn't packages, AFAIK.
  dontCheckRuntimeDeps = true;
  pythonImportsCheck = [ "vllm" ];

  passthru = {
    # make internal dependency available to overlays
    vllm-flash-attn = vllm-flash-attn';
    # updates the cutlass fetcher instead
    skipBulkUpdate = true;
  };

  meta = {
    description = "High-throughput and memory-efficient inference and serving engine for LLMs";
    changelog = "https://github.com/vllm-project/vllm/releases/tag/v${version}";
    homepage = "https://github.com/vllm-project/vllm";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [
      happysalada
      lach
    ];
    badPlatforms = [
      # CMake Error at cmake/cpu_extension.cmake:78 (find_isa):
      # find_isa Function invoked with incorrect arguments for function named:
      # find_isa
      "x86_64-darwin"
    ];
    # ValueError: 'aimv2' is already used by a Transformers config, pick another name.
    # Version bump ongoing in https://github.com/NixOS/nixpkgs/pull/429117
    broken = true;
  };
}
