# msgpack package decisions

Design decisions for the Zap `msgpack` package, keyed to issues. Each records a
choice that could not be read straight off
[msgpack-python](https://msgpack-python.readthedocs.io/) or the
[MessagePack spec](https://github.com/msgpack/msgpack/blob/master/spec.md), with
the reference it follows or departs from.

## Parity target: msgpack-python

The package tracks [**msgpack-python**](https://msgpack-python.readthedocs.io/)
as its primary API reference (`packb`/`unpackb`, `Packer`/`Unpacker`, `ExtType`,
`Timestamp`, `default`/`ext_hook`, and the option set). It is the de-facto
standard Python MessagePack library, so matching it gives Zap users the
least-surprise surface. Deviations are recorded below, keyed to the issue that
introduces them.

## Wire format: byte-for-byte spec conformance

Encoded output must match the MessagePack spec exactly (type tags, widths,
canonical int sizing). Conformance is tested against spec vectors and
round-trips, not just internal consistency.

## Dynamic document value model (issue #10)

`packb` accepts a recursive `Value` enum. `unpackb` and streaming `Unpacker`
return the same type. The variants are `Nil`, `Bool`, `Int`, `UInt`, `Float`,
`Str`, `Bin`, `Array(list[Value])`, `Map(list[(Value, Value)])`, `Ext(ExtType)`,
and `Timestamp(Timestamp)`. Callers match on the variants to inspect values.
A typed conversion layer can be added later for callers with known schemas.

- **Maps.** A map is a list of key/value pairs in input order, including
  repeated keys. Python's default `dict` keeps the last value for a duplicate
  key. The Zap representation follows the pair list supplied to Python's
  `object_pairs_hook`, so callers can choose how to handle duplicates without
  losing entries at decode time. [msgpack-python map decoding](https://github.com/msgpack/msgpack-python/blob/main/msgpack/fallback.py)
- **Map keys.** `strict_map_key=True` is the decode default and accepts only
  MessagePack strings and binary values as map keys, including in nested
  maps. `False` allows any `Value` as a key, including arrays and maps. The
  pair list has no hashability requirement. [msgpack-python `Unpacker`](https://msgpack-python.readthedocs.io/en/latest/api.html#msgpack.Unpacker)
- **Numbers.** Decode integers that fit in `int64` as `Int`, and larger
  positive integers as `UInt` through `2^64 - 1`. Decode both float widths as
  `Float` with a `float64` payload. The variants represent decoded values
  independently of the input bytes' numeric width. [MessagePack type system](https://github.com/msgpack/msgpack/blob/master/spec.md#type-system)
- **Text and binary.** With `raw=False` (the default), decode MessagePack
  strings as UTF-8 `Str` and binary payloads as `Bin`. With `raw=True`, decode
  strings as `Bin` too, including map keys. Pair order and duplicates survive
  even when a string and binary key decode to identical bytes. [msgpack-python `Unpacker`](https://msgpack-python.readthedocs.io/en/latest/api.html#msgpack.Unpacker)
- **Extensions.** `ExtType` holds an application code from 0 through 127 and
  a bytes payload. Code -1 decodes to `Timestamp`, with signed 64-bit seconds
  and nanoseconds from 0 through 999,999,999. Reject other reserved codes by
  default. [MessagePack extension types](https://github.com/msgpack/msgpack/blob/master/spec.md#extension-types), [msgpack-python `ExtType` and `Timestamp`](https://msgpack-python.readthedocs.io/en/latest/api.html#msgpack.ExtType)

## Base encoder floats and nesting (issue #2)

`packb` defaults to binary64. `use_single_float=True` selects binary32 with
round-to-nearest, ties-to-even, matching the behavior of msgpack-python's
C extension. Both widths preserve signed zero and infinity. The pure-Zap
encoder emits a canonical positive quiet NaN for any NaN input. MessagePack
allows IEEE 754 NaNs and leaves their payload bits unspecified. The encoder
limits nesting to 1,024 levels, the same budget used by msgpack-python.
[MessagePack float formats](https://github.com/msgpack/msgpack/blob/master/spec.md#float-format-family), [msgpack-python packer](https://github.com/msgpack/msgpack-python/blob/main/msgpack/_packer.pyx)

## Single-document decode errors and bounds (issue #3)

`unpackb` reports incomplete input through the catchable `OutOfData` type.
This uses the msgpack-python streaming error name for both entry points.
Python's one-shot `unpackb` uses `ValueError` for incomplete input. The Zap
decoder raises `ExtraData` when a complete value is followed by more bytes,
`FormatError` for invalid or unsupported formats, and `StackError` for
nesting beyond 1,024 levels. It verifies that declared lengths can fit in
the remaining input before slicing payloads or allocating collections.
Issue #7 adds configurable per-type limits to both readers.
[msgpack-python decode errors](https://msgpack-python.readthedocs.io/en/latest/api.html#msgpack.unpackb)

## Feed-based streaming (issue #4)

`Packer.pack` returns the bytes for one value, following msgpack-python's
default autoreset behavior. Callers write those bytes to their stream.
`Unpacker` takes bytes via `feed`; iteration ends on `OutOfData` and resumes
on subsequent feeds. The initial streaming surface covers immediate-return
packing and caller-managed input. Accumulating packer output (`autoreset=False`)
and file-like input are outside this surface.

The default unread-byte budget is 100 MiB. A zero budget setting selects
`2^32 - 1` bytes. `BufferFull` leaves the unread bytes and framing position
intact. The framer resumes from its saved position and delegates each complete
value to `unpackb`, which keeps text and key validation consistent with one-shot
decoding. An invalid frame remains at the front of the stream.
[msgpack-python streaming API](https://msgpack-python.readthedocs.io/en/latest/api.html#msgpack.Unpacker)

## Typed application extension hooks (issue #5)

Python's `default` and `ext_hook` can accept or return arbitrary objects.
Zap uses typed top-level helpers so the core APIs can retain `Value` for
heterogeneous documents. `packb_with_default[T]` invokes `default(T) -> ExtType`
once and encodes that extension. `unpackb_with_ext_hook[T]` invokes
`ext_hook(int64, bytes) -> T` only after validating exactly one top-level
application extension. Nested extensions remain `Value.Ext` for the caller to
interpret. Callback exceptions propagate to the caller.
[msgpack-python hooks](https://msgpack-python.readthedocs.io/en/latest/api.html)

## Timestamp `DateTime` conversion (issue #6)

`timestamp_from_datetime(dt)` and `Timestamp.to_datetime()` keep the
`Value` signatures of `packb` and `unpackb` fixed. Encoding requires an aware
`DateTime`, following msgpack-python's `datetime=True` pack option. It uses
the stored offset to obtain Unix seconds and preserves the nanosecond field.
Decoding to `DateTime` returns an aware UTC value and preserves the same
fraction. Python's `datetime` conversion is limited to microseconds. Its
standalone `Timestamp.from_datetime` also interprets naive values in the
host timezone, while the aware-input rule here makes encoding independent
of the host. The `DateTime` helper uses the Python year range 1 through 9999.
`Timestamp` itself covers all signed 64-bit seconds.
[msgpack-python `Timestamp`](https://msgpack-python.readthedocs.io/en/latest/api.html#msgpack.Timestamp), [Zap subsecond DateTime](https://github.com/zaplang-io/zap/issues/1148), [Zap timezone handling](https://github.com/zaplang-io/zap/issues/1149)

## Decode limits (issue #7)

Both readers use the `max_str_len`, `max_bin_len`, `max_array_len`,
`max_map_len`, and `max_ext_len` keyword names from msgpack-python. A setting
of `-1` leaves the length bounded by the available input or the streaming
buffer budget. An explicit nonnegative cap applies to the declared wire
length before any payload or collection is materialized. This means a string
decoded with `raw=True` is subject to the string cap, and a timestamp is
subject to the extension payload cap. Every map pair counts toward its cap.

Each length cap has a distinct exception. A complete over-limit header raises
its limit error even if its body has yet to arrive. A short header or a body
that fits the configured limits can still raise `OutOfData`. A streaming
limit error leaves the offending input in place.

`max_depth` is configurable from 0 to 1,024 and uses 1,024 by default. The
root is at depth zero, with children, map keys, and map values counted one
level deeper. Nesting beyond the configured depth raises `StackError`.
[msgpack-python resource limits](https://msgpack-python.readthedocs.io/en/latest/api.html#msgpack.Unpacker)

## msgpack-python option parity (issue #8)

The defaults are `use_bin_type=True`, `use_single_float=False`, `raw=False`,
and `strict_map_key=True`, matching msgpack-python. `use_bin_type=False`
applies the legacy raw header family to strings and binary values, including
keys and nested values. It selects `fixstr`, `str16`, or `str32`, skipping
`str8`. The `raw` read option recovers the bytes of those values. Strict key
validation still applies to raw reads. Extensions and timestamps keep their
wire types in both modes.

The approved `Value` type uses lists for arrays and ordered pairs for maps.
The remaining Python options relate to the API shape rather than the wire
format.

| Python option | Zap behavior |
| --- | --- |
| `datetime=True`, `timestamp=3` | Use the explicit `DateTime` helpers from issue #6. Dynamic timestamp modes 1 and 2 produce a float or an integer in Python. Zap returns the seconds and nanoseconds together as `Value.Timestamp`. |
| `default`, `ext_hook` | The typed top-level helpers from issue #5 keep a single declared input or result type. |
| `object_hook`, `object_pairs_hook` | Match `Value.Map(pairs)` after decoding and convert the ordered pairs explicitly. This gives callers control over duplicate keys and keys that cannot be represented in a dictionary. |
| `use_list`, `list_hook` | Arrays always decode as `Value.Array(list[Value])`. Callers can convert the list after decoding. |
| `strict_types` | The encoder already requires explicit `Value` variants, so there is no Python subtype dispatch to configure. |
| `unicode_errors` | `Str` validates UTF-8. Use `raw=True` to handle the original bytes explicitly. |
| `autoreset`, `buf_size` | `Packer.pack` returns encoded bytes per call, as in the default autoreset mode. Callers manage output buffering. |
| `file_like`, `read_size` | The source owns reads and supplies bytes with `Unpacker.feed`. |

[msgpack-python options](https://msgpack-python.readthedocs.io/en/latest/api.html), [msgpack-python legacy headers](https://github.com/msgpack/msgpack-python/blob/main/msgpack/fallback.py)

## Typed struct codec over serde (issue #24, tracks zaplang-io/zap#1552)

`pack[T](value) -> bytes` / `unpack[T](bytes) -> T` serialize an arbitrary struct
through Zap's bundled `serde` foundation (zaplang-io/zap#1570) instead of a
hand-written per-type encoder. A struct maps to a MessagePack **map** of field
name → value in field-declaration order — byte-identical to the equivalent
`Value.Map(...)` + `packb` (tested in `tests/serde_test.zap`), so the typed path
and the `Value` DOM codec interoperate in both directions.

msgpack is a **pure library** here: it implements the `serde.Serializer` /
`serde.Deserializer` backend interfaces and reuses serde's generic, fully
monomorphized drivers — no per-codec compiler support (the point of
zaplang-io/zap#1248).

Decisions / deviations:
- **Struct → map**, not array: follows msgpack-python's dict encoding and keeps
  field names on the wire; keys are written in declaration order.
- `serde.begin_struct` carries no field count, so `MsgpackSerializer` buffers each
  struct's entries in a frame stack and backfills the map header at `end_struct`.
- `unpack` takes an explicit type (`unpack[Rec](data)`): serde's deserialize target
  type cannot be inferred from the bytes.
- **Scope this release** (serde's current surface): scalars (`int64` / `uint64` /
  `float64` / `str` / `bool` / `bytes`), nested structs on encode, and `list[T]` /
  `dict[str, V]` of scalar elements (both directions). `list` encodes as a
  MessagePack array, `dict` as a map, `uint64` as an unsigned int, `float64` as
  binary64, `bytes` as a bin header. Serde nested-struct decode and enum/generic
  decode remain later additions.
  Wider field types (float, the integer-width tower, bytes, lists, maps, `Optional`,
  enums) and a direct-to-struct (DOM-free) decode follow serde's breadth work
  (zaplang-io/zap#1561 and the serde breadth follow-up). The `Value` DOM codec
  remains the path for those today.
- **Requires** a Zap toolchain that bundles `serde` (zaplang-io/zap#1570); this is
  gated on that landing in the compiler CI uses.
