# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.1] - 2026-10-08

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

[Unreleased]: https://github.com/rigortype/zard/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/rigortype/zard/tree/v0.0.1
