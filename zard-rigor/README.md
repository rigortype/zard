# zard-rigor

Optional, experimental adapter from the **released Rigor 0.4.3 CLI** to
`zard-doc/v0` revision 1. It accepts only `lens/v0` revision 1; this is not
the future stable lens protocol. Neither `zard` nor `zard-doc` loads Rigor.

This gem is not yet published. Use the monorepo's path gems or build the
packages with `bundle exec rake build build_doc build_rigor`.
Install `zard-rigor` alongside `zard-doc`, and install `rigortype` 0.4.3 in
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
The Ruby entry point is `Zard::Rigor::Lens#enrich(export, base:)`, with the
same `root:`, `config:`, `command:` and `workers:` constructor options.

The adapter invokes one batch process from the explicit project root. It
checks the ZARD SHA-256 snapshots, Rigor XXH3 digests, byte spans, target
order, exit status and fact references, and rereads selected sources after
analysis. Transport failure produces no JSON export. Partial target failures
remain unavailable bindings with warnings. No types are parsed, combined or
inferred here. Unavailable and dynamic slots retain the producer's reasons.

The optional top-level `lens` extension preserves producer/context/capability
metadata and separates source `sites`, shared `members`, and ZARD `bindings`.
Bindings match exact path, byte span, declaration kind, owner, scope and name;
unsupported aliases/refinements never fall back to name-only matching. Site
keys are document-local, not public identities or anchors. Only facts needed
by public declarations are retained, including other definition sites supporting
a public member. Visibility and runtime winners are never guessed.

`inputs` is not a complete dependency graph. Regenerate for each publication
from the intended clean checkout and tool environment; do not reuse an enriched
export solely because its selected Ruby files still match. Configure timeouts
in the calling build job. This adapter adds no persistent cache.

`zard-doc-astro` owns the HTML presentation. It shows member signatures and
definition body returns separately, escaping Rigor's display text verbatim.
Consumer applications own all CSS. Revision 1 does not provide type-reference
links, plugin-synthesized members, constant types, or the reserved `@extrbs`
semantics. Missing capabilities and omissions are not empty type sets.

The shared fixture is attributed in `test/fixtures/rigor_lens/README.md`.
Set `ZARD_RIGOR_COMMAND` to an executable for the opt-in released-CLI test.
