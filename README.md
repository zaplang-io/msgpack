# msgpack

MessagePack binary serialization for [Zap](https://github.com/zaplang-io/zap) — an official **non-core** package, a pure-Zap codec.

- Tracking issue: [zaplang-io/zap#317](https://github.com/zaplang-io/zap/issues/317)
- Roadmap: [bootstrap epic #1](https://github.com/zaplang-io/msgpack/issues/1)
- Contributor & agent conventions: [AGENTS.md](AGENTS.md)
- Design decisions: [DECISIONS.md](DECISIONS.md)

> **Status: 0.1.0 unreleased candidate.** `packb`, `unpackb`, `Packer`, and `Unpacker` support the base types, `ExtType`, and `Timestamp`.

## Goals

A pure-Zap MessagePack codec whose public API mirrors [**msgpack-python**](https://msgpack-python.readthedocs.io/) (`packb` / `unpackb`, the streaming `Packer` / `Unpacker`, `ExtType`, `Timestamp`, `default` / `ext_hook`, and the option set) as closely as Zap's static typing allows. API-parity with the popular Python library is a project rule — see [AGENTS.md](AGENTS.md). Output is byte-for-byte conformant with the [MessagePack spec](https://github.com/msgpack/msgpack/blob/master/spec.md).

## Install and run an example

Add a reviewed checkout as a Zap path dependency and materialize the project's
`zenv`. CI runs each example as an external application using that installation.
[Installation and release checklist](docs/RELEASING.md) · [Support matrix](docs/SUPPORT.md)

- Encode and decode an ordered map with a binary payload. [Round-trip example](examples/roundtrip.zap)
- Drain a stream with a value split across two feeds. [Streaming example](examples/streaming.zap)
- Use typed application extension hooks and convert an aware `DateTime`. [Extension and Timestamp example](examples/extensions.zap)

## Encoding

```zap
import msgpack

def main():
    auto value = msgpack.Value.Map([(msgpack.Value.Str("id"), msgpack.Value.Int(1))])
    auto data = msgpack.packb(value)
    auto single = msgpack.packb(msgpack.Value.Float(1.5), use_single_float=True)
```

`packb` chooses the shortest integer and collection or payload length headers. `Str` encodes UTF-8 and `Bin` keeps the original bytes. Maps retain the order and duplicates in their pair lists. Float payloads default to binary64, and `use_single_float=True` selects binary32 throughout the document. NaNs encode as a canonical quiet NaN. The encoder raises `ValueError` for invalid extension codes or timestamp nanoseconds, lengths outside the wire limit, and nesting beyond 1,024 levels.

`use_bin_type=False` selects legacy MessagePack raw headers for both strings and binary values. On decode, use `raw=True` to recover arbitrary bytes from these headers. The default reader interprets them as UTF-8 strings.

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
- `FormatError` signals malformed UTF-8, an invalid strict map key, a reserved tag or extension code, or a malformed timestamp.
- `StackError` signals a value nested beyond `max_depth`.

### Decode limits

`unpackb` and `Unpacker` accept the same limits. Supply them as keyword arguments.

| Option | Measures | Error |
| --- | --- | --- |
| `max_str_len` | UTF-8 bytes on the wire, including strings decoded with `raw=True` | `StrLimitError` |
| `max_bin_len` | Binary payload bytes | `BinLimitError` |
| `max_array_len` | Array elements | `ArrayLimitError` |
| `max_map_len` | Map pairs, including duplicate keys | `MapLimitError` |
| `max_ext_len` | Extension or Timestamp payload bytes, excluding the type code | `ExtLimitError` |
| `max_depth` | Nesting level, with the root at zero | `StackError` |

Length limits default to `-1` and allow any value that fits the available input or the streaming buffer budget. A nonnegative limit caps the declared length, with zero allowing only an empty payload or collection. `max_depth` defaults to 1,024 and can be lowered to zero. Invalid settings raise `ValueError`.

The decoder checks explicit length limits as soon as the header is complete. It checks that the remaining input can hold the payload or minimum collection size before slicing or allocating. A length within its cap can still be incomplete.

## Application extensions

Wrap `msgpack.ExtType(code, data)` in `msgpack.Value.Ext` to encode an application-defined extension. The code is an integer from 0 through 127 and the payload is `bytes`. Encoding uses `fixext` for 1, 2, 4, 8, or 16 payload bytes and the smallest variable-length extension header otherwise. The decoder returns `Value.Ext` with the original code and bytes, including inside arrays and maps. `raw` applies to text fields and leaves extension payloads as bytes.

For a top-level custom object, `packb_with_default[Record](value, default=encode)` calls your `encode` function to produce an `ExtType`. `unpackb_with_ext_hook[Record](data, ext_hook=decode)` validates one complete application extension, then calls your `decode(code, payload)` function and returns a `Record`.

## Timestamps

Use `msgpack.Value.Timestamp(msgpack.Timestamp(seconds, nanoseconds))` to encode the standard extension code `-1`. Seconds are signed Unix seconds. `nanoseconds` is a `uint32` from 0 through 999,999,999 and defaults to zero. For instants before the epoch, a positive nanosecond component is added to negative seconds. Encoding selects the shortest of the 32-, 64-, and 96-bit payload forms. Decoding returns `Value.Timestamp` with exact seconds and nanoseconds.

`timestamp_from_datetime(dt)` accepts a timezone-aware Zap `DateTime` and preserves all nine fractional digits. `Timestamp.to_datetime()` returns a timezone-aware UTC value. It raises `ValueError` for timestamps beyond years 1 through 9999. The wire codec supports the full signed 64-bit seconds range.

```zap
import datetime
import msgpack

def main():
    auto dt = datetime.rfc3339_parse("1970-01-01T05:30:00.123456789+05:30")
    auto stamp = msgpack.timestamp_from_datetime(dt)
    auto wire = msgpack.packb(msgpack.Value.Timestamp(stamp))
    match msgpack.unpackb(wire):
        case msgpack.Value.Timestamp(decoded):
            print(datetime.isoformat(decoded.to_datetime()))
```

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

## msgpack-python options

| Option | Zap API and default | Behavior |
| --- | --- | --- |
| `use_bin_type` | `packb` and `Packer`, `True` | Binary uses the bin family and text can use `str8`. `False` uses legacy raw headers for both and skips `str8`. |
| `use_single_float` | `packb` and `Packer`, `False` | `True` selects binary32 in place of the binary64 default. |
| `raw` | `unpackb` and `Unpacker`, `False` | `True` returns string payloads as `Value.Bin`, including map keys. |
| `strict_map_key` | `unpackb` and `Unpacker`, `True` | Requires string or binary keys. `False` permits arbitrary `Value` keys. |
| `max_str_len`, `max_bin_len`, `max_array_len`, `max_map_len`, `max_ext_len` | Both readers, `-1` | See [decode limits](#decode-limits) for units and typed errors. |
| `max_buffer_size` | `Unpacker`, 100 MiB | Caps unread stream bytes. |
| `datetime` and `timestamp` | Explicit `timestamp_from_datetime` and `Timestamp.to_datetime()` | The codec defaults to `Value.Timestamp` (`timestamp=0` in Python). The helpers convert an aware `DateTime` to a timestamp and convert a timestamp to UTC. |
| `default` and `ext_hook` | Typed `packb_with_default[T]` and `unpackb_with_ext_hook[T]` | Optional top-level conversion through application extensions. The ordinary encoder accepts `Value` and the ordinary decoder returns `Value.Ext` for application extensions. |
| `object_hook` and `object_pairs_hook` | Explicit conversion from `Value.Map(pairs)` | Match the map variant and convert its ordered pairs to your application type. Every duplicate key is available to the caller. |

See [option decisions](DECISIONS.md#msgpack-python-option-parity-issue-8) for the Python options that have a different shape or are outside the Zap API.

## Scope

- Core `packb`/`unpackb` for all MessagePack base types (#2/#3).
- Streaming `Packer`/`Unpacker` with incremental `feed` (#4).
- Extension types (`ExtType`) + `default`/`ext_hook` (#5), and the Timestamp extension (ext -1) (#6).
- Configurable decode limits and a deterministic malformed-input corpus (#7).
- Modern and legacy binary encoding plus the msgpack-python option mapping (#8).
- The approved `Value` model represents maps as ordered key/value pairs and preserves duplicate keys. By default, decoding accepts string and binary keys. [Value-model decision](DECISIONS.md#dynamic-document-value-model-issue-10)

## Build and test

GitHub Actions runs **MessagePack CI** on every pull request and on pushes to `main`, using `ghcr.io/zaplang-io/zap:latest`. The check must pass before merging. `sh tools/run-tests.sh` stages each suite with the library and runs the named `@test` cases using `zap test`. The tests assert exact wire bytes, round-trips, typed errors, and incremental reads across split and coalesced chunks. A native doctest checks the compiler diagnostic. CI also validates candidate metadata and runs the examples with assertions in a path-dependent application. [Changelog](CHANGELOG.md)

Codec changes should include wire-format golden vectors and round-trips for valid data, plus rejection cases for malformed and truncated input. See [AGENTS.md](AGENTS.md) for the full coverage expectations.

## Development

Read **[AGENTS.md](AGENTS.md)** before contributing — it covers the msgpack-python-parity rule, the one-issue-one-PR + **CI-per-PR** flow, how design decisions are recorded in **[DECISIONS.md](DECISIONS.md)**, and the rule for reporting core Zap defects upstream in `zaplang-io/zap`.
