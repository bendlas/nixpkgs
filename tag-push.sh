#!/bin/sh

set -eux

git fetch origin main
git push origin FETCH_HEAD:refs/heads/main-$(date -I)
