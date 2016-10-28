{ writeScript, writeText, zlib, gcc
, wrappedCC ? gcc }:
let
  testC = writeText "cc-wrapper-test.cpp" ''
    #include <iostream>
    #include <stdlib.h>
    #include <zlib.h>
    int main(int ac, char **av) {
      std::cout << "Linked to zlib version " << zlibVersion() << std::endl;
      exit(0);
    }
  '';
  compileFlags = writeText "cflags.rsp" ''
    -I${zlib.dev}/include
    -xc++
  '';
  linkFlags = writeText "ldflags.rsp" ''
    -L${zlib}/lib
    -lz
    -lstdc++
  '';
in writeScript "cc-wrapper-tests" ''
    #!/bin/sh
    info () {
      echo "$@" >&2
    }
    trace () {
      info "$@"
    }
    EXIT=0
    check () {
      trace "Checking '$2'"
      eval "$1" && ./a.out && trace "OK" || EXIT=1
    }
    cc="${wrappedCC}/bin/gcc"
    testC="${testC}"
    compileFlags="${compileFlags}";
    linkFlags="${linkFlags}";

    pushd $(mktemp -d)
    info "Starting cc-wrapper response file tests ..."

    mapfile -t unpackedFlags <<< $(cat $compileFlags $linkFlags)
    uf="${"$"}{unpackedFlags[@]}"
    check "$cc $uf $testC" "CompileLinkNorsp"
    check "$cc @$compileFlags @$linkFlags $testC" "CompileLink"
    check "$cc -c -o tc.o @$compileFlags $testC && $cc @$linkFlags tc.o" "Compile -> CompileLink"

    TWD=`pwd`
    trace " ... removing $TWD..."
    popd
    rm -r $TWD
    if ( exit $EXIT ); then
      info " ... finished successfully"
    else
      info " ... finished with errors"
    fi  
    exit $EXIT
''
