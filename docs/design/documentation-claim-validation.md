# Documentation claim validation: consumer integration

Status: **producer contract accepted; runtime capability not implemented or released.** [Rigor PR #2779](https://github.com/rigortype/rigor/pull/2779) ratified the contract at `fc8a97f10cb4c39abecbf344a19f26396d8a4835`. This document replaces the earlier Zard proposal with a consumer handoff. The binding definitions are the [pinned lens-claims specification](https://github.com/rigortype/rigor/blob/fc8a97f10cb4c39abecbf344a19f26396d8a4835/docs/internal-spec/lens-claims.md) and [ADR-113 amendment](https://github.com/rigortype/rigor/blob/fc8a97f10cb4c39abecbf344a19f26396d8a4835/docs/adr/113-rigor-lens.md#amendment-2026-11-04--documentation-claim-checking-as-agreed-with-zard-in-2737). Those sources take precedence over this integration summary.

Zard #5 remains gated on a released producer advertising `claims` and passing real CLI conformance fixtures. The current adapter still accepts Rigor 0.4.5 and `lens/v0` revision 1; this documentation change neither enables checking nor changes its allowlist. The separation in [ADR 0001](../adr/0001-contract-and-documentation-channels.md) and [ADR 0003](../adr/0003-package-boundaries-and-rigor-lens.md) remains: ZARD owns documentation syntax and attachment, Rigor owns type grammar, resolution and proofs.

## One lens call

The accepted invocation is:

```text
rigor lens --format json --claims REQUEST [--config FILE] [--workers N] FILE...
```

The adapter already holds the parsed export and source snapshots before invoking lens. It can extract claims into one request without a preflight run. The request locates a declaration by its own `{kind, owner, scope, name, span}`; Rigor binds it to a same-session site when the named member lists that site. The response's `site` is that site's lens key, not an identity to persist across runs. Never fall back to a neighboring declaration or a name-only match.

The enclosing lens document retains its context, target statuses/digests, inputs, completeness, omissions, members and exit rules. It gains capability `claims` and a `claims` field, null when no request is supplied. With the same targets, every field other than `claims` must equal the document without claim checking. Claims must not enter inference, signatures, diagnostics, caches or the incremental snapshot.

`--claims` requires JSON output. Claim verdicts never change the lens exit status: `0` means at least one target is `ok`, `1` means none is. Request-level integrity/usage errors are `64` with no document; whole-run crash handling is unchanged. An unsuccessful target produces per-claim `unavailable` results inside an otherwise valid lens document.

## Request and response integration

The request is `lens-claims-request/v0`, the response section is `lens-claims/v0`, and both use **revision 1, versioned together** independently of `lens/v0`. A breaking change to either increments their shared revision. The grammar identifier is exactly `rbs`, not the adapter's existing `rigor:v1` metadata.

An illustrative request, with placeholder source offsets/digest:

```json
{
  "schema": "lens-claims-request/v0",
  "revision": 1,
  "grammar": "rbs",
  "files": [{"path": "lib/widget.rb", "digest": "xxh3-64:0123456789abcdef"}],
  "claims": [{
    "id": "widget-result:tag-0",
    "file": "lib/widget.rb",
    "declaration": {
      "kind": "method", "owner": "Widget", "scope": "instance", "name": "result",
      "span": {"start_offset": 80, "end_offset": 110}
    },
    "tag": {"name": "return", "subject": null, "span": {"start_offset": 40, "end_offset": 79}},
    "claim": "::String"
  }]
}
```

The type payload is the claim row's top-level `claim` string, without brackets. The adapter retains tag attachment and its own documentation scope/id mapping; Rigor checks span bounds and declaration binding, not whether the tag documents the right declaration. Spans are zero-based, end-exclusive byte offsets. Each file appears once, is root-relative, and must name an invocation target; duplicate target arguments refer claims to the first target row. The adapter's existing SHA-256 export check remains separate from the wire's XXH3 source digest.

An illustrative `claims` response section for that request:

```json
{
  "schema": "lens-claims/v0",
  "revision": 1,
  "request_digest": "xxh3-64:fedcba9876543210",
  "grammar": "rbs",
  "capabilities": ["return", "required_param", "required_keyword"],
  "results": [{
    "id": "widget-result:tag-0",
    "verdict": "conflict",
    "reason": "proven_disjoint_arm",
    "relation": "documentation_coverage",
    "direction": "contract_within_claim",
    "site": "lib/widget.rb:80-110:0",
    "member": {"owner": "Widget", "scope": "instance", "name": "result"},
    "slot": {"kind": "return"},
    "contract": {"type": "::Integer", "provenance": "sig", "path": "sig/widget.rbs"},
    "evidence": [{"rule": "unrelated_classes", "arm": "::Integer", "against": "::String"}]
  }]
}
```

These are protocol examples, not executable fixtures or observed types of repository code. Validate `request_digest` as XXH3-64 over the exact request bytes before accepting any result. Require exactly one result per requested id in request order. Recheck source snapshots after the process and bind each non-null `site`, `member` and `slot` to the same lens document and original tag.

For a parameter, `slot` is `{kind: "param", name, param_kind, index}`, using lens parameter kinds and the zero-based index in the contract overload's `params`. For a return it is `{kind: "return"}`. `contract` is `{type, provenance, path}`. `relation` and `direction` are null when no slot resolved; `site`, `member`, `slot` and `contract` are null when their respective binding/evidence is absent. `evidence` is an array of `{rule, arm, against}`, empty for undecided/invalid/unavailable results. Display types explain the producer's verdict; the adapter must not recompute it from those strings.

## Verdicts and diagnostics

| Verdict | Reason | Consumer meaning |
| --- | --- | --- |
| `compatible` | `proven_inclusion` | The authored contract supports the claim under the specified proof scope. |
| `conflict` | `proven_disjoint_arm` | Emit a mismatch on the original tag with producer evidence. |
| `unknown` | An ordered reason below | Target analysed, but no semantic decision; show the reason. |
| `invalid_claim` | `syntax_error` | Both supported parsing paths reject the claim text; separate from mismatch. |
| `unavailable` | Target status: `not_found`, `not_ruby`, `outside_project`, `parse_error` or `failed` | Target has no analysis; no semantic answer. |

For an `ok` target, `invalid_claim` takes precedence over every unknown reason. Otherwise Rigor checks these unknown reasons in this exact order and returns the first applicable one:

1. `no_such_declaration`
2. `unsupported_declaration`
3. `declaration_mismatch`
4. `unsupported_subject`
5. `no_authored_contract`
6. `unsupported_contract_source`
7. `extrbs_contract`
8. `refined_contract`
9. `unsupported_overloads`
10. `no_such_parameter`
11. `unsupported_parameter_kind`
12. `unmatched_parameter`
13. `unsupported_grammar_feature`
14. `unresolved_name`
15. `ambiguous_name`
16. `dynamic_type`
17. `unsupported_type`
18. `unproven`

The pinned specification defines each condition. Relation computation happens only after the earlier checks; `unproven` is its undecided outcome. An unrecognized reason code must be treated as unknown with no inferred meaning.

A valid in-file span with no declaration is `unknown/no_such_declaration`, not an integrity error. A site under another member identity is `unknown/declaration_mismatch`; non-method/shared-span sites and omissions are `unknown/unsupported_declaration`. Request faults instead produce exit 64: unreadable/malformed/unsupported requests, missing required fields, duplicate ids/files, a claim file absent from the file list, a file absent from invocation targets, stale readable-file digests, or out-of-bounds declaration/tag spans. Unreadable targets such as `not_found` remain unavailable. Rigor validates requests before analysis; source changes during analysis also invalidate the digest. Revision 1 ignores undefined request fields.

## Proof scope and presentation

`documentation_coverage` is directional: parameters require `C ⊆ F` (`claim_within_contract`), returns require `F ⊆ C` (`contract_within_claim`), where `C` is the claim and `F` the authored slot. Every subset-side union arm must be included for compatible. An inhabited subset-side arm proved disjoint from the entire other side establishes conflict. Failed inclusion and overlap alone establish neither.

Revision 1 reads one authored overload after Rigor's `sig/` and inline merge, with `sig` or `inline` slot provenance. It checks returns and required positional/keyword parameters. Positional subjects map through the site's Ruby name, then aligned positional kinds/indexes; RBS positional names do not control the match. Required keywords match by name and `keyreq` kind. Library/plugin/inferred slots, extra overloads, unsupported subjects, `@extrbs` and authored refinements remain unknown.

Canonical payloads are RBS type expressions; there is no implicit YARD translation. Rigor expands non-generic aliases and owns name resolution. Text rejected as RBS but accepted by Rigor's refinement grammar is `unsupported_grammar_feature`; only text both reject is `invalid_claim`. A parsed but ill-formed type, such as an unknown name or wrong type-argument count, is not invalid syntax in revision 1. Nested `untyped` is `dynamic_type`; unsupported forms and generic aliases are `unsupported_type`. Exact type equality, including normalized union arguments, may prove inclusion; generic variance is not inferred by the adapter.

Project-authored ancestry may prove inclusion. Conflict disjointness trusts only the producer's core/stdlib class and literal fragment, never project/gem classes or modules. Relative claim names must agree between RBS resolution and Ruby lookup over the configured project index; a visible Ruby-only shadow gives `ambiguous_name`. Agreement can prove compatible for the classes Rigor sees, but unread files or runtime namespace changes can still change Ruby's lookup. **Never present relative-name compatible as proof against the running program.**

Relative names contribute to conflict only for a top-level `def` outside every class/module body (owner `Object`). Inside a project class or even a reopened core class, a conflict needs an absolute claim spelling such as `::Integer`; the corresponding relative claim can remain `unknown/unproven`. For example, a `String` return documented as `"hello"` is overlap-only and unproven. The accepted spec's conformance fixtures cover these distinctions; the adapter consumes their verdicts without implementing the proof engine.

Counts are derived after validating exhaustive results: compatible and conflict are decided, unknown is unchecked, invalid and unavailable remain separate. An optional decided ratio states that all requested claims form its denominator; zero claims means “no claims,” never 100% checked. A missing capability or failed protocol validation is unavailable validation, not a zero-result success. Neither compatible nor conflict changes the authoritative contract or asserts a runtime observation.

## Implementation and release handoff

1. Rigor implements the accepted contract and checks in real isolated CLI fixtures, including every reason, both directions, relative-name guards, integrity failures and equality of the surrounding lens document with/without claims. The pinned spec owns this producer acceptance gate.
2. Verify a released producer that advertises lens capability `claims`, the jointly versioned request/response revision, `rbs` grammar and supported subject capabilities. A ratified ADR or development checkout is insufficient to enable Zard's mismatch diagnostics.
3. Extend `zard-rigor`'s existing lens invocation with claim extraction and strict request/response validation, then attach results to original tags and derive coverage counts. Pin the producer fixtures and add real released-CLI integration evidence before changing compatibility declarations.
4. Expose mismatch, invalid, unknown and unavailable states in the documentation check surface. Preserve useful documentation generation without Rigor. Keep core free of type parsing/comparison and analyzer internals.

The wire contract is settled; implementation and a verified release are the outstanding dependencies. This handoff does not claim runtime completion of Zard #5.
