# zard-doc

`zard-doc` renders API documentation from the versioned model produced by `zard`.

```ruby
document = Zard.parse(source, path: "lib/example.rb")
markdown = Zard::Doc.render(document)
```
