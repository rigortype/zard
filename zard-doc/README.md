# zard-doc

`zard-doc` renders API documentation from the versioned model produced by `zard`.

```ruby
document = Zard.parse(source, path: "lib/example.rb")
markdown = Zard::Doc.render(document)
```

Run the linter against Ruby source files with:

```console
zard-doc lint lib/example.rb
zard-doc lint --fail-on warning lib/example.rb
```
