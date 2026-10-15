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

## Format annotations

Repository builds provide `Zard.format` and `zard-doc format` (not included in the published 0.0.1 gems):

```ruby
result = Zard.format(source, path: "lib/example.rb")
puts result.source if result.changed?
document = result.document
diagnostics = result.diagnostics
```

The result contains formatted source and a freshly parsed document with spans and raw text referring to that source. The input remains unchanged. `diagnostics` includes parser diagnostics and formatting warnings.

```sh
zard-doc format lib/example.rb
zard-doc format --check lib
zard-doc format --write lib
printf '# @return — Value.\ndef read = nil\n' | zard-doc format -
```

Plain mode prints one input to stdout. Check mode returns 1 if any input would change; write mode updates changed files after reading and validating all inputs. Both modes accept files and recursive directories. Standard input is supported in plain and check modes. Invocation and I/O errors return 2; source errors return 1. Warnings are printed to stderr and do not fail formatting.

Formatting normalizes standalone `@extrbs` prefixes and moves them before other annotations only when reparsing preserves documentation and contract content. It removes redundant markers from untyped `@return` and `@yieldreturn`. Payloads, notes, multiline descriptions, unrelated bytes, and the original sequence of line endings are retained. YARD-like tags and ambiguous continuation boundaries are diagnosed without conversion. Invalid Ruby and non-UTF-8 source remain unchanged with errors. See [ADR 0005](adr/0005-safe-annotation-formatting.md) for the transformation limits.

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

The complete syntax decision, including BitClust and RD compatibility forms, is recorded in [ADR 0004](adr/0004-documentation-reference-syntax.md).

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

Explicit references work in prose and documentation tag descriptions, including `@see`:

```ruby
# Read [m:Foo#bar] or [[m:Foo#bar]].
# @note See [c:Foo] and [m:Foo::LIMIT].
# @see [Read a value](m:Foo#bar)
# @see [`Foo#bar()`](m:Foo#bar)
# @see [m:Kernel?.puts]
# @see [[m:Kernel.#puts]]
```

`m:` selects methods or constants; `c:` selects classes or modules. BitClust's single brackets and RD's double brackets resolve to the same destinations. `[label](m:target)` supplies a display label; a label consisting entirely of a backtick code span keeps its code presentation. Escape operator brackets as `[m:Foo#\[\]]`, or use the historical RD form `[[m:Foo#[] ]]` with its delimiter-separating space.

Inline code, fenced and indented code blocks, and `@example` content retain literal reference syntax. Existing Markdown links and images are preserved. Explicit forms in `@see` take precedence over shorthand parsing; unresolved forms retain their original text.

Plain comment lines continue the preceding canonical documentation tag until another annotation or contract begins. No continuation marker is needed. Contract notes use ` -- ` after the contract payload and remain contract notes, not API prose. Familiar YARD-like tags without the em dash can be retained as raw text, but are not treated as documentation claims.

ZARD documentation requires UTF-8 source text. Ruby source encoding declarations are respected; non-UTF-8 source can still contain contracts, but documentation text in it receives a diagnostic.

## Visibility and analysis boundaries

Declarations carry `:public`, `:protected`, or `:private` visibility. `zard-doc` renders only public declarations. The parser statically models supported Ruby declaration forms; it does not execute the program. Runtime-generated declarations, dynamic names, and effects that cannot be determined from supported syntax are not resolved. Superclass, mixin, receiver, and refinement expressions are retained as source references; runtime ancestry and object identity are not inferred.

Visibility forms supported by the parser include bare visibility calls, inline forms such as `private def` and `private attr_reader`, named method modifiers such as `private :read`, and `private_class_method` / `public_class_method`. Named attribute modifiers produce a diagnostic because an attribute declaration can generate more than one method. See the [supported Ruby syntax guide](supported-ruby-syntax.md) for detailed coverage.

## Command line

### Build a documentation tree

Repository builds provide `zard-doc build` (not included in the published 0.0.1 gems). Define named documentation scopes in a YAML file:

```yaml
docroot: docs/api
layout: namespace
scopes:
  core:
    destination: core
    sources:
      - root: lib
        include: ["**/*.rb"]
        exclude: ["fixtures/**"]
  playground:
    destination: playground
    references: [core]
    sources:
      - root: apps/playground/lib
        include: ["**/*.rb"]
```

```sh
zard-doc build --config zard-doc.yml
zard-doc build --config zard-doc.yml --scope playground --layout file
zard-doc build --config zard-doc.yml --format json > api.json
```

Paths are relative to the configuration file. The default layout is `namespace`: reopened classes and modules share a page, preserving each definition's description and source location. `file` preserves each source root's relative file hierarchy with `.md` extensions. A source mapping can set `prefix` to distinguish multiple roots in file layout. `include` defaults to `["**/*.rb"]`; `exclude` defaults to `[]`. Source selection uses globs independently of Git and gemspecs.

CLI layout overrides configuration. With no `--scope`, all scopes are built; repeat `--scope` to select several. Selected scopes include their recursive documentation dependencies for generation. References search the current scope first, then only directly declared dependencies. Separate scopes do not merge declarations even when Ruby namespace names match. Ambiguous references remain text with warnings; local shadowing prevents fallback to unrelated dependency declarations.

The default `--format markdown` publishes managed Markdown pages. `--format json` instead prints one experimental, versioned JSON document after validation and leaves `docroot` untouched. JSON includes public declarations even without prose, their original documentation and unparsed contracts, source spans and digests, page assignments, stable anchors, and resolved documentation links. Private and protected declarations are excluded. See the [JSON export contract](json-export.md) for the schema, path conventions, and differences from Markdown publication. This export does not require Rigor or a Rigor lens result.

Each scope has an index. Namespace pages follow Ruby namespace hierarchy, with documented top-level members in `_top-level.md`. Files without publishable declarations produce no API page. The documentation root has an index linking the scopes. Links use relative paths and stable anchors.

Build reports diagnostics to stderr and does not print generated Markdown to stdout. Source errors return 1; configuration, input, ownership, and publication errors return 2. Warnings permit generation. All selected inputs and destinations are validated before publication. Missing roots or dependencies, empty source selections, conflicting destinations, and paths escaping declared roots are errors.

The output manifest tracks generated pages and resolved API links. Regeneration removes obsolete managed pages, retains unrelated handwritten files, and refuses to overwrite edited managed pages or existing unowned destination files. Partial scope builds retain other scopes' managed pages and refuse changes that would invalidate their generated links; include the affected scopes or run a full build instead. Publication prepares output before writing, attempts recovery on filesystem failures, and reports recovery failures; it is not a filesystem-wide atomic transaction.

This workflow uses the existing ZARD parse model. External RBS ingestion is separate work; Rigor lens integration is deferred to the `v0.1.0` goal. See [ADR 0006](adr/0006-hierarchical-documentation-output.md).

### Lint and render to stdout

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
