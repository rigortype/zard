---
status: accepted
---

# Separate documentation scopes from page organization

Monorepos need separate application documentation even when applications share Ruby namespace names. Applications have separate documentation scopes by default. Each scope is named and explicitly configured; directory conventions and gemspecs do not automatically establish scope boundaries. Multiple source trees assigned to one scope aggregate together. A shared documentation root accommodates hierarchical output, while page organization can use source files or Ruby namespaces; a CLI option overrides the page organization selected in the configuration file. Contracts and Rigor facts must retain their association with declarations independently of page organization.

Source files without publishable declarations produce no API page. In namespace organization, documented top-level methods and constants appear on a dedicated top-level page. Script explanations and execution instructions belong in separate guides.

References first resolve within their own scope. If no local target is found, lookup searches explicitly configured documentation dependencies. Sharing Ruby namespace names does not implicitly enable references between scopes.

Each source mapping selects files using include and exclude globs relative to its source root, independently of Git tracking and gemspec contents. Namespace organization is the default; file organization remains selectable. Both modes resolve references against all selected files in their scope.

Shared source files may belong to multiple scopes, with separate scope-specific declaration identities. Within one scope, overlapping inputs parse the same physical source file once. Ambiguous local references do not fall back to dependencies; ambiguous dependency references do not select the first match. Ambiguous references remain literal and produce warnings identifying candidate scopes and source locations.

Generation validates all selected scopes before updating output. Parse errors, unreadable inputs, and output collisions prevent publication of the entire selected output set; warnings alone permit generation. Filesystem publication failures use the recovery policy below.

## Configuration

Use YAML with `docroot`, `layout`, and named `scopes`. Each scope defines a `destination`, explicit `references`, and `sources` containing a `root` with include and exclude globs. Paths are relative to the configuration file. Source mappings may define an output prefix to distinguish source trees in file organization. CLI options override configured page organization and select scopes to generate.

```yaml
docroot: docs/api
layout: namespace
scopes:
  rigor:
    destination: rigor
    sources:
      - root: lib
        include: ["**/*.rb"]
      - root: plugins
        include: ["*/lib/**/*.rb"]
  playground:
    destination: playground
    references: [rigor]
    sources:
      - root: apps/rigor-playground/lib
        include: ["**/*.rb"]
```

## Aggregation and initial delivery

Reopened classes and modules share one namespace page, retaining descriptions, contracts, and provenance from each definition rather than replacing one description with another. Repeated method definitions remain separately represented; no runtime winner is inferred, and references to multiple competing method definitions are ambiguous. A namespace reference identifies the aggregate namespace page.

The initial implementation covers configuration, declaration aggregation, page organization, and cross-scope links using the existing parse model. External RBS ingestion and Rigor lens integration require separate specifications. Existing contract payloads retain their association with source declarations; this work does not introduce contract text rendering or type inference.

## Generated output ownership

A generation manifest records ZARD-managed pages. Regeneration removes obsolete managed pages while preserving unowned files, including handwritten guides. If a managed page has been edited since generation, publication stops before overwriting or deleting it. Output is prepared in a staging area; publication failures trigger recovery attempts. Failed recovery produces a non-success exit and actionable recovery information. This does not promise an atomic filesystem transaction across all pages.

## CLI and dependency generation

Add `zard-doc build --config zard-doc.yml`; retain the existing `render PATH...` combined Markdown stream and existing APIs. Configuration is explicitly selected. Without `--scope`, build all configured scopes; repeated `--scope` selects named scopes. `--layout namespace|file` overrides the configured layout.

```sh
zard-doc build --config zard-doc.yml
zard-doc build --config zard-doc.yml --scope playground --layout file
```

Build selected scopes together with their recursive documentation dependency closure so generated links have destinations. Reference lookup still searches only the current scope and its directly declared dependencies; transitive generation does not expand lookup visibility. Dependency cycles are allowed, and each scope is generated once.

## Path validation and navigation

Missing source roots, unknown documentation dependencies, scopes selecting no Ruby files, and conflicting output paths are errors before publication. Output destinations must stay within `docroot`. Input symlinks must not lead outside explicitly declared input roots. Within one scope, repeated inclusion of one physical file is deduplicated when the output assignment agrees, but conflicting output assignments are errors.

Generate `docroot/index.md` listing scopes and a scope-local `index.md` listing its pages. In namespace organization, publishable top-level declarations use `_top-level.md` within their scope. Links use relative output paths and stable anchors. Collisions between API pages and reserved navigation paths are errors.

## Acceptance scenarios

- Generate two applications defining the same namespace without mixing declarations or links.
- Aggregate multiple source trees and reopened namespaces within one scope while preserving all definition provenance.
- Generate namespace and file layouts from the same selected declarations; CLI layout overrides configuration.
- Honor include and exclude globs independently of Git and gem packaging.
- Include shared source in separate scopes without cross-scope identity leakage; deduplicate identical assignments within one scope.
- Resolve local references before direct documentation dependencies; preserve and warn on ambiguous targets.
- Generate selected scopes and recursive dependency closure, including cycles, without making transitive dependencies visible to reference lookup.
- Omit API pages for files without publishable declarations and place top-level declarations in the dedicated namespace-layout page.
- Reject invalid roots, dependencies, empty source selections, escaped paths, and output collisions before changing output.
- Generate relative links and navigation pages; reject collisions with reserved paths.
- Remove obsolete managed pages, preserve handwritten guides, and reject overwriting edited managed pages.
- Preserve existing output when pre-publication validation fails; exercise publication failure recovery and report unrecovered failures.
- Preserve existing parse, render, lint, and format behavior outside the new build workflow.

The initial file-oriented example maps `app/foo/hoge/fuga.rb` to `docs/api/foo/hoge/fuga.md` and `ext/foo-bar/hoge/fuga_foo.rb` to `docs/api/foo-bar/hoge/fuga_foo.md`. It illustrates file organization, rather than requiring that hierarchy for namespace organization. External contract and fact ingestion is deferred to a separate design.
