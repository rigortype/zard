# ZARD

**ZARD** is an AI-friendly Ruby self-documentation notation built around RBS and Rigor extensions. It keeps human-facing API documentation separate from type contracts.

> **Status**: Under active design (pre-1.0). The current release slice parses Ruby source into a versioned model (`Zard::Model::V1`) and renders public API documentation as Markdown.

---

## Why ZARD?

In traditional Ruby documentation tools (such as YARD or RDoc), type annotations and descriptive prose are often mixed within comment tags (e.g. `@param [String] path The path`). This creates redundant, easily desynchronized type definitions alongside modern Ruby type checkers.

ZARD separates contracts from API documentation:

- **Type Contracts (`@rbs`, `#:`, `@extrbs`)**: Plain RBS expresses contracts for the Ruby type ecosystem. Rigor-specific refinements use `@extrbs`.
- **API Documentation (`@param`, `@return`, etc.)**: Human- and AI-facing prose explains *what* and *why* without repeating type signatures.
- **Structured Declaration Model**: The parser captures declarations, contracts, documentation, and diagnostics with precise source spans and provenance—ideal for IDEs, automated tooling, and AI agents.

The current release preserves contract payloads as text. It does not parse or validate their types, check documentation claims against contracts, or integrate with the Rigor lens.

---

## Syntax at a Glance

ZARD separates type contracts from API prose:

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

- **Contracts**: Plain RBS uses `@rbs` or `#:`. Advanced Rigor-only refinements use `@extrbs`. Contract payloads are not copied into API documentation. Inline RBS trailing prose after `--` is stored as a contract note, not API prose.
- **Documentation Marker**: An em dash (`—`) separates named documentation tags (`@param`, `@yieldparam`, `@raise`, `@option`) or optional type claims from descriptions.
- **Tags without names or type claims**: Tags such as `@return`, `@note`, and `@example` write their descriptions directly without an em dash.
- **Continuations**: Plain comment lines continue documentation text until the next annotation or contract.
- **Encoding**: ZARD documentation requires UTF-8 source text.

---

## Architecture & Packages

This repository provides two coordinated gems:

| Gem | Role | Description |
| --- | --- | --- |
| [`zard`](.) | Parser & Model | Parses Ruby source into a versioned, static document model (`Zard::Model::V1`) with source spans and provenance. |
| [`zard-doc`](zard-doc) | Renderer & CLI | Renders API documentation from the ZARD model into Markdown, and provides the `zard-doc` CLI tool. |

---

## Installation

Both gems are available on RubyGems: [zard](https://rubygems.org/gems/zard) and [zard-doc](https://rubygems.org/gems/zard-doc). Add the released pair to your Gemfile:

```ruby
# Gemfile
gem "zard", "~> 0.0.1"
gem "zard-doc", "~> 0.0.1"
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
