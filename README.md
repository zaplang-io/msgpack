# msgpack

MessagePack binary serialization for [Zap](https://github.com/zaplang-io/zap) — an official **non-core** package, a pure-Zap codec.

- Tracking issue: [zaplang-io/zap#317](https://github.com/zaplang-io/zap/issues/317)
- Roadmap: [bootstrap epic #1](https://github.com/zaplang-io/msgpack/issues/1)
- Contributor & agent conventions: [AGENTS.md](AGENTS.md)
- Design decisions: [DECISIONS.md](DECISIONS.md)

> **Status: early / scaffolding.** The codec is being built out issue-by-issue (see the epic). The APIs sketched below describe the *target* surface and are not all implemented yet.

## Goals

A pure-Zap MessagePack codec whose public API mirrors [**msgpack-python**](https://msgpack-python.readthedocs.io/) (`packb` / `unpackb`, the streaming `Packer` / `Unpacker`, `ExtType`, `Timestamp`, `default` / `ext_hook`, and the option set) as closely as Zap's static typing allows. API-parity with the popular Python library is a project rule — see [AGENTS.md](AGENTS.md). Output is byte-for-byte conformant with the [MessagePack spec](https://github.com/msgpack/msgpack/blob/master/spec.md).

## Usage (target surface)

```zap
# Sketch — see the epic for what is implemented today.
data = msgpack.packb({"id": 1, "tags": [b"a", b"b"]})   # bytes
obj  = msgpack.unpackb(data)                              # dynamic value

# Streaming:
unpacker = msgpack.Unpacker()
unpacker.feed(chunk)
for item in unpacker:
    handle(item)
```

## Scope

- Core `packb`/`unpackb` for all MessagePack base types (#2/#3).
- Streaming `Packer`/`Unpacker` with incremental `feed` (#4).
- Extension types (`ExtType`) + `default`/`ext_hook` (#5), and the Timestamp extension (ext -1) (#6).
- Decode limits + malformed-input hardening — untrusted input is a first-class concern (#7).
- Option parity: `use_bin_type`, `raw`, `strict_map_key`, … (#8).
- The dynamic document value model is an open design decision (#10 — see DECISIONS.md).

## Build and test

Standard Zap package build/test. **Every PR is validated by CI** (see AGENTS.md) — tests are exhaustive and include malformed/truncated input. Prefer round-trip and spec-vector tests.

## Development

Read **[AGENTS.md](AGENTS.md)** before contributing — it covers the msgpack-python-parity rule, the one-issue-one-PR + **CI-per-PR** flow, how design decisions are recorded in **[DECISIONS.md](DECISIONS.md)**, and the rule for reporting core Zap defects upstream in `zaplang-io/zap`.
