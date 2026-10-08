# ZARD

**ZARD** is an AI-friendly Ruby self-documentation notation built around RBS and Rigor extensions. It keeps human-facing API documentation cleanly separated from checked type contracts.

> **Status**: Under active design (pre-1.0). The current release slice parses Ruby source into a versioned model (`Zard::Model::V1`) and renders public API documentation as Markdown.

---

## Why ZARD?

In traditional Ruby documentation tools (such as YARD or RDoc), type annotations and descriptive prose are often mixed within comment tags (e.g. `@param [String] path The path`). This creates redundant, easily desynchronized type definitions alongside modern Ruby type checkers.

ZARD enforces a clean **separation of concerns**:

- **Type Contracts (`@rbs`, `#:`, `@extrbs`)**: RBS contracts define checked types for the Ruby type ecosystem. Rigor-specific refinements use `@extrbs`.
- **API Documentation (`@param`, `@return`, etc.)**: Human- and AI-facing prose explains *what* and *why* without repeating type signatures.
- **Structured Lossless Model**: The parser captures declarations, contracts, documentation, and diagnostics with precise source spans and provenance—ideal for IDEs, automated tooling, and AI agents.

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
- **Tags without names**: Tags such as `@return`, `@note`, and `@example` write their descriptions directly without an em dash.
- **Continuations**: Plain comment lines continue documentation text until the next annotation or contract.
- **Encoding**: ZARD documentation requires UTF-8 source text.

---

## Architecture & Packages

This repository provides two coordinated gems:

| Gem | Role | Description |
| --- | --- | --- |
| [`zard`](.) | Parser & Model | Parses Ruby source into a versioned, static document model (`Zard::Model::V1`) with AST and source provenance. |
| [`zard-doc`](zard-doc) | Renderer & CLI | Renders API documentation from the ZARD model into Markdown, and provides the `zard-doc` CLI tool. |

---

## Quick Start & Usage

For in-depth guides, model inspection, and exit codes, see the [Usage Guide](docs/usage.md).

### Command Line (`zard-doc`)

Lint Ruby source files or directories:

```sh
# Lint files or directories (warnings do not fail by default)
zard-doc lint lib

# Fail in CI if any warnings or errors are reported
zard-doc lint --fail-on warning lib
```

Render Markdown documentation to standard output:

```sh
# Render API documentation to stdout
zard-doc render lib

# Read Ruby source from stdin using '-'
printf '%s\n' '# @return The value.' 'def value = 1' | zard-doc render -
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

The ZARD parser models modern Ruby declarations statically without executing code. Runtime ancestry, dynamic metaprogramming, and foreign object evaluations are intentionally left unresolved.

### Visibility & Modifiers
- Declarations record `public`, `protected`, or `private` visibility. Markdown output includes public declarations only.
- Bare visibility calls, inline forms (`private def`, `private attr_reader`), named method modifiers (`private :read`), and `private_class_method` / `public_class_method` are supported.
- Visibility calls received by `self` belong to the current scope (method scope for instance visibility, singleton method scope for class methods).
- `module_function` records its private instance method and public singleton copy as separate declarations with shared provenance. Bare, named, inline, and splatted forms (`module_function(*attr_accessor(:name))`) are supported.
- `module_function` received by `self` belongs to the current module, like its bare form. Named `module_function` calls may target generated attribute methods, preserving the other accessor side with its original visibility.

### Attributes, Aliases & Method Removal
- Ruby `attr` declarations default to readers; the legacy `attr :name, true` form is preserved as an accessor. Attributes received by `self` belong to the current owner.
- Named attribute visibility modifiers are diagnosed because one attribute declaration may generate two methods; use lexical or inline visibility instead.
- Method aliases preserve their target name and inherit visibility and parameters when declared in the same source scope. Generated attribute readers and writers are valid alias targets (writer aliases use the conventional `value` parameter).
- Inline visibility and `module_function` modifiers around `alias_method` apply to the resulting alias. `alias_method` received by `self` belongs to the current method scope.
- Alias documentation remains separate from target documentation.
- `undef`, `undef_method`, and `remove_method` remove declarations from the current method scope. Removing or replacing one side of an attribute accessor preserves the other side.
- Later method, alias, and attribute definitions replace earlier declarations of the same name in the same source scope.

### Dynamic Definitions & Evaluation Blocks
- Literal `define_method` and `define_singleton_method` calls produce method declarations with preserved block parameters, visibility, receiver, refinement scope, and documentation provenance.
- `define_method` received by `self` belongs to the current method scope.
- Inline `private define_method`, `module_function define_method`, and class-method visibility modifiers around `define_singleton_method` preserve the visibility produced by Ruby.
- Declarations in bare or `self` evaluation blocks remain in the current owner. Blocks evaluated by another receiver are not attributed to the lexical owner.
- In bare or `self.instance_eval` blocks, bare `def` becomes a singleton method, while method-definition calls, attributes, and constants retain their lexical owner. Foreign instance-evaluation blocks are not resolved.

### Classes, Modules & Container Builders
- Class declarations preserve explicit superclass expressions and source spans without resolving runtime ancestry.
- Class assignments from `Data.define`, `Struct.new`, `Class.new`, and `Module.new` preserve builders, generated attributes, and block members within the container scope.
- Literal Symbol and String member names produce generated attributes; the leading String class name accepted by `Struct.new` is not a member.
- Named subclasses (e.g. `class Point < Data.define(:x)`) preserve generated attributes while retaining the explicit superclass expression.
- `Class.new(Struct.new(...))` and `Class.new(Data.define(...))` chains preserve inherited generated attributes when no intermediate factory block can override them.
- Standard library `DelegateClass(Target)` calls are treated as class builders and preserve the delegated target expression as source provenance.
- Conditional container builders (`||=`, `Registry = Registry || Module.new`) and transparent `.freeze` tails (including repeated or block forms) are supported.

### Mixins, Singletons & Refinements
- `include`, `prepend`, and `extend` targets are preserved with source spans and listed in documented containers without resolving inheritance trees. Mixin calls received by `self` belong to the current container.
- Singleton methods and attributes preserve explicit receiver expressions (or `class <<` expressions).
- Ruby `refine` blocks and their members remain scoped to the refinement target and separate from ordinary module members. `refine` received by `self` belongs to the current module.

### Constants & Namespaces
- `private_constant` and `public_constant` update constant visibility in the same namespace. Constant visibility calls received by `self` belong to the current namespace.
- Bare or `self.autoload` calls with literal Symbol or String names produce constant declarations for the current ordinary owner without guessing the loaded value's kind.
- Bare or `self.const_set` calls with literal names produce declarations in the current ordinary class or module body; container-builder values retain their generated scope.
- `remove_const` removes matching declarations and their nested APIs from the current namespace. Unconditional assignments and literal `const_set` replace earlier declarations, while conditional initialization (`||=`) is non-destructive.

---

## Installation

The `0.0.1` candidate is currently an active release candidate. Until published on RubyGems, install directly from GitHub:

```ruby
# Gemfile
gem "zard", github: "rigortype/zard"
gem "zard-doc", github: "rigortype/zard"
```

Once published, install with:

```ruby
# Gemfile
gem "zard", "~> 0.0.1"
gem "zard-doc", "~> 0.0.1"
```

**Requirements**: Ruby `>= 3.2.0`. The project is pre-1.0; compatibility guarantees for future releases have not yet been established.

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

- [Usage Guide](docs/usage.md) — Comprehensive guide on CLI options, model inspection, and exit codes.
- [Design Context (`CONTEXT.md`)](CONTEXT.md) — Core vocabulary, design principles, and anti-patterns.
- [Architecture Decision Records (`docs/adr/`)](docs/adr) — ADRs documenting syntactic and architectural decisions.
- [Catalog Example](examples/catalog) — Complete multi-file example with [expected Markdown](examples/catalog/expected.md).

---

## License

ZARD is open-source software available under the [Mozilla Public License 2.0](LICENSE).
