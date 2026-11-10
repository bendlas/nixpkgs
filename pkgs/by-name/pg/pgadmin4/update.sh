#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl wget jq nix yarn-berry_4 yarn-berry_4.yarn-berry-fetcher nix-prefetch-git git

# Updates version, src hash, yarnHash and missing-hashes.json of pgadmin4.
#
# Usage: ./update.sh [version]
# Without an argument the newest version is taken from pgadmin.org.

set -eu -o pipefail

TMPDIR=/tmp/pgadmin-update-script

cleanup() {
  if [[ -e "$TMPDIR/.done" ]]; then
    rm -rf "$TMPDIR"
  elif [[ -t 0 ]]; then
    echo
    read -p "Script exited prematurely. Do you want to delete the temporary directory $TMPDIR ? " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      rm -rf "$TMPDIR"
    fi
  else
    echo "Script exited prematurely, keeping $TMPDIR for inspection"
  fi
}

trap cleanup EXIT

scriptDir=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
mkdir -p "$TMPDIR"

newest_version="${1:-$(curl -s https://www.pgadmin.org/versions.json | jq -r .pgadmin4.version)}"
old_version=$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$scriptDir/package.nix")

if [[ $newest_version == "$old_version" ]]; then
  printf "Already at latest version %s\n" "$newest_version"
  touch "$TMPDIR/.done"
  exit 0
fi
printf "Updating pgadmin4: %s -> %s\n" "$old_version" "$newest_version"

# The derivation fetches the GitHub tag REL-<major>_<minor>
rev="REL-${newest_version%.*}_${newest_version#*.}"
url="https://github.com/pgadmin-org/pgadmin4/archive/refs/tags/${rev}.tar.gz"
archive="$TMPDIR/pgadmin4-${newest_version}.tar.gz"
src_dir="$TMPDIR/pgadmin4-$rev/web"

printf "Downloading %s\n" "$url"
# don't use mktemp, so if a network error happens, we can resume from there
wget -c -O "$archive" "$url"
if [[ ! -d "$src_dir" ]]; then
  tar -xzf "$archive" -C "$TMPDIR"
fi

printf "Computing src hash\n"
src_hash=$(nix-prefetch-url --unpack "file://$archive")
src_hash=$(nix hash convert --hash-algo sha256 --to sri "$src_hash")

pushd "$src_dir"

printf "Generating missing-hashes.json\n"
yarn-berry-fetcher missing-hashes yarn.lock >missing-hashes.json
if [[ $(jq 'length' missing-hashes.json) -gt 0 ]]; then
  printf "Prefetching yarn dependencies (this downloads to the nix store and takes some time)\n"
  yarn_hash=$(yarn-berry-fetcher prefetch yarn.lock missing-hashes.json | grep -m1 '^sha256-')
else
  printf "Prefetching yarn dependencies (this downloads to the nix store and takes some time)\n"
  yarn_hash=$(yarn-berry-fetcher prefetch yarn.lock | grep -m1 '^sha256-')
fi
printf "Done\n"

if [[ -z "$src_hash" || -z "$yarn_hash" ]]; then
  printf "ERROR: could not determine src hash or yarnHash\n" >&2
  exit 1
fi

if [[ ! -e "$scriptDir/missing-hashes.json" ]]; then
  printf "PLEASE NOTE: FIRST TIME OF FINDING MISSING HASHES!\n"
  printf "Please add \"missingHashes = ./missing-hashes.json\" to pgadmin derivation\n"
fi
cp missing-hashes.json "$scriptDir/missing-hashes.json"
popd

printf "Updating %s\n" "$scriptDir/package.nix"
sed -i -E \
  -e "s|^(  version = )\"[^\"]*\";|\1\"$newest_version\";|" \
  -e "s|^(  yarnHash = )\"[^\"]*\";|\1\"$yarn_hash\";|" \
  -e "s|^(    hash = )\"[^\"]*\";|\1\"$src_hash\";|" \
  "$scriptDir/package.nix"

touch "$TMPDIR/.done"
printf "Done\n"
