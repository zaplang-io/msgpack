# msgpack (Zap package) — contributor & agent conventions

This is an official **non-core** Zap package: a pure-Zap MessagePack codec. These conventions apply to everyone working in this repo, human or agent.

## Project scope & design

- **Python-parity rule.** The public API mirrors [msgpack-python](https://msgpack-python.readthedocs.io/) (`packb`/`unpackb`, `Packer`/`Unpacker`, `ExtType`, `Timestamp`, `default`/`ext_hook`, and the option set) as closely as Zap's static typing allows.
- When a shape cannot match msgpack-python cleanly — keyword-argument ergonomics, Zap's single-declared-return-type rule, a word Zap reserves, bytes-vs-str, or the dynamic value model (#10) — **do not guess.** Record the chosen deviation and its rationale in `DECISIONS.md`, keyed to the issue, citing the msgpack-python or MessagePack-spec reference it follows or departs from.
- **Byte-for-byte spec conformance.** Encoded output must match the [MessagePack spec](https://github.com/msgpack/msgpack/blob/master/spec.md); test against spec vectors and round-trips.

## Issues & PRs

- Keep issues concrete and testable, with as much detail as possible: the target msgpack-python API, the wire-format detail involved, and explicit acceptance criteria.
- Multi-issue features get an **Epic** with linked, trackable sub-issues.
- Individual issues should be **'M'-sized**. Don't split an epic into unnecessary 'S'-sized issues.
- **One issue → one PR.** Branch fresh from `origin/main`; **rebase onto `origin/main`** before opening a PR and before pushing follow-up commits.
- **All package issues live in this repo** (zaplang-io/msgpack), not in zaplang-io/zap.
- Conventional-commits PR titles.

## CI — every PR goes through CI

- **Every PR must pass CI before it is merged.** CI is the authority on correctness here: contributors (and agents) may not have a full local toolchain, so a green local run is not sufficient — the PR's CI must be green.
- Do not merge a PR with failing, pending, or skipped required checks, and do not bypass or disable CI to land a change. If CI is red, fix the PR (or the test) until it is green.
- Keep PRs small so CI stays fast and failures are easy to localize. Rebase on `origin/main` so CI runs against current main.

## Core-language defects (important)

This package is built on the Zap language and stdlib. If package work exposes a **core language or stdlib defect**:

- **Report it in `zaplang-io/zap`**, and stop at reporting it.
- **Never work around a core defect** to make this package function. Keep the dependent work blocked/draft and note the dependency.
- Do not implement a core fix here; the Zap maintainer decides who fixes it and when.

## Decisions

- Record every non-obvious API/design decision in **`DECISIONS.md`**, keyed to its issue, citing the msgpack-python or spec reference. The dynamic document value model (#10) is a notable open decision. Keep it current with every PR that changes the public surface.

## Documentation

- Keep `README.md` and `DECISIONS.md` up to date with every PR that changes behavior or the public API.
- User-exposed functions carry docstrings suitable for later documentation generation.

## Tests

- Tests are **exhaustive, not minimal** — intent documentation and a walled garden around the wire format. Cover every MessagePack type and width, round-trips, spec vectors, and especially **malformed / truncated / adversarial input** (decode limits, depth bounds, oversized lengths) — untrusted input is a first-class concern (#7).
- When fixing a bug, **first add a failing test** that reproduces it, then fix.
- Do not assume dict/set iteration order in assertions (it is unspecified in Zap); for map encoding, test as a set of pairs or sort.

## Attribution

- Commits, PR descriptions, and issue/PR bodies carry **only the author's name** — no `Co-Authored-By`, no "Generated with …", no model mention anywhere. This follows the `zaplang-io` org convention. (Issue/PR **comments** may carry a review-attribution note such as "Reviewed by …" / "… input on …".)
