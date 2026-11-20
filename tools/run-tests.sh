#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
trap 'exit 1' HUP INT TERM

# Zap resolves sibling imports beside the entry point.
if [ -d "$root/src" ]; then
    cp "$root"/src/*.zap "$build/"
fi

for source in "$root"/tests/*_test.zap; do
    name=$(basename "$source" .zap)
    cp "$source" "$build/$name.zap"
    timeout -k 5s 60s zap run "$build/$name.zap" > "$build/actual"
    diff -u "$root/tests/$name.expected" "$build/actual"
    cat "$build/actual"
done

# Require the expected compiler diagnostic so a missing tool or timeout cannot
# satisfy the negative fixture.
status=0
timeout -k 5s 60s zap ir "$root/tests/compile_fail/unknown_name.zap" > "$build/diagnostic" 2>&1 || status=$?
if [ "$status" -ne 1 ] || ! grep -Fq 'error[ZAP3001]: unknown name' "$build/diagnostic"; then
    cat "$build/diagnostic" >&2
    echo "Expected unknown_name.zap to fail with ZAP3001; exit status was $status" >&2
    exit 1
fi
echo 'Zap compile-fail smoke test: PASS'
