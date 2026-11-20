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

## Open: dynamic document value model (issue #10)

Zap is statically typed, but `unpackb` of arbitrary MessagePack needs a single
declared return type that can hold any of nil / bool / int / float / str / bin /
array / map / ext. How that dynamic value is represented (a tagged union type,
its accessors, and how `strict_map_key` and `raw` interact with it) is a
**design decision to be recorded here when taken** (#10). Until then, typed
`packb`/`unpackb` against known shapes is the buildable surface.

<!--
Add one section per decision as issues are implemented, e.g.:

## use_bin_type / raw defaults (issue #8)
...which msgpack-python defaults the package adopts and why...

## ExtType / ext_hook shape (issues #5/#6)
...the Zap representation of ExtType and the hook signatures...

## Decode limits (issue #7)
...default max depth / max length bounds for untrusted input...
-->
