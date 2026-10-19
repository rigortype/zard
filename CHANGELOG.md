# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.2] - 2026-10-19

Generate scoped API documentation and versioned JSON for static sites, optionally enriched by released Rigor lens facts. This release also adds annotation formatting and an unstyled Astro presentation package; consumer sites own styling and publication.

### Added

- Build hierarchical Markdown documentation for explicitly configured monorepo scopes, with namespace or file organization, direct dependency links, navigation indexes, and managed output updates.
- Link YARD-style `@see` references and URLs in generated Markdown, including cross-file CLI references and equivalent `.#` and `?.` module-function spellings.
- Link BitClust Markdown and RD-compatible references in prose and documentation tags while preserving code regions, existing Markdown links, and source provenance.
- Format annotation layout through `Zard.format` and `zard-doc format`, with safe contract ordering, redundant-marker removal, check/write modes, and reparsed source provenance.
- Export experimental `zard-doc/v0` revision 1 JSON with public declarations, exact Ruby parameter syntax, source snapshots, scoped links and written superclass/mixin relationships ([#22](https://github.com/rigortype/zard/pull/22), [#23](https://github.com/rigortype/zard/pull/23), [#25](https://github.com/rigortype/zard/pull/25)).
- Enrich exports through the optional `zard-rigor` gem and released Rigor 0.4.5 CLI, preserving shared signatures, per-definition returns, provenance and explicit unavailable reasons without loading analyzer internals ([#24](https://github.com/rigortype/zard/pull/24), [#27](https://github.com/rigortype/zard/pull/27)).
- Consume constant value types, aliases, module functions and readable declared block types with exact source matching and separate instance/singleton member bindings; only Rigor 0.4.5 is supported.
- Provide the experimental, unpublished `zard-doc-astro` package with unstyled accessible HTML, Starlight routes, grouped member navigation, definition/name sorting, native documentation disclosures and class/module relationship browsing.

## [0.0.1] - 2026-10-11

The first ZARD release separates Ruby API documentation from RBS and Rigor contracts. Parse Ruby source into a versioned model, generate public API Markdown, and lint documentation from files, directories, or standard input without installing Rigor.

### Added

- Parse Ruby source into `Zard::Model::V1` declarations with documentation, contracts, diagnostics, and source provenance.
- Preserve plain RBS and `@extrbs` contract payloads and InlineRBS contract notes separately from API documentation.
- Support class, module, constant, attribute, and method documentation, including aliases, module functions, literal method-definition calls, and Ruby refinements.
- Model literal container builders such as `Data.define`, `Struct.new`, `Class.new`, `Module.new`, and `DelegateClass`, with generated attributes and block members.
- Preserve explicit superclass, mixin, singleton receiver, and refinement target expressions without resolving runtime ancestry or object identity.
- Apply supported visibility, removal, reassignment, and redefinition operations within the modeled source scope.
- Render documented public declarations as Markdown with parameter, return, block, option, exception, note, reference, deprecation, and example tags, including multiline descriptions.
- Lint noncanonical or YARD-like documentation syntax, empty descriptions, UTF-8 requirements, and Ruby syntax errors, with an option to fail on warnings.
- Provide `zard-doc render` and `zard-doc lint` for files, recursive directories, and standard input, with deterministic path ordering and no partial Markdown on input errors.
- Distribute `zard` and `zard-doc` as separate gems for Ruby 3.2 and newer, with a usage guide and a complete multi-file example.

[Unreleased]: https://github.com/rigortype/zard/compare/v0.0.2...HEAD
[0.0.2]: https://github.com/rigortype/zard/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/rigortype/zard/tree/v0.0.1
