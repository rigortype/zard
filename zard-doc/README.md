# zard-doc

`zard-doc` renders API documentation from the versioned model produced by `zard`.

See the [ZARD usage guide](https://github.com/rigortype/zard/blob/master/docs/usage.md) for installation, canonical tag syntax, model access, limitations, and exit codes. Install the 0.0.2 pair with Bundler:

```ruby
gem "zard", "~> 0.0.2"
gem "zard-doc", "~> 0.0.2"
```

```ruby
require "zard"
require "zard/doc"

document = Zard.parse(source, path: "lib/example.rb")
markdown = Zard::Doc.render(document)
```

Descriptions may continue across plain comment lines until the next annotation or contract.

Run the linter against Ruby source files with:

```console
zard-doc lint lib
zard-doc lint --fail-on warning lib/example.rb
```

Render Markdown to standard output with:

```console
zard-doc render lib
```

Version 0.0.2 provides hierarchical monorepo documentation with `zard-doc build --config zard-doc.yml`. Named scopes separate applications; namespace or file layouts, direct documentation dependencies, and managed output updates are described in the [usage guide](https://github.com/rigortype/zard/blob/master/docs/usage.md#build-a-documentation-tree). Optional experimental Rigor lens integration is provided by the separate `zard-rigor` gem.

`zard-doc build --config zard-doc.yml --format json` exports one experimental JSON document to stdout instead of publishing Markdown. It includes declarations selected by independent Ruby visibility and documentation intent policies, with or without prose, plus unparsed contracts, source provenance and digests, and scoped page assignments and links. Both axes default to public. Use the canonical `@api internal — explanation` marker for an internal declaration; an unmarked declaration has public documentation intent. See the [JSON export contract](https://github.com/rigortype/zard/blob/master/docs/json-export.md) for root and per-scope `publication` settings. The export needs no Rigor installation and is not a Rigor lens result.

Version 0.0.2 also provides annotation formatting:

```console
zard-doc format lib/example.rb
zard-doc format --check lib
zard-doc format --write lib
```

Formatting preserves contract payloads, descriptions, and line endings. Ambiguous documentation and unsafe contract reorderings retain their text with diagnostics. Plain mode prints one input; check mode exits with 1 when changes are needed; write mode validates all inputs before changing files. Source errors exit with 1 and invocation or I/O errors with 2. Formatting diagnostics go to standard error.

Directories are searched recursively for Ruby source files. Files are processed in stable sorted order and duplicate paths are ignored.
Unreadable inputs are reported together; rendering never emits partial Markdown when any input cannot be read.
Use `-` as a path to read Ruby source from standard input.

`lint` exits with 0 when no diagnostic meets the configured failure threshold, 1 when a diagnostic meets it, and 2 for invalid usage or unreadable input. The default threshold is `error`; `--fail-on warning` also fails on warnings. `render` exits with 1 for error diagnostics, 2 for invalid usage or unreadable input, and 0 otherwise. Diagnostics go to standard error for `render`; lint diagnostics go to standard output.
