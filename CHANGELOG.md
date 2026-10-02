# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Add the initial Ruby gem package, test, lint, signature, and CI skeleton.
- Add the versioned ZARD document model and Ruby source parser.
- Add the separate `zard-doc` gem with Markdown rendering for method parameters and returns.
- Add parsing and Markdown rendering for `@yieldparam` and `@yieldreturn` block documentation.
- Add structured option ownership plus parsing and Markdown rendering for `@option` and `@raise`.
- Add parsing and Markdown rendering for description-only documentation tags.
- Add the `zard-doc lint` command with configurable warning failure behavior.
- Add the `zard-doc render` command for generating Markdown from Ruby source files.
- Diagnose ZARD documentation in non-UTF-8 source while preserving contract channels.
- Preserve InlineRBS trailing prose separately from contract payloads.
- Support multiline descriptions with exact source provenance and Markdown list continuation.
- Discover Ruby source files recursively from `zard-doc` CLI directory inputs.
- Report all unreadable CLI inputs without emitting partial Markdown.

[Unreleased]: https://github.com/rigortype/zard/commits/master
