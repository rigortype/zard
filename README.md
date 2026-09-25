# ZARD

ZARD is an AI-friendly Ruby self-documentation notation built around RBS and Rigor extensions. It keeps human-facing API documentation separate from checked type contracts.

The package is under active design. The current repository contains the core gem skeleton and the accepted design records; parsing and rendering are not implemented yet.

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

## Installation

Until the first RubyGems release, add the repository to your Gemfile:

```ruby
gem "zard", github: "rigortype/zard"
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

