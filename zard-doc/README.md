# zard-doc

`zard-doc` renders API documentation from the versioned model produced by `zard`.

```ruby
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
