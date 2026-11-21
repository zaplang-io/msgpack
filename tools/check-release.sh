#!/bin/sh
# Check candidate metadata and, when supplied, an existing release tag.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n 's/^version = "\([^"]*\)"$/\1/p' "$root/zap.toml")
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo 'Expected a stable X.Y.Z version in zap.toml' >&2
    exit 1
fi
test -s "$root/LICENSE"
test -s "$root/src/msgpack.zap"
test -s "$root/docs/SUPPORT.md"
test -s "$root/docs/RELEASING.md"
grep -Fq "## $version (" "$root/CHANGELOG.md"
for source in "$root"/examples/*.zap; do
    test -s "$source"
    test -s "${source%.zap}.expected"
done
for golden in "$root"/examples/*.expected; do
    test -s "${golden%.expected}.zap"
done

if [ "$#" -gt 1 ]; then
    echo 'Usage: tools/check-release.sh [vX.Y.Z]' >&2
    exit 2
fi
if [ "$#" -eq 1 ]; then
    tag=$1
    if [ "$tag" != "v$version" ]; then
        echo "Tag must match the manifest version v$version" >&2
        exit 1
    fi
    tagged=$(git -C "$root" rev-parse --verify "refs/tags/$tag^{commit}")
    head=$(git -C "$root" rev-parse HEAD)
    if [ "$tagged" != "$head" ]; then
        echo 'Release tag must identify the checked-out commit' >&2
        exit 1
    fi
fi
printf 'Release preflight %s: PASS\n' "$version"
