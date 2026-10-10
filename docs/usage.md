# ZARD 0.0.1 usage

ZARD parses Ruby source into a versioned model. The separate `zard-doc` gem renders the model's human-facing API documentation as Markdown. Both `0.0.1` gems are available on RubyGems. Install the released pair with Bundler:

```ruby
gem "zard", "~> 0.0.1"
gem "zard-doc", "~> 0.0.1"
```

The gems require Ruby 3.2 or newer. The project is pre-1.0: the model has an explicit `Zard::Model::V1` namespace, but no general compatibility guarantee has been established yet. Review release notes when upgrading; pre-1.0 releases may change APIs and behavior.

## Parse and render

```ruby
require "zard"
require "zard/doc"

source = File.read("lib/example.rb")
document = Zard.parse(source, path: "lib/example.rb")
markdown = Zard::Doc.render(document)
```

`Zard.parse` accepts Ruby source text and a required `path:` used in provenance and diagnostics. The path labels the source; the parser does not read that file. For in-memory input, use a label such as `"example.rb"`. `Zard::Doc.render` accepts the resulting document and returns Markdown. The renderer emits documented public declarations; it does not print contracts as API prose.

## Inspect the model

The document is available through `document.path`, `document.declarations`, and `document.diagnostics`. A declaration exposes `kind`, `name`, `namespace`, `visibility`, `parameters`, `receiver`, `receiver_span`, `refinement`, `refinement_span`, `alias_target`, `superclass`, `superclass_span`, `container_builder`, `container_builder_span`, `mixins`, `span`, `comment_span`, `documentation`, and `contracts`.

Documentation entries are `DocumentationTag` objects with `name`, `owner`, `subject`, `claim`, `description`, `span`, and `raw`. Contract entries are `Contract` objects with `channel`, `payload`, `note`, `span`, and `raw`. Mixins expose `kind`, `target`, and `span`. Diagnostics expose `code`, `severity`, `message`, and `span`.

Every source span exposes `path`, `start_line`, `start_column`, `end_line`, `end_column`, `start_offset`, and `end_offset`. Lines are one-based; columns and byte offsets are zero-based, and end positions are exclusive. Raw source and spans make it possible to trace modeled content back to its source. For example:

```ruby
document.declarations.each do |declaration|
  declaration.contracts.each do |contract|
    puts "#{contract.channel}: #{contract.payload} at #{contract.span.path}:#{contract.span.start_line}"
  end
end

document.diagnostics.each do |diagnostic|
  span = diagnostic.span
  warn "#{span.path}:#{span.start_line}: #{diagnostic.severity} #{diagnostic.code}: #{diagnostic.message}"
end
```

## Contracts and API documentation

Use `@rbs` or `#:` for plain RBS contracts and `@extrbs` for Rigor-specific type information. The parser preserves contract payloads as text; it does not parse or validate their types. Keep contracts distinct from API prose. The `zard-doc` renderer does not copy contract text into Markdown.

ZARD uses an em dash (`—`) between a named documentation tag (or an optional type claim) and its description:

```ruby
# @extrbs return: non-empty-string
# @rbs path: String
# @rbs return: String
# @param path — Path to the name file.
# @return The stored name.
# @raise IOError — If the file cannot be read.
def read_name(path)
  File.read(path).strip
end
```

For example, `@param path [String] — The file path.` carries an optional documentation claim. It is not a substitute for `@rbs path: String` and is not checked by this project: there is no Rigor claim checking in this release. The parser may diagnose malformed or noncanonical documentation syntax, but does not validate claims against contracts.

Tags without a name or type write their description directly: `@return Normalized value.`, `@note Keep this in mind.`, and `@example Call the method.` Named tags such as `@param`, `@yieldparam`, `@raise`, and `@option` require the marker. `@option options :format — Output format.` documents an option. `@yieldreturn yielded value.` describes a yielded result. Supported tags include `@param`, `@return`, `@yieldparam`, `@yieldreturn`, `@option`, `@raise`, `@note`, `@see`, `@deprecated`, and `@example`.

### See also references

The complete syntax decision, including planned BitClust and RD compatibility forms, is recorded in [ADR 0004](adr/0004-documentation-reference-syntax.md).

`@see` accepts YARD-style references followed by an optional display label, without an em dash:

```ruby
# @see Foo#bar
# @see Foo.build Build a Foo
# @see #bar Related instance method
# @see .build Related class method
# @see Kernel.#puts Legacy module-function spelling
# @see Kernel?.puts Modern module-function spelling
# @see https://example.com/reference Reference guide
```

`#` selects an instance method and `.` selects a class method. `.#` and `?.` are equivalent module-function spellings and link to the public singleton copy. Relative references use the current class or module; qualified references search namespace prefixes as YARD does, and a leading `::` starts at the root. This lookup also applies to qualified class openings such as `class Outer::Caller`; it does not reproduce Ruby's lexical constant lookup. A nearer declared owner prevents fallback to an unrelated outer owner when its member is missing. The first whitespace-separated token is the target and the remaining text is the display label. HTTP, HTTPS, and mailto targets become external links.

`zard-doc` links references to uniquely identified public declarations with documentation in the generated output. The CLI resolves references across all input files. Unresolved, undocumented, private, ambiguous, and refinement references remain plain text. Lookup uses explicit declarations, without following inheritance or mixins or evaluating dynamic receivers. The document model retains the original description, raw comment, and source span.

Plain comment lines continue the preceding canonical documentation tag until another annotation or contract begins. No continuation marker is needed. Contract notes use ` -- ` after the contract payload and remain contract notes, not API prose. Familiar YARD-like tags without the em dash can be retained as raw text, but are not treated as documentation claims.

ZARD documentation requires UTF-8 source text. Ruby source encoding declarations are respected; non-UTF-8 source can still contain contracts, but documentation text in it receives a diagnostic.

## Visibility and analysis boundaries

Declarations carry `:public`, `:protected`, or `:private` visibility. `zard-doc` renders only public declarations. The parser statically models supported Ruby declaration forms; it does not execute the program. Runtime-generated declarations, dynamic names, and effects that cannot be determined from supported syntax are not resolved. Superclass, mixin, receiver, and refinement expressions are retained as source references; runtime ancestry and object identity are not inferred.

Visibility forms supported by the parser include bare visibility calls, inline forms such as `private def` and `private attr_reader`, named method modifiers such as `private :read`, and `private_class_method` / `public_class_method`. Named attribute modifiers produce a diagnostic because an attribute declaration can generate more than one method. See the [supported Ruby syntax guide](supported-ruby-syntax.md) for detailed coverage.

## Command line

`zard-doc lint PATH...` checks Ruby files. Directories are searched recursively for `*.rb`; paths are sorted and duplicates removed. Warnings do not fail by default. Use `--fail-on warning` to make warnings fail:

```sh
zard-doc lint lib
zard-doc lint --fail-on warning lib/example.rb
```

`zard-doc render PATH...` renders Markdown to standard output:

```sh
zard-doc render lib
```

Use `-` as a path to read Ruby source from standard input with either command:

```sh
printf '%s\n' '# @return A value.' 'def value = 1' | zard-doc render -
printf '%s\n' '# @param value [String] A value.' 'def value = 1' | zard-doc lint -
```

Exit codes:

- `0`: success; for `lint`, no diagnostic reached the configured failure threshold.
- `1`: `lint` found a diagnostic at or above its threshold, or `render` found an error diagnostic.
- `2`: invalid command or options, no Ruby sources found, or an input could not be read.

The default lint threshold is `error`. Lint diagnostics are written to standard output. Render diagnostics are written to standard error, and rendering does not emit partial Markdown when an input cannot be read or has an error diagnostic. Calling `Zard::Doc.render` directly does not enforce this CLI error policy; inspect `document.diagnostics` before rendering in an application.

## Complete example

The repository includes a multi-file catalog example and its expected Markdown:

```sh
bundle exec zard-doc lint examples/catalog/lib
bundle exec zard-doc render examples/catalog/lib
```

See [the example source](../examples/catalog/lib) and [expected output](../examples/catalog/expected.md). The default verification task exercises this example through the CLI and checks retained contracts and source provenance in the model.
