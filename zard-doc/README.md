# zard-doc

`zard-doc` renders API documentation from the versioned model produced by `zard`.

See the [ZARD usage guide](https://github.com/rigortype/zard/blob/master/docs/usage.md) for installation, canonical tag syntax, model access, limitations, and exit codes. Both `0.0.1` gems are available on RubyGems. Install the released pair with Bundler:

```ruby
gem "zard", "~> 0.0.1"
gem "zard-doc", "~> 0.0.1"
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

Directories are searched recursively for Ruby source files. Files are processed in stable sorted order and duplicate paths are ignored.
Unreadable inputs are reported together; rendering never emits partial Markdown when any input cannot be read.
Use `-` as a path to read Ruby source from standard input.

`lint` exits with 0 when no diagnostic meets the configured failure threshold, 1 when a diagnostic meets it, and 2 for invalid usage or unreadable input. The default threshold is `error`; `--fail-on warning` also fails on warnings. `render` exits with 1 for error diagnostics, 2 for invalid usage or unreadable input, and 0 otherwise. Diagnostics go to standard error for `render`; lint diagnostics go to standard output.
