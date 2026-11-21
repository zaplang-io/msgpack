# Changelog

## 0.1.0 (Unreleased)

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
