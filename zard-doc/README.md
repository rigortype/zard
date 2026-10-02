# zard-doc

`zard-doc` renders API documentation from the versioned model produced by `zard`.

```ruby
document = Zard.parse(source, path: "lib/example.rb")
markdown = Zard::Doc.render(document)
```

Descriptions may continue across plain comment lines until the next annotation or contract.

Run the linter against Ruby source files with:

```console
zard-doc lint lib/example.rb
zard-doc lint --fail-on warning lib/example.rb
```

Render Markdown to standard output with:

```console
zard-doc render lib/example.rb
```
