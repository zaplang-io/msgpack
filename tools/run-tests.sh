#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
trap 'exit 1' HUP INT TERM

# Stage the package and each suite together, as in the memcached runner.
for source in "$root"/tests/*_test.zap; do
    name=$(basename "$source")
    {
        cat "$root/src/msgpack.zap"
        printf '\n'
        cat "$source"
    } > "$build/$name"
done

timeout -k 5s 180s zap test "$build"
timeout -k 5s 30s zap test --doc "$root/tests/compile_fail/unknown_name.zap"
