# ZARD

**ZARD** is a simple Ruby documentation notation, orthogonal to types. Describe what your API does, how to use it, and why it behaves that way without repeating type signatures.

Use it on its own or alongside RBS and a type checker. Documentation and type contracts stay separate, so each can evolve without duplicating the other.

> **Status**: Under active design (pre-1.0). Version 0.0.2 parses Ruby source into a versioned model (`Zard::Model::V1`), generates Markdown documentation, and exports experimental JSON for static sites.

---

## Why ZARD?

API documentation explains meaning, usage, and intent. Type contracts describe the types a program accepts and returns. Keeping these concerns separate lets you document an API without choosing a type checker or maintaining a second copy of its signatures.

ZARD keeps the notation small:

- **Write prose in Ruby comments.** Familiar tags such as `@param`, `@return`, and `@example` describe your API without requiring types.
- **Keep types in contracts.** Existing `@rbs`, `#:`, and `@extrbs` annotations remain separate from API prose.
- **Generate documentation without a type checker.** Parsing, linting, formatting, and documentation generation work independently of Rigor. The optional `zard-rigor` adapter adds type information to JSON exports when needed.

Being AI-friendly is also a design goal. ZARD captures declarations, documentation, contracts, and diagnostics in a structured model with precise source spans and provenance, so editors, automated tools, and AI agents can work with the same information people read in the source.

The core parser preserves contract payloads as text. It does not parse or validate their types or check documentation claims against contracts.

---

## Syntax at a Glance

Document an API with plain prose and a few tags:

```ruby
# Read the stored name from a file.
# @param path — Path to the name file.
# @return The stored name.
# @raise IOError — If the file cannot be read.
def read_name(path)
  File.read(path).strip
end
```

This documentation stands on its own. If the method also has type contracts, keep them in their own annotations; the prose does not need to repeat them.

- **Contracts**: Plain RBS uses `@rbs` or `#:`. Advanced Rigor-only refinements use `@extrbs`. Contract payloads are not copied into API documentation. Inline RBS trailing prose after `--` is stored as a contract note, not API prose.
- **Documentation Marker**: An em dash (`—`) separates named documentation tags (`@param`, `@yieldparam`, `@raise`, `@option`) or optional type claims from descriptions.
- **Tags without names or type claims**: Tags such as `@return`, `@note`, and `@example` write their descriptions directly without an em dash.
- **Continuations**: Plain comment lines continue documentation text until the next annotation or contract.
- **Encoding**: ZARD documentation requires UTF-8 source text.

---

## Architecture & Packages

ZARD separates parsing, documentation generation, optional type enrichment, and site presentation into packages. The three Ruby gems are released as 0.0.2; the Astro package is not yet released.

| Package | Role | Description |
| --- | --- | --- |
| [`zard`](.) | Parser & Model | Parses Ruby source into a versioned, static document model (`Zard::Model::V1`) with source spans and provenance. |
| [`zard-doc`](zard-doc) | Renderer & CLI | Renders API documentation from the ZARD model into Markdown, and provides the `zard-doc` CLI tool. |
| [`zard-rigor`](zard-rigor) | Optional adapter | Enriches JSON exports through the released Rigor 0.4.5 CLI (`lens/v0` revision 1), without loading analyzer internals. |
| [`zard-doc-astro`](zard-doc-astro/README.md) (unreleased) | Astro presentation | Consumes JSON exports to produce unstyled API HTML and Starlight page data. Consumer sites own CSS and publication. Not yet published to npm. |

---

## Installation

Install [zard](https://rubygems.org/gems/zard) and [zard-doc](https://rubygems.org/gems/zard-doc) 0.0.2 from RubyGems by adding the pair to your Gemfile:

```ruby
# Gemfile
gem "zard", "~> 0.0.2"
gem "zard-doc", "~> 0.0.2"
```

Run `bundle install` after adding the gems to your Gemfile.

**Requirements**: Ruby `>= 3.2.0`. The project is pre-1.0; compatibility guarantees for future releases have not yet been established.

---

## Quick Start & Usage

For in-depth guides, model inspection, and exit codes, see the [Usage Guide](docs/usage.md).

### Command Line (`zard-doc`)

Lint Ruby source files or directories:

```sh
# Lint files or directories (warnings do not fail by default)
bundle exec zard-doc lint lib

# Fail in CI if any warnings or errors are reported
bundle exec zard-doc lint --fail-on warning lib
```

Render Markdown documentation to standard output:

```sh
# Render API documentation to stdout
bundle exec zard-doc render lib

# Read Ruby source from stdin using '-'
printf '%s\n' '# @return The value.' 'def value = 1' | bundle exec zard-doc render -
```

**Exit Codes**:

- `0`: Success (no diagnostic met the failure threshold).
- `1`: Diagnostic error (or warning when `--fail-on warning` is set), or render error.
- `2`: Invalid CLI usage, no Ruby sources found, or unreadable input.

### Ruby API

```ruby
require "zard"
require "zard/doc"

# 1. Parse Ruby source into the versioned model
source = File.read("lib/example.rb")
document = Zard.parse(source, path: "lib/example.rb")

# 2. Render public API documentation as Markdown
markdown = Zard::Doc.render(document)
```

The renderer emits documented public declarations and supports class, module, constant, attribute, and method prose, as well as `@param`, `@return`, `@yieldparam`, `@yieldreturn`, `@option`, `@raise`, `@note`, `@see`, `@deprecated`, and `@example`. Contracts remain in the model and are not duplicated into API prose.

Version 0.0.2 provides `zard-doc build --config zard-doc.yml --format json` for static-site consumers. It exports public declarations, documentation, unparsed contracts, source provenance, and scoped page/link metadata to stdout without publishing files. This experimental [JSON export](docs/json-export.md) works independently of Rigor; install the optional `zard-rigor` gem to enrich it with reviewed lens facts.

The experimental [`zard-doc-astro`](zard-doc-astro/README.md) JavaScript package owns unstyled API presentation and a separate Starlight adapter. Consumer sites own CSS, source acquisition, localization and publication; the Ruby gems do not depend on Astro.

---

## Supported Ruby Semantics

The parser models supported Ruby declarations statically without executing code. Runtime ancestry, dynamic names, and foreign object evaluations remain unresolved.

- Public declarations are rendered; private and protected declarations remain available in the model.
- Supported forms include visibility modifiers, attributes, aliases, method removal, and literal method definitions.
- Class and module builders, mixins, singleton declarations, and refinements retain source references and provenance.
- Constant visibility, removal, replacement, and conditional initialization are modeled.

See the [supported Ruby syntax guide](docs/supported-ruby-syntax.md) for exact forms and limits.

---

## Development

Set up dependencies and run the test suite:

```sh
bin/setup
bundle exec rake
```

The default rake task runs tests, StandardRB linting, RBS type validation, and gem packaging.

---

## Documentation & References

- [Usage Guide](docs/usage.md) — CLI options, model inspection, and exit codes.
- [Supported Ruby Syntax](docs/supported-ruby-syntax.md) — Declaration forms and static analysis limits.
- [Design Context (`CONTEXT.md`)](CONTEXT.md) — Core vocabulary, design principles, and anti-patterns.
- [Architecture Decision Records (`docs/adr/`)](docs/adr) — ADRs documenting syntactic and architectural decisions.
- [Catalog Example](examples/catalog) — Complete multi-file example with [expected Markdown](examples/catalog/expected.md).

---

## License

ZARD is open-source software available under the [Mozilla Public License 2.0](LICENSE).
