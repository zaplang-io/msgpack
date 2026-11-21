#!/bin/sh
# Run each example as the entry point of an external application.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
trap 'exit 1' HUP INT TERM

export ZAP_CACHE="$build/cache"
unset ZAP_ZENV
(cd "$root" && zap publish --dry-run)
consumer="$build/consumer"
mkdir -p "$consumer/src"
cat > "$consumer/zap.toml" <<'MANIFEST'
[package]
name = "msgpack_examples"
version = "0.0.0"
MANIFEST

cd "$consumer"
zap add msgpack --path "$root"
zap zenv create --no-venv
export ZAP_ZENV="$consumer/zenv"
test -s zap.lock
test -f "$ZAP_ZENV/pkg/msgpack/src/msgpack.zap"

for source in "$root"/examples/*.zap; do
    name=$(basename "$source" .zap)
    cp "$source" src/main.zap
    timeout -k 5s 60s zap run > "$build/actual"
    diff -u "$root/examples/$name.expected" "$build/actual"
    printf 'Installed example %s: PASS\n' "$name"
done
