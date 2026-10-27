# zard-rigor

Optional, experimental adapter from the **released Rigor 0.4.5 CLI** to
`zard-doc/v0` revisions 1 and 2. It accepts only `lens/v0` revision 1; this is not
the future stable lens protocol. Neither `zard` nor `zard-doc` loads Rigor.

Version 0.0.2 is the first release of this optional gem. Add `gem "zard-rigor", "~> 0.0.2"` to your Gemfile alongside `zard-doc`.
It depends on `rbs ~> 4.0` to read signature text; RBS 4.2 alone would exclude Ruby 3.2.
Install `zard-rigor` alongside `zard-doc`, and install `rigortype` 0.4.5 in
the environment used by the executable. Projects using `rigor-rbs-inline`
also need `rbs-inline` (the shared fixture uses 0.14.0). The child process
runs outside the caller's Bundler environment, so its executable must have
access to its own dependencies. A wrapper executable can select that environment.

```sh
zard-doc build --config zard-doc.yml --format json \
  --lens-root /path/to/project --lens-config .rigor.dist.yml \
  --rigor-command /path/to/rigor
```

`--lens-config` is optional and relative to the lens root. Without it,
Rigor selects its normal configuration. `--lens-workers` defaults to 4.
The Ruby entry point is `Zard::Rigor::Lens#enrich(export, base:, resolve_constant: nil)`,
with the same `root:`, `config:`, `command:` and `workers:` constructor options.
`zard-doc build` passes `resolve_constant`; without it, signatures stay literal
and bindings carry no type-reference fields.

The adapter invokes one batch process from the explicit project root. It
checks the ZARD SHA-256 snapshots, Rigor XXH3 digests, byte spans, target
order, exit status and fact references, and rereads selected sources after
analysis. Transport failure produces no JSON export. Partial target failures
remain unavailable bindings with warnings. No types are combined or inferred
here, and type text is read only to locate named types (below). Unavailable and
dynamic slots retain the producer's reasons.

The optional top-level `lens` extension preserves producer/context/capability
metadata and separates source `sites`, shared `members`, and ZARD `bindings`.
Bindings match exact path, byte span, declaration kind, owner, scope and name;
aliases match their recorded target and refinements remain unavailable, without name-only fallback. Site
keys are document-local, not public identities or anchors. Only facts needed
by public declarations are retained, including other definition sites supporting
a public member. Visibility and runtime winners are never guessed.

`inputs` is not a complete dependency graph. Regenerate for each publication
from the intended clean checkout and tool environment; do not reuse an enriched
export solely because its selected Ruby files still match. Configure timeouts
in the calling build job. This adapter adds no persistent cache.

`zard-doc-astro` owns the HTML presentation. It shows member signatures and
definition body returns separately, escaping Rigor's display text verbatim.
Consumer applications own all CSS. Revision 1 does not provide
plugin-synthesized members or the reserved `@extrbs` semantics. Missing capabilities and omissions are not empty type sets.
Rigor 0.4.5 supplies constant value slots and alias/module-function sites. The
adapter preserves these facts; a module function's public singleton binding
does not expose its private instance signature or relabel its body return.
Only Rigor 0.4.5 is supported; regenerate older exports with that executable.
Unavailable bindings carry explicit reasons for unsupported constructs or
capabilities, target failures, ambiguous sites and unmatched declarations.
Producer omission explanations are attached only after exact byte-span/name
matching. Page coverage summaries distinguish these gaps from dynamic types.

The shared fixture is attributed in `test/fixtures/rigor_lens/README.md`.
Set `ZARD_RIGOR_COMMAND` to an executable for the opt-in released-CLI test.

## Signature type references

Each binding gains additive `type_references` and `type_reference_diagnostics`
when built through `zard-doc build`. The adapter parses each overload's `rbs`
text with the `rbs` gem (`~> 4.0`) and visits class, singleton and interface
type nodes, including nested generics, unions, tuples, records, blocks and
method type parameter bounds. Type variables, literals, aliases and built-in
syntax (`self`, `void`, `bool`, `untyped` …) are never references. Text that
does not parse, or does not have a single overload, keeps its literal spelling
and adds a diagnostic.

Rigor 0.4.5 spells contract signatures from resolved RBS definitions, so every
class and interface name there is absolute (`::App::Foo`); a relative name is a
type variable, such as a class's `T`, and is skipped. An inferred return
(`provenance: inferred`) is spelled with the full constant path without a
leading `::` (`App::Foo`) and is read as absolute. Lexical lookup is therefore
Rigor's, not the adapter's. Only the documentation scope is decided here, by
zard-doc's constant lookup: the binding's own scope first, then its explicitly
declared direct documentation dependencies. Transitive dependencies and
unrelated scopes that share Ruby names are never searched, and a local
candidate, even one excluded from publication, stops the search. Several
definitions of one class or module are a single type, represented by its first
published definition in source path order; it shares the aggregate page in
namespace layout.

| Field | Meaning |
| --- | --- |
| `member_key`, `overload` | The bound member and zero-based overload whose `rbs` text holds the name. |
| `name` | The exact spelling; `start_offset`/`end_offset` are its UTF-8 byte range in that text. |
| `status` | `resolved`, `ambiguous` or `unresolved`. |
| `candidates` | Every declaration found: `{scope, span: {path, start_line, end_line}}`. |
| `targets` | The linkable candidates: `{scope, declaration_id, path, anchor, span}`. |
| `reason` | For `unresolved` only: `missing`, `unpublished` or `not_class_or_module`. |

`resolved` has exactly one candidate, which is a published class, module, or
constant assigned from a container builder such as `Data.define`. `ambiguous`
has two or more candidates and is never linked; its targets list only the
published ones. `unresolved` has no targets: `missing` means no visible scope
declares the name, as for core and gem types, and is not reported; the other
reasons have one candidate and a diagnostic. Diagnostics name the binding's
scope, member and overload, and each candidate as `scope:path:line`; they are
also appended to `lens.warnings`. Consumers that ignore these fields keep
rendering signatures literally.

## Updating supported releases

`lib/zard/rigor/compatibility.json` is the authoritative producer/schema allowlist and declares the supported
`rigor:v1` type grammar. The adapter copies this value to `lens.adapter.grammar`;
the Astro consumer requires an exact match before rendering enriched exports.
Missing or unsupported grammar values fail validation without parsing type text.
`default_version` selects the released executable tested in CI. Versions are
explicitly reviewed; sharing a schema revision does not automatically admit an
untested producer. After verifying a new released executable with the shared
fixture and real project, replace the supported version and default, then run
`node scripts/sync-lens-compatibility.mjs` from the repository root. The Astro
package ships the generated manifest and tests/packing reject a stale copy.
Its notice renders the validated producer version from the actual artifact.
