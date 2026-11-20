# msgpack

MessagePack binary serialization for [Zap](https://github.com/zaplang-io/zap) — an official **non-core** package, a pure-Zap codec.

- Tracking issue: [zaplang-io/zap#317](https://github.com/zaplang-io/zap/issues/317)
- Roadmap: [bootstrap epic #1](https://github.com/zaplang-io/msgpack/issues/1)
- Contributor & agent conventions: [AGENTS.md](AGENTS.md)
- Design decisions: [DECISIONS.md](DECISIONS.md)

> **Status: base types and application extensions.** `packb`, `unpackb`, `Packer`, and `Unpacker` support the base types and `ExtType`. Timestamp support is tracked in the epic.

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

`packb` chooses the shortest integer and collection or payload length headers. `Str` encodes UTF-8 and `Bin` keeps the original bytes. Maps retain the order and duplicates in their pair lists. Float payloads default to binary64, and `use_single_float=True` selects binary32 throughout the document. NaNs encode as a canonical quiet NaN. The encoder raises `ValueError` for invalid extension codes, timestamps, lengths outside the wire limit, and nesting beyond 1,024 levels.

## Decoding

`unpackb(data, raw=False, strict_map_key=True)` decodes one complete value. `raw=True` returns string payloads as bytes, including string keys. Disable `strict_map_key` to allow other value types as map keys. Maps preserve input order and repeated keys in both modes.

```zap
import msgpack

def main():
    try:
        auto value = msgpack.unpackb(bytes([0x81, 0xa2, 0x69, 0x64, 0x01]))
    except msgpack.OutOfData:
        print("Incomplete MessagePack value")
    except msgpack.ExtraData:
        print("Exactly one value is required")
```

- `OutOfData` signals incomplete input, including a declared length that cannot fit in the remaining bytes.
- `ExtraData` signals trailing bytes after a complete value.
- `FormatError` signals malformed UTF-8, an invalid strict map key, a reserved tag or extension code, or a timestamp.
- `StackError` signals a value nested beyond 1,024 levels.

## Application extensions

Wrap `msgpack.ExtType(code, data)` in `msgpack.Value.Ext` to encode an application-defined extension. The code is an integer from 0 through 127 and the payload is `bytes`. Encoding uses `fixext` for 1, 2, 4, 8, or 16 payload bytes and the smallest variable-length extension header otherwise. The decoder returns `Value.Ext` with the original code and bytes, including inside arrays and maps. `raw` applies to text fields and leaves extension payloads as bytes.

For a top-level custom object, `packb_with_default(value, default=encode)` calls your `encode` function to produce an `ExtType`. `unpackb_with_ext_hook(data, ext_hook=decode)` validates one complete application extension, then calls your `decode(code, payload)` function and returns its declared type.

## Streaming

Use `Packer().pack(value)` to encode each value for immediate writing to a stream. `Packer(use_single_float=True)` applies the same float setting to each call. Feed incoming chunks to `Unpacker` and iterate whenever more bytes arrive.

```zap
import msgpack

def main():
    auto packer = msgpack.Packer()
    auto packed = packer.pack(msgpack.Value.Str("hello"))
    auto reader = msgpack.Unpacker(max_buffer_size=4096)

    reader.feed(packed[0:2])
    reader.feed(packed[2:len(packed)])
    for value in reader:
        print(value)
```

`Unpacker.unpack()` gets one value and raises `OutOfData` when more bytes are needed. Iteration stops at that point and can resume after a later `feed`. A single feed can contain several values, and the unpacker keeps incomplete data between calls. `raw` and `strict_map_key` behave as in `unpackb`.

`max_buffer_size` defaults to 100 MiB of unread data. Set it to a positive byte limit for your stream or to zero for the MessagePack-scale limit of `2^32 - 1` bytes. A feed that would exceed the limit raises `BufferFull` before accepting any bytes. Successful reads release capacity.

## Scope

- Core `packb`/`unpackb` for all MessagePack base types (#2/#3).
- Streaming `Packer`/`Unpacker` with incremental `feed` (#4).
- Extension types (`ExtType`) + `default`/`ext_hook` (#5), and the Timestamp extension (ext -1) (#6).
- Decode limits + malformed-input hardening — untrusted input is a first-class concern (#7).
- Option parity: `use_bin_type`, `raw`, `strict_map_key`, … (#8).
- The approved `Value` model represents maps as ordered key/value pairs and preserves duplicate keys. By default, decoding accepts string and binary keys. [Value-model decision](DECISIONS.md#dynamic-document-value-model-issue-10)

## Build and test

GitHub Actions runs **MessagePack CI** on every pull request and on pushes to `main`, using `ghcr.io/zaplang-io/zap:latest`. The check must pass before merging. `tools/run-tests.sh` executes the Zap fixtures in `tests/` and compares their output with the adjacent `.expected` files. The codec fixtures check exact wire bytes, round-trips, typed errors, and incremental reads across split and coalesced chunks.

Codec changes should include wire-format golden vectors and round-trips for valid data, plus rejection cases for malformed and truncated input. See [AGENTS.md](AGENTS.md) for the full coverage expectations.

## Development

Read **[AGENTS.md](AGENTS.md)** before contributing — it covers the msgpack-python-parity rule, the one-issue-one-PR + **CI-per-PR** flow, how design decisions are recorded in **[DECISIONS.md](DECISIONS.md)**, and the rule for reporting core Zap defects upstream in `zaplang-io/zap`.
