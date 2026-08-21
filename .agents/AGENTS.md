# Agent Instructions

## Documentation: update by hand on every API change

This project has **no documentation generation**. All documentation is written
and maintained by hand. Whenever you change code, update the documentation in
the same change.

### On any API change

When you add, remove, or modify any public declaration (types, enum variants,
fields, methods, constructors, function signatures, default values), you MUST
update **both** copies of the documentation:

1. `src/*.cj` — the `/** */` doc comment above the declaration.
2. `docs/api/` — the matching entry in the relevant category page.

These two locations must always mirror each other. Do not change one without
the other.

### Documentation structure

- `README.md` — the front door: tagline, demo image, feature list, quick start,
  documentation links.
- `docs/api/` — the API reference (rustdoc-style), one page per category:
  - `index.md` — package overview and item index
  - `enums.md`, `structs.md`, `interfaces.md`, `classes.md`, `functions.md`
  - Each entry is terse: heading + full declaration + one-line summary.
- `docs/archive/` — retired documentation. Preserve it, but do not reference
  or link to it from active docs.
- `docs/assets/` — images (e.g., the README demo screenshot).

### TODO.md

`TODO.md` at the repo root tracks deferred work (e.g., re-adding copyright
headers). Update it when the tracked item is done.

## Examples

`examples/` is a separate cjpm package (module `examples`) that depends on the
`diagnostic` package via `path = ".."`. It is a single executable with its
sources at the package root (`src-dir = "."`). Each example is one file with
one `run<Name>()` function that `main.cj` dispatches:

- `basic_cli.cj`, `jsonrpc.cj`, `labels.cj`, `related_info.cj`, `configuration.cj`

Because the sources sit at the package root, cjpm names the output binary
`main`, so bare `cjpm run` works.

Run from `examples/`:

```text
cjpm run                        # runs all examples
cjpm run -- --example basic_cli # runs one example
```

When you add or change a feature, keep the examples exercising it, and keep
them building (`cd examples && cjpm build`).