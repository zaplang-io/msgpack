# Changelog

## 0.1.0 (Unreleased)

- Serializer encode perf (#32): `MsgpackSerializer._finish` now pops the frame
  stack in O(1) instead of re-slicing all four stack lists on every `end_*`. On a
  {int64; list×20; dict×5} payload this takes typed encode from ~8-10% slower than
  the hand-rolled DOM path to ~3% (near parity). No behavior change.
- Reworked the typed serde `unpack[T]` decoder (#30) to stream directly from the
  wire into the struct (a `_Decoder` cursor + context stack; array/map headers read
  directly, scalars decoded natively), with no intermediate `Value` DOM. On a
  {int64; list×20; dict×5} payload this takes typed decode from ~38% slower than
  the hand-rolled DOM path to ~21% faster. Wire format and behavior unchanged.
- Extended the typed `pack[T]` / `unpack[T]` serde codec to `uint64` and to
  `list[T]` / `dict[str, V]` of scalar elements (arrays and maps), matching the
  serde collection breadth in zaplang-io/zap#1594.
- Extended the typed `pack[T]` / `unpack[T]` serde codec to `float64` and `bytes`
  struct fields (binary64 floats, `bin` payloads), matching the serde breadth in
  zaplang-io/zap#1574.
- Added typed `pack[T]` / `unpack[T]` built on Zap's bundled `serde` foundation
  (zaplang-io/zap#1552): a struct (de)serializes with no per-type encoder, byte-
  identical to and interoperable with the `Value` DOM codec. Scalar `int64` /
  `str` / `bool` fields and nested-struct encode; flat scalar decode.
- Added the pure-Zap MessagePack codec with `packb`, `unpackb`, and the recursive
  `Value` model. Map entries retain input order and duplicates.
- Added `Packer` and feed-based `Unpacker` for incremental streams with a
  configurable unread-byte budget.
- Added all application extension wire formats, typed top-level extension
  hooks, and Timestamp including nanosecond-precise UTC `DateTime` conversion.
- Added modern and legacy raw encoding, explicit single-precision floats,
  raw decoding, and strict map-key validation.
- Added typed decode errors and configurable payload, collection, extension,
  and nesting limits, with wire goldens and deterministic malformed-input
  fixtures in required CI.
- Added installed-package examples with assertions, the support matrix, and
  release preflight.
- Run codec coverage as native `zap test` cases with a compiler diagnostic
  doctest.
