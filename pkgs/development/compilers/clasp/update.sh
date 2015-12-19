#!/bin/sh

TAG="0.4.0"
TMP_REPO="$(mktemp -d)"

(cd $TMP_REPO
 git init
 git fetch --depth=1 https://github.com/drmeister/clasp.git $TAG
 git checkout FETCH_HEAD
 git submodule status | awk)
