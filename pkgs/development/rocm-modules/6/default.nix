{
  stdenv,
  lib,
  newScope,
  recurseIntoAttrs,
  symlinkJoin,
  fetchFromGitHub,
  boost179,
  opencv,
  ffmpeg_4,
  libjpeg_turbo,
  python3Packages,
  libffi,
  emptyDirectory,
  cudaPackages,
  triton-llvm,
  openmpi,
}:

lib.makeScope newScope (
  self:
  let
    pyPackages = python3Packages;
    libffiorig = libffi;
    openmpi-orig = openmpi;
  in
  with self;
  {
    buildTests = false;
    buildBenchmarks = false;

    libffi =
      (libffiorig.override {
        stdenv = self.llvm.rocmClangStdenv;
      }).overrideAttrs
        (old: {
          dontStrip = true;
          env.CFLAGS = "-g1 -gz";
          env.CXXFLAGS = "-g1 -gz";
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            "-DCMAKE_BUILD_TYPE=Release"
          ];
        });

    rocmPath = callPackage ./rocm-path { };
    rocmUpdateScript = callPackage ./update.nix { };

    ## ROCm ##
    llvm = recurseIntoAttrs (callPackage ./llvm/default.nix { inherit rocm-device-libs rocm-runtime; });
    inherit (self.llvm) rocm-merged-llvm clang;

    rocm-core = callPackage ./rocm-core {
      stdenv = llvm.rocmClangStdenv;
    };
    amdsmi = pyPackages.callPackage ./amdsmi {
      inherit rocmUpdateScript;
      stdenv = llvm.rocmClangStdenv;
    };

    rocm-cmake = callPackage ./rocm-cmake {

      stdenv = llvm.rocmClangStdenv;
    };

    rocm-smi = pyPackages.callPackage ./rocm-smi {
      inherit rocmUpdateScript;
      stdenv = llvm.rocmClangStdenv;
    };

    rocm-device-libs = callPackage ./rocm-device-libs {
      inherit (llvm) rocm-merged-llvm;
      stdenv = llvm.rocmClangStdenv;
    };

    rocm-runtime = callPackage ./rocm-runtime {
      inherit rocmUpdateScript rocm-device-libs;
      inherit (llvm) rocm-merged-llvm;
      stdenv = llvm.rocmClangStdenv;
    };

    # Eventually will be in the LLVM repo
    rocm-comgr = callPackage ./rocm-comgr {
      inherit rocm-device-libs;
      inherit (llvm) rocm-merged-llvm;
      stdenv = llvm.rocmClangStdenv;
    };

    rocminfo = callPackage ./rocminfo {
      inherit rocmUpdateScript rocm-cmake rocm-runtime;
      stdenv = llvm.rocmClangStdenv;
    };

    # Unfree
    hsa-amd-aqlprofile-bin = callPackage ./hsa-amd-aqlprofile-bin {
      stdenv = llvm.rocmClangStdenv;
    };

    rdc = callPackage ./rdc {
      inherit rocmUpdateScript rocm-smi rocm-runtime;
      stdenv = llvm.rocmClangStdenv;
    };

    rocm-docs-core = python3Packages.callPackage ./rocm-docs-core { };

    hip-common = callPackage ./hip-common {

      stdenv = llvm.rocmClangStdenv;
    };

    # Eventually will be in the LLVM repo
    hipcc = callPackage ./hipcc {

      inherit (llvm) rocm-merged-llvm;
      stdenv = llvm.rocmClangStdenv;
    };

    # Replaces hip, opencl-runtime, and rocclr
    clr = callPackage ./clr {
      inherit
        rocmUpdateScript
        hip-common
        rocm-device-libs
        rocm-comgr
        rocm-runtime
        roctracer
        rocminfo
        rocm-smi
        hipcc
        ;
      stdenv = llvm.rocmClangStdenv;
    };

    aotriton = callPackage ./aotriton {
      inherit (llvm) clang-sysrooted openmp;
      stdenv = llvm.rocmClangStdenv;
    };

    hipify = callPackage ./hipify {
      inherit (llvm)
        clang
        rocm-merged-llvm
        ;
      stdenv = llvm.rocmClangStdenv;
    };

    # hsakmt = throw "hsakmt is part of rocm-runtime";

    rocprofiler = callPackage ./rocprofiler {
      stdenv = llvm.rocmClangStdenv;
      inherit
        rocmUpdateScript
        clr
        rocm-core
        rocm-device-libs
        roctracer
        rocdbgapi
        ;
      inherit (llvm) clang;
    };
    rocprofiler-register = callPackage ./rocprofiler-register {
      stdenv = llvm.rocmClangStdenv;
      inherit rocmUpdateScript;
      inherit (llvm) clang;
    };

    # Needs GCC
    roctracer = callPackage ./roctracer {
      inherit
        rocmUpdateScript
        rocm-device-libs
        rocm-runtime
        clr
        ;
      stdenv = llvm.rocmClangStdenv;
    };

    rocgdb = callPackage ./rocgdb {
      inherit rocmUpdateScript rocdbgapi;
      stdenv = llvm.rocmClangStdenv;
    };

    rocdbgapi = callPackage ./rocdbgapi {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocm-comgr
        rocm-runtime
        ;
      stdenv = llvm.rocmClangStdenv;
    };

    rocr-debug-agent = callPackage ./rocr-debug-agent {
      inherit rocmUpdateScript clr rocdbgapi;
      stdenv = llvm.rocmClangStdenv;
    };

    rocprim = callPackage ./rocprim {
      inherit rocmUpdateScript rocm-cmake clr;
      stdenv = llvm.rocmClangStdenv;
    };

    rocsparse = callPackage ./rocsparse {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocprim
        clr
        ;
      stdenv = llvm.rocmClangStdenv;
    };

    rocthrust = callPackage ./rocthrust {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocprim
        clr
        ;
      stdenv = llvm.rocmClangStdenv;
    };

    rocrand = callPackage ./rocrand {
      inherit rocmUpdateScript rocm-cmake clr;
      stdenv = llvm.rocmClangStdenv;
    };

    hiprand = callPackage ./hiprand {
      inherit
        rocmUpdateScript
        rocm-cmake
        clr
        rocrand
        ;
      stdenv = llvm.rocmClangStdenv;
    };

    rocfft = callPackage ./rocfft {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocrand
        clr
        ;
      inherit (llvm) openmp;
      stdenv = llvm.rocmClangStdenv;
    };

    mscclpp = callPackage ./mscclpp {
      stdenv = llvm.rocmClangStdenv;
    };

    rccl = callPackage ./rccl {
      inherit rocmUpdateScript;
      stdenv = llvm.rocmClangStdenv;
    };

    # RCCL with sanitizers and tests
    # Can't have with sanitizer build as dep of other packages without
    # runtime crashes due to ASAN not loading first
    rccl-tests = callPackage ./rccl {
      inherit rocmUpdateScript;
      stdenv = llvm.rocmClangStdenv;
      buildTests = true;
    };

    hipcub = callPackage ./hipcub {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocprim
        clr
        ;
      stdenv = llvm.rocmClangStdenv;
    };

    hipsparse = callPackage ./hipsparse {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocsparse
        clr
        ;
      inherit (llvm) openmp;
      stdenv = llvm.rocmClangStdenv;
    };

    hipfort = callPackage ./hipfort {
      inherit rocmUpdateScript rocm-cmake;
      stdenv = llvm.rocmClangStdenv;
    };

    hipfft = callPackage ./hipfft {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocfft
        clr
        ;
      inherit (llvm) openmp;
      stdenv = llvm.rocmClangStdenv;
    };

    tensile = pyPackages.callPackage ./tensile {
      inherit rocmUpdateScript rocminfo;
      stdenv = llvm.rocmClangStdenv;
    };

    rocblas = callPackage ./rocblas {
      inherit
        rocmUpdateScript
        rocm-cmake
        clr
        tensile
        ;
      inherit (llvm) openmp clang-sysrooted;
      stdenv = llvm.rocmClangStdenv;
      buildTests = true;
      buildBenchmarks = true;
    };

    rocsolver = callPackage ./rocsolver {
      inherit rocmUpdateScript;
      stdenv = llvm.rocmClangStdenv;
    };

    rocwmma = callPackage ./rocwmma {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocm-smi
        rocblas
        clr
        ;
      inherit (llvm) openmp;
      stdenv = llvm.rocmClangStdenv;
    };

    rocalution = callPackage ./rocalution {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocprim
        rocsparse
        rocrand
        rocblas
        clr
        ;
      inherit (llvm) openmp;
      stdenv = llvm.rocmClangStdenv;
    };

    rocmlir = callPackage ./rocmlir {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocminfo
        clr
        ;
      stdenv = llvm.rocmClangStdenv;
      buildRockCompiler = true;
    };

    rocmlir-rock = rocmlir;
    # rocmlir-rock = rocmlir.override {
    #   buildRockCompiler = true;
    # };

    hipsolver = callPackage ./hipsolver {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocblas
        rocsolver
        clr
        ;
      stdenv = llvm.rocmClangStdenv;
    };

    hipblas-common = callPackage ./hipblas-common {
      inherit rocm-cmake;
      stdenv = llvm.rocmClangStdenv;
    };

    hipblas = callPackage ./hipblas {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocblas
        rocsolver
        clr
        ;
      stdenv = llvm.rocmClangStdenv;
    };

    hipblaslt = callPackage ./hipblaslt {
      inherit rocmUpdateScript;
      inherit (llvm) openmp clang-sysrooted;
      stdenv = llvm.rocmClangStdenv;
    };

    # hipTensor - Only supports GFX9

    composable_kernel_build = callPackage ./composable_kernel {
      inherit rocmUpdateScript rocm-cmake clr;
      inherit (llvm) rocm-merged-llvm;
      stdenv = llvm.rocmClangStdenv;
    };

    # FIXME: we have compressed code objects now, may be able to skip two stages?
    composable_kernel = callPackage ./composable_kernel/unpack.nix { };
    ck4inductor = pyPackages.callPackage ./composable_kernel/ck4inductor.nix {
      inherit (llvm) rocm-merged-llvm;
      inherit composable_kernel_build;
    };

    half = callPackage ./half {
      inherit rocmUpdateScript rocm-cmake;
      stdenv = llvm.rocmClangStdenv;
    };

    miopen = callPackage ./miopen {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocblas
        composable_kernel
        rocm-comgr
        clr
        rocm-docs-core
        half
        roctracer
        ;
      inherit (llvm) rocm-merged-llvm;
      stdenv = llvm.rocmClangStdenv;
      rocmlir = rocmlir-rock;
      boost = boost179.override { enableStatic = true; };
    };

    miopen-hip = miopen;

    # miopen-opencl= throw ''
    #   'miopen-opencl' has been deprecated.
    #   It is still available for some time as part of rocmPackages_5.
    # ''; # Added 2024-3-3

    migraphx = callPackage ./migraphx {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocblas
        composable_kernel
        miopen
        clr
        half
        rocm-device-libs
        ;
      inherit (llvm) openmp;
      stdenv = llvm.rocmClangStdenv;
      rocmlir = rocmlir-rock;
    };

    rpp = callPackage ./rpp {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocm-docs-core
        clr
        half
        ;
      inherit (llvm) openmp;
      stdenv = llvm.rocmClangStdenv;
    };

    rpp-hip = rpp.override {
      useOpenCL = false;
      useCPU = false;
    };

    rpp-opencl = rpp.override {
      useOpenCL = true;
      useCPU = false;
    };

    rpp-cpu = rpp.override {
      useOpenCL = false;
      useCPU = true;
    };

    mivisionx = callPackage ./mivisionx {
      inherit
        rocmUpdateScript
        rocm-cmake
        rocm-device-libs
        clr
        rpp
        rocblas
        miopen
        migraphx
        half
        rocm-docs-core
        ;
      inherit (llvm) clang openmp;
      opencv = opencv.override { enablePython = true; };
      ffmpeg = ffmpeg_4;
      stdenv = llvm.rocmClangStdenv;

      # Unfortunately, rocAL needs a custom libjpeg-turbo until further notice
      # See: https://github.com/ROCm/MIVisionX/issues/1051
      libjpeg_turbo = libjpeg_turbo.overrideAttrs {
        version = "2.0.6.1";

        src = fetchFromGitHub {
          owner = "rrawther";
          repo = "libjpeg-turbo";
          rev = "640d7ee1917fcd3b6a5271aa6cf4576bccc7c5fb";
          sha256 = "sha256-T52whJ7nZi8jerJaZtYInC2YDN0QM+9tUDqiNr6IsNY=";
        };

        # overwrite all patches, since patches for newer version do not apply
        patches = [ ./0001-Compile-transupp.c-as-part-of-the-library.patch ];
      };
    };

    mivisionx-hip = mivisionx.override {
      rpp = rpp-hip;
      useOpenCL = false;
      useCPU = false;
    };

    # mivisionx-opencl = throw ''
    #   'mivisionx-opencl' has been deprecated.
    #   Other versions of mivisionx are still available.
    #   It is also still available for some time as part of rocmPackages_5.
    # ''; # Added 2024-3-24

    mivisionx-cpu = mivisionx.override {
      rpp = rpp-cpu;
      useOpenCL = false;
      useCPU = true;
    };

    openmpi = openmpi-orig.override (prev: {
      ucx = prev.ucx.override {
        enableCuda = false;
        enableRocm = true;
      };
    });
    mpi = self.openmpi;

    triton-llvm =
      builtins.trace "FIXME: triton-rocm needs ANOTHER different LLVM build"
        (triton-llvm.override {
          buildTests = false; # FIXME: why are tests failing?
        }).overrideAttrs
        {
          src = fetchFromGitHub {
            owner = "llvm";
            repo = "llvm-project";
            # make sure this matches triton llvm rel branch hash for now
            # https://github.com/triton-lang/triton/blob/release/3.2.x/cmake/llvm-hash.txt
            rev = "86b69c31642e98f8357df62c09d118ad1da4e16a";
            hash = "sha256-W/mQwaLGx6/rIBjdzUTIbWrvGjdh7m4s15f70fQ1/hE=";
          };
          pname = "triton-llvm-rocm";
          patches = [ ]; # FIXME: https://github.com/llvm/llvm-project//commit/84837e3cc1cf17ed71580e3ea38299ed2bfaa5f6.patch doesn't apply, may need to rebase
        };

    triton =
      (pyPackages.triton-no-cuda.override (_old: {
        rocmPackages = self;
        rocmSupport = true;
        # buildPythonPackage = x: old.buildPythonPackage (x // { stdenv = llvmPackagesRocm.rocmClangStdenv;});
        stdenv = self.llvm.rocmClangStdenv;
        llvm = self.triton-llvm;
      })).overridePythonAttrs
        (old: {
          doCheck = false;
          stdenv = self.llvm.rocmClangStdenv;
          version = "3.2.0";
          src = fetchFromGitHub {
            owner = "triton-lang";
            repo = "triton";
            rev = "64b80f0916b69e3c4d0682a2368fd126e57891ab"; # "release/3.2.x";
            hash = "sha256-xQOgMLHruVrI/9FtY3TvZKALitMOfqZ69uOyrYhXhu8=";
          };
          buildInputs = old.buildInputs ++ [
            self.clr
          ];
          dontStrip = true;
          env = old.env // {
            CXXFLAGS = "-gz -g1 -O3 -I${self.clr}/include -I/build/source/third_party/triton/third_party/nvidia/backend/include";
            TRITON_OFFLINE_BUILD = 1;
          };
          patches = [ ];
          postPatch = ''
            # Need an empty cuda.h to happily compile for ROCm
            mkdir -p third_party/nvidia/include/ third_party/nvidia/include/backend/include/
            echo "" > third_party/nvidia/include/cuda.h
            touch third_party/nvidia/include/backend/include/{cuda,driver_types}.h
            rm -rf third_party/nvidia
            substituteInPlace CMakeLists.txt \
              --replace-fail "add_subdirectory(test)" ""
            sed -i '/nvidia\|NVGPU\|registerConvertTritonGPUToLLVMPass\|mlir::test::/Id' bin/RegisterTritonDialects.h
            sed -i '/TritonTestAnalysis/Id' bin/CMakeLists.txt
            substituteInPlace python/setup.py \
              --replace-fail 'backends = [*BackendInstaller.copy(["nvidia", "amd"]), *BackendInstaller.copy_externals()]' \
              'backends = [*BackendInstaller.copy(["amd"]), *BackendInstaller.copy_externals()]'
            #cp ''${cudaPackages.cuda_cudart}/include/*.h third_party/nvidia/backend/include/
            find . -type f -exec sed -i 's|[<]cupti.h[>]|"cupti.h"|g' {} +
            find . -type f -exec sed -i 's|[<]cuda.h[>]|"cuda.h"|g' {} +

            # remove any downloads
            substituteInPlace python/setup.py \
              --replace-fail "[get_json_package_info()]" "[]"\
              --replace-fail "[get_llvm_package_info()]" "[]"\
              --replace-fail "curr_version != version" "False"

            # Don't fetch googletest
            substituteInPlace cmake/AddTritonUnitTest.cmake \
              --replace-fail 'include(''${PROJECT_SOURCE_DIR}/unittest/googletest.cmake)' "" \
              --replace-fail "include(GoogleTest)" "find_package(GTest REQUIRED)"

            substituteInPlace third_party/amd/backend/compiler.py \
              --replace-fail '"/opt/rocm/llvm/bin/ld.lld"' "os.environ['ROCM_PATH']"' + "/llvm/bin/ld.lld"'
          '';
        });

    ## Meta ##
    # Emulate common ROCm meta layout
    # These are mainly for users. I strongly suggest NOT using these in nixpkgs derivations
    # Don't put these into `propagatedBuildInputs` unless you want PATH/PYTHONPATH issues!
    # See: https://rocm.docs.amd.com/en/docs-5.7.1/_images/image.004.png
    # See: https://rocm.docs.amd.com/en/docs-5.7.1/deploy/linux/os-native/package_manager_integration.html
    meta = rec {
      rocm-developer-tools = symlinkJoin {
        name = "rocm-developer-tools-meta";

        paths = [
          hsa-amd-aqlprofile-bin
          rocm-core
          rocr-debug-agent
          roctracer
          rocdbgapi
          rocprofiler
          rocgdb
          rocm-language-runtime
        ];
      };

      rocm-ml-sdk = symlinkJoin {
        name = "rocm-ml-sdk-meta";

        paths = [
          rocm-core
          miopen-hip
          rocm-hip-sdk
          rocm-ml-libraries
        ];
      };

      rocm-ml-libraries = symlinkJoin {
        name = "rocm-ml-libraries-meta";

        paths = [
          llvm.clang
          llvm.mlir
          llvm.openmp
          rocm-core
          miopen-hip
          rocm-hip-libraries
        ];
      };

      rocm-hip-sdk = symlinkJoin {
        name = "rocm-hip-sdk-meta";

        paths = [
          rocprim
          rocalution
          hipfft
          rocm-core
          hipcub
          hipblas
          hipblaslt
          rocrand
          rocfft
          rocsparse
          rccl
          rocthrust
          rocblas
          hipsparse
          hipfort
          rocwmma
          hipsolver
          rocsolver
          rocm-hip-libraries
          rocm-hip-runtime-devel
        ];
      };

      rocm-hip-libraries = symlinkJoin {
        name = "rocm-hip-libraries-meta";

        paths = [
          rocblas
          hipfort
          rocm-core
          rocsolver
          rocalution
          rocrand
          hipblas
          hipblaslt
          rocfft
          hipfft
          rccl
          rocsparse
          hipsparse
          hipsolver
          rocm-hip-runtime
        ];
      };

      rocm-openmp-sdk = symlinkJoin {
        name = "rocm-openmp-sdk-meta";

        paths = [
          rocm-core
          llvm.clang
          llvm.mlir
          llvm.openmp # openmp-extras-devel (https://github.com/ROCm/aomp)
          rocm-language-runtime
        ];
      };

      rocm-opencl-sdk = symlinkJoin {
        name = "rocm-opencl-sdk-meta";

        paths = [
          rocm-core
          rocm-runtime
          clr
          clr.icd
          rocm-opencl-runtime
        ];
      };

      rocm-opencl-runtime = symlinkJoin {
        name = "rocm-opencl-runtime-meta";

        paths = [
          rocm-core
          clr
          clr.icd
          rocm-language-runtime
        ];
      };

      rocm-hip-runtime-devel = symlinkJoin {
        name = "rocm-hip-runtime-devel-meta";

        paths = [
          clr
          rocm-core
          hipify
          rocm-cmake
          llvm.clang
          llvm.mlir
          llvm.openmp
          rocm-runtime
          rocm-hip-runtime
        ];
      };

      rocm-hip-runtime = symlinkJoin {
        name = "rocm-hip-runtime-meta";

        paths = [
          rocm-core
          rocminfo
          clr
          rocm-language-runtime
        ];
      };

      rocm-language-runtime = symlinkJoin {
        name = "rocm-language-runtime-meta";

        paths = [
          rocm-runtime
          rocm-core
          rocm-comgr
          llvm.openmp # openmp-extras-runtime (https://github.com/ROCm/aomp)
        ];
      };

      rocm-all = symlinkJoin {
        name = "rocm-all-meta";

        paths = [
          rocm-developer-tools
          rocm-ml-sdk
          rocm-ml-libraries
          rocm-hip-sdk
          rocm-hip-libraries
          rocm-openmp-sdk
          rocm-opencl-sdk
          rocm-opencl-runtime
          rocm-hip-runtime-devel
          rocm-hip-runtime
          rocm-language-runtime
        ];
      };
    };
  }
)
