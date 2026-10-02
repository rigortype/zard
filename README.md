# ZARD

ZARD is an AI-friendly Ruby self-documentation notation built around RBS and Rigor extensions. It keeps human-facing API documentation separate from checked type contracts.

The package is under active design. The first vertical slice parses Ruby source into a versioned ZARD model and renders its API documentation as Markdown.

## Syntax direction

Plain RBS remains visible to the wider Ruby type ecosystem. Rigor-only refinements use `@extrbs`, while prose uses ZARD documentation tags.

```ruby
# @extrbs return: non-empty-string
# @rbs path: String
# @rbs return: String
# @param path — Path to the name file.
# @return The stored name.
def read_name(path)
  File.read(path).strip
end
```

See [CONTEXT.md](CONTEXT.md) and [docs/adr](docs/adr) for the current language and architecture decisions.

## Usage

The core gem parses Ruby source without interpreting `@extrbs` type payloads:

```ruby
document = Zard.parse(source, path: "lib/example.rb")
```

The separate `zard-doc` gem renders the API documentation in that model:

```ruby
require "zard/doc"

markdown = Zard::Doc.render(document)
```

The initial renderer supports method prose, `@param`, `@return`, `@yieldparam`, `@yieldreturn`, `@option`, `@raise`, `@note`, `@see`, `@deprecated`, and `@example`. Contracts remain available in the model and are not copied into API prose.

Lint source files with `zard-doc lint`. Warnings are reported without failing by default; use `--fail-on warning` to make them fail in CI.

Render Markdown to standard output with `zard-doc render lib/example.rb`.

ZARD documentation requires UTF-8 source text. Non-UTF-8 Ruby source may still carry `@rbs`, `#:`, and `@extrbs` contracts.

InlineRBS trailing prose after `--` is stored as a contract note. It is not copied into API documentation.

## Installation

Until the first RubyGems release, add the repository to your Gemfile:

```ruby
gem "zard", github: "rigortype/zard"
gem "zard-doc", github: "rigortype/zard"
```

## Development

Run the setup script and the default verification task:

```sh
bin/setup
bundle exec rake
```

The default task runs tests, Standard, RBS validation, and a gem build.

## License

ZARD is available under the Mozilla Public License 2.0. See [LICENSE](LICENSE).
