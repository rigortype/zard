# JSON API documentation export

Repository builds support an experimental static-site producer:

```sh
zard-doc build --config zard-doc.yml --format json > api.json
```

This is ZARD documentation data, not a Rigor lens result. Generation does not execute Ruby source, parse contract types, infer signatures, or require Rigor. A future optional lens adapter can associate facts with source declarations without replacing their documentation or provenance.

## Invocation and publication

The existing build configuration, source selection, explicit documentation scopes, dependency closure and `--layout` / `--scope` options apply. `--format markdown` remains the default and retains its managed-page behavior.

JSON exports the selected scopes and their recursive documentation dependencies as one document to stdout, after validation. It does not read a previous generation manifest or create, edit or remove anything under `docroot`. The export is self-contained for those selected scopes; it does not merge a previous partial export. Consumers own their output publication. Shell redirection itself can truncate an existing destination before ZARD runs; callers that publish artifacts should write a temporary file and replace the artifact only after success.

Source errors return 1; invalid configuration or invocation, unreadable inputs, output-path collisions and serialization errors return 2. Neither emits partial JSON. Warnings permit export and also appear on stderr. A process or stdout I/O failure can leave truncated output, so consumers must check both exit status and JSON parsing before accepting an artifact.

## Envelope

| Field | Meaning |
| --- | --- |
| `schema` | Exactly `zard-doc/v0`. |
| `revision` | Integer `1` for this experimental representation. |
| `producer` | `zard` and `zard_doc` gem versions. |
| `layout` | `namespace` or `file`. |
| `scopes` | Selected documentation scopes, ordered by name. |
| `links` | Resolved documentation links grouped by source page path, with target `path` and `anchor`. |
| `warnings` | Reference-resolution warning strings, including ambiguous candidates; diagnostic prose is not a machine-readable enum. |

Consumers should reject unsupported schema/revision pairs. This format is experimental; a breaking change increments the revision before any stable schema commitment. It has its own lifecycle, independent of `lens/v0`, `lens/v1` and the `rigor:v1` type grammar revision. No generation timestamp, absolute configuration path or inferred fact is added. Repeated exports of identical inputs with the same producer versions are byte-identical.

## Documentation scopes and pages

Each scope has `name`, `destination`, its explicit direct documentation dependency names in `references`, `files`, `declarations`, and `pages`.

Each page has a `path` and an ordered array of declaration `id` values. Reopened classes/modules share a namespace page while retaining distinct source declarations. Namespace pages can exist for members of an undocumented container. Top-level declarations use the existing `_top-level.md` assignment. File organization uses source mappings and prefixes. Page paths are logical paths relative to `docroot`, with Markdown extensions, not a promise of emitted Markdown files or final website URLs. Website consumers map these paths to their routes.

The site can derive scope landing pages and navigation from this metadata. Generated Markdown index pages are not included in `pages` because they own no declarations. A file without public declarations produces no page.

JSON exports all public declarations, including those without API prose, so a site can present the selected API surface before documentation is complete. Private/protected declarations remain available to internal reference lookup but are not exported or linked. The Markdown format continues to publish only documented public declarations. This publication distinction is intentional and is not an inference that a Ruby-public declaration is a stable supported product API.

## Declarations

| Fields | Meaning |
| --- | --- |
| `id`, `page`, `anchor` | Scope-specific identity and logical page destination; `id` combines the documentation scope with the existing stable anchor. |
| `kind`, `name`, `namespace`, `display_name`, `visibility` | Original declaration kind/name, lexical namespace, display/reference name and visibility. |
| `parameters` | Existing source parameter labels, not a structured typed signature. |
| `references` | Names by which this declaration participates in documentation reference lookup. |
| `span`, `comment_span` | Declaration and attached comment provenance. |
| `documentation` | Original tag data plus resolved Markdown descriptions. |
| `contracts` | Unparsed contract channels, payloads, notes and provenance. |
| `receiver`, `refinement`, `superclass`, `container_builder` | Written source expressions with their corresponding `*_span` fields. |
| `alias_target` | Recorded alias target, without copying the target's documentation. |
| `mixins` | Written mixin `kind`, `target` and `span`. |

Absent optional fields are `null`; arrays remain arrays. A repeated method definition has its own identity/anchor. Nothing chooses a runtime-winning definition, resolves dynamic receivers, or asserts effective ancestry. Attribute accessors remain a source declaration with multiple reference names, rather than separate inferred getter/setter signatures.

Documentation entries carry `name`, `owner`, `subject`, optional `claim`, `description`, `raw`, and `span`, matching the source model. `rendered_description` contains Markdown with resolvable ZARD references linked, using the same resolution rules as a documentation build. Original descriptions remain unchanged. Examples, raw text and inline/fenced code preserve literal reference syntax. Consumers must use their normal safe Markdown rendering policy; strings in JSON are not trusted HTML.

Contract entries carry `channel`, `payload`, `note`, `raw`, and `span`. They are source text, not parsed or validated types. A documentation claim does not become a contract, signature or Rigor fact.

## Source provenance and diagnostics

Each selected source file has `path`, its full SHA-256 `digest` over the bytes parsed, and structured parser `diagnostics` with `code`, `severity`, `message` and `span`. Files without public declarations remain listed for provenance and diagnostics.

All generated source paths are relative to the real directory containing the build configuration. Explicit source roots outside that directory can produce `../` paths; these are source identifiers, not output destinations. No absolute checkout paths are generated in provenance or reference warnings. Source-authored prose and raw text are preserved, including any paths the author wrote.

Spans retain the model's 1-based lines, 0-based columns and byte offsets, including an exclusive `end_offset`. Digests cover the entire source file, including documentation comments. Neither the digest nor a declaration ID proves the semantic inputs of a future Rigor analysis are unchanged.

Reference lookup searches the current documentation scope, then only its explicit direct documentation dependencies. Transitive dependencies are generated without becoming visible to lookup. Ambiguous references remain literal with warnings. The `links` entries target actual exported pages/anchors and provide route mapping input without requiring consumers to reverse-engineer references from text.
