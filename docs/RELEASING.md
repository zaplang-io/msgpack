# Preparing the 0.1.0 release

The candidate uses version `0.1.0` in `zap.toml`. Required CI validates it on
pull requests and pushes to `main`, using the toolchain in the support matrix.
[Support matrix](SUPPORT.md)

## Install a reviewed checkout into an application

```sh
git clone https://github.com/zaplang-io/msgpack.git
git -C msgpack rev-parse HEAD
zap new msgpack_demo
cd msgpack_demo
zap add msgpack --path ../msgpack
zap zenv create --no-venv
. zenv/activate
cp ../msgpack/examples/roundtrip.zap src/main.zap
zap run
```

Review the source commit before adding the path dependency. Zap resolves
`import msgpack` from `zenv/pkg/msgpack/src/msgpack.zap`. Keep the application
manifest and `zap.lock` with the application. Recreate `zenv` after changing
the dependency checkout intentionally.

## Required CI checks

- `tools/run-tests.sh` runs the codec fixtures, malformed-input corpus, and
  compiler rejection fixture.
- `tools/check-release.sh` checks the package version, changelog, support
  matrix, release checklist, and the pairing of examples with golden output.
- `tools/run-package-tests.sh` validates packaging with `zap publish --dry-run`,
  materializes a path dependency in a fresh external application, and runs
  every example through its `src/main.zap` entry point. It compares stdout with
  each checked-in `.expected` file.

## Release checklist

1. Confirm the bootstrap issues linked from the epic are closed and required
   CI passed on all merged PRs. [Bootstrap epic](https://github.com/zaplang-io/msgpack/issues/1)
2. Verify that the manifest version matches the changelog and that the support
   matrix describes the behavior verified by CI.
3. Confirm the required checks passed on the reviewed `main` commit selected
   for release.
4. After maintainer approval, create `v0.1.0` on that commit. From a checkout
   of the tag, `tools/check-release.sh v0.1.0` verifies that it matches both the
   manifest and the commit.
5. Use the separately approved publication channel to release the reviewed
   package and changelog.
