#!/usr/bin/env nix-shell
#! nix-shell -i bash -p jq -p curl

one-line() {
    printf %s "$(cat)"
}

TAG=$(curl -L https://api.github.com/repos/Eloston/ungoogled-chromium/tags | jq '.[0]')
echo "$TAG" | jq -r '.name' | one-line > ungoogled-version

echo 0000000000000000000000000000000000000000000000000000000000000000 | one-line > ungoogled-sha256

nix-prefetch-url ./ungoogled.nix -A '' | one-line > ungoogled-sha256
