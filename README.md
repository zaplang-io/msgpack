# msgpack

MessagePack binary serialization for [Zap](https://github.com/zaplang-io/zap) — an official **non-core** package, a pure-Zap codec.

- Tracking issue: [zaplang-io/zap#317](https://github.com/zaplang-io/zap/issues/317)
- Roadmap: [bootstrap epic #1](https://github.com/zaplang-io/msgpack/issues/1)
- Contributor & agent conventions: [AGENTS.md](AGENTS.md)
- Design decisions: [DECISIONS.md](DECISIONS.md)

> **Status: base-type encoding.** `packb` encodes the MessagePack base types. The decoder, streaming APIs, and extension support are tracked in the epic.

## Goals

A pure-Zap MessagePack codec whose public API mirrors [**msgpack-python**](https://msgpack-python.readthedocs.io/) (`packb` / `unpackb`, the streaming `Packer` / `Unpacker`, `ExtType`, `Timestamp`, `default` / `ext_hook`, and the option set) as closely as Zap's static typing allows. API-parity with the popular Python library is a project rule — see [AGENTS.md](AGENTS.md). Output is byte-for-byte conformant with the [MessagePack spec](https://github.com/msgpack/msgpack/blob/master/spec.md).

## Encoding

```zap
import msgpack

def main():
    auto value = msgpack.Value.Map([(msgpack.Value.Str("id"), msgpack.Value.Int(1))])
    auto data = msgpack.packb(value)
    auto single = msgpack.packb(msgpack.Value.Float(1.5), use_single_float=True)
```

`packb` chooses the shortest integer and collection or payload length headers. `Str` encodes UTF-8 and `Bin` keeps the original bytes. Maps retain the order and duplicates in their pair lists. Float payloads default to binary64, and `use_single_float=True` selects binary32 throughout the document. NaNs encode as a canonical quiet NaN. The encoder raises `ValueError` for extension variants, lengths outside the wire limit, and nesting beyond 1,024 levels.

## Scope

- Core `packb`/`unpackb` for all MessagePack base types (#2/#3).
- Streaming `Packer`/`Unpacker` with incremental `feed` (#4).
- Extension types (`ExtType`) + `default`/`ext_hook` (#5), and the Timestamp extension (ext -1) (#6).
- Decode limits + malformed-input hardening — untrusted input is a first-class concern (#7).
- Option parity: `use_bin_type`, `raw`, `strict_map_key`, … (#8).
- The approved `Value` model represents maps as ordered key/value pairs and preserves duplicate keys. By default, decoding accepts string and binary keys. [Value-model decision](DECISIONS.md#dynamic-document-value-model-issue-10)

## Build and test

GitHub Actions runs **MessagePack CI** on every pull request and on pushes to `main`, using a pinned Zap runtime. The check must pass before merging. `tools/run-tests.sh` executes the Zap fixtures in `tests/` and compares their output with the adjacent `.expected` files. The encoder fixtures check exact wire bytes for integer, float, and length boundaries and check rejection of unsupported values and excessive nesting.

Codec changes should include wire-format golden vectors and round-trips for valid data, plus rejection cases for malformed and truncated input. See [AGENTS.md](AGENTS.md) for the full coverage expectations.

## Development

Read **[AGENTS.md](AGENTS.md)** before contributing — it covers the msgpack-python-parity rule, the one-issue-one-PR + **CI-per-PR** flow, how design decisions are recorded in **[DECISIONS.md](DECISIONS.md)**, and the rule for reporting core Zap defects upstream in `zaplang-io/zap`.
