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

<!--
Add one section per decision as issues are implemented, e.g.:

## use_bin_type / raw defaults (issue #8)
...which msgpack-python defaults the package adopts and why...

## ExtType / ext_hook shape (issues #5/#6)
...the Zap representation of ExtType and the hook signatures...

## Decode limits (issue #7)
...default max depth / max length bounds for untrusted input...
-->
