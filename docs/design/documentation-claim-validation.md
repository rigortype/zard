# Documentation claim validation through Rigor

Status: proposal for Zard #5. The command, schemas, and semantic proof capability below are unimplemented. This document does not change the accepted ADRs or authorize a release.

This revision incorporates the [Rigor-side feedback on #2737](https://github.com/rigortype/rigor/issues/2737#issuecomment-6614160242). That feedback explicitly awaits owner ratification through a Rigor ADR; neither it nor this document establishes an accepted API. Runtime implementation of Zard #5 waits for an agreed producer contract and a tested release carrying that capability.

ZARD permits an optional type claim in API documentation without making it a contract. This proposal lets Rigor check whether the authoritative method contract supports that claim, while preserving the separation required by [ADR 0001](../adr/0001-contract-and-documentation-channels.md) and [ADR 0003](../adr/0003-package-boundaries-and-rigor-lens.md).

## Existing boundary and missing capability

The core already preserves each documentation tag's name, subject, option owner, claim text, raw text, and source span. The optional `zard-rigor` adapter invokes the external Rigor CLI and binds declarations by source identity and exact byte spans. It accepts released Rigor 0.4.5 and `lens/v0` revision 1.

That lens supplies rendered types and provenance, not semantic comparison results. Its inferred types erase refinements; `@extrbs` semantics and inferred refinements are outside revision 1. Equal strings therefore cannot establish semantic agreement, and unequal strings cannot establish conflict. Parsing their RBS syntax does not add the missing subtype, alias, inheritance, or refinement semantics. See the [version-pinned lens contract](https://github.com/rigortype/rigor/blob/56cbfce60d27f7455f441728e8494ee79c74ab72/docs/internal-spec/lens.md) and [released capability list](https://github.com/rigortype/rigor/blob/56cbfce60d27f7455f441728e8494ee79c74ab72/lib/rigor/lens.rb).

`assert_type` is also unsuitable: it checks the engine's short display text, not subtype compatibility. Rigor already has a conservative contradiction diagnostic for certain signature collisions, but it does not expose a general public claim proof API. See [inspecting types](https://github.com/rigortype/rigor/blob/56cbfce60d27f7455f441728e8494ee79c74ab72/docs/manual/05-inspecting-types.md) and [the diagnostic catalogue](https://github.com/rigortype/rigor/blob/56cbfce60d27f7455f441728e8494ee79c74ab72/docs/manual/04-diagnostics.md).

## Ownership

- `zard` recognizes documentation syntax and preserves claims and provenance. It does not parse type payloads or compare types.
- `zard-rigor` extracts claims, sends one batch request, validates the response and source snapshots, and attaches results to the original tags. It never loads Rigor analyzer classes, turns claims into signatures, or implements type relations.
- Rigor resolves declarations and authoritative contracts in its project environment, parses the claim grammar, performs semantic proofs, and emits verdicts and evidence references.
- Documentation consumers render the original claim and the producer's result. A claim does not replace a contract or inferred fact, including when validation succeeds.

## Meaning of the check

The initial check concerns the documented API promise against an authored contract. Let `C` be the documentation claim and `F` the authoritative contract slot. The proposed relation is named `documentation_coverage`: semantic subtype inclusion with its direction supplied by the tag. Its semantics need agreement from the Rigor owner before implementation:

| Tag | Required relation | Meaning |
| --- | --- | --- |
| `@param name [C]` | `C <: F` | Every input advertised as accepted is accepted by the contract. |
| `@return [C]` | `F <: C` | Every result the contract permits satisfies the documented promise. |

A narrower advertised parameter domain or a broader documented return domain is compatible under this rule. It does not check whether documentation exhaustively describes the contract. A conflict says that the contract does not support the documented promise, not that a runtime execution violated it. Claims cannot override the contract, and a narrower inferred body return cannot replace the authored return as the comparison basis.

The proposed first proof policy follows Rigor's feedback. Decompose the subset side (`C` for a parameter, `F` for a return) into union arms:

1. If every arm is proved included in the other side, return `compatible`.
2. Otherwise, if at least one inhabited arm is proved disjoint from the entire other side, return `conflict`.
3. Otherwise return `unknown`. A failed inclusion proof, partial overlap, or string inequality is not a conflict proof.

Inclusion may use authored ancestry of project classes. Conflict proofs are restricted to Rigor's trusted fragment of absolute core/stdlib classes and their literals, using the producer's ancestry checks and exclusions. Modules, project classes and gem classes cannot establish disjointness. Relative names resolve in the declaration's lexical nesting before this restriction is applied; a resolved project class can contribute to an inclusion proof, never a conflict proof. The adapter does not implement these rules or import the internal comparator. Rigor's gradual call-acceptance relation is not a substitute: its treatment of Dynamic does not satisfy this check's proof requirements.

Either side containing Dynamic anywhere, including nested `Array[untyped]`, or `void`, `self`, `instance`, `class`, type variables or interfaces yields `unknown` in the first slice. An arm that only overlaps provides neither inclusion nor disjointness evidence; another inhabited, trusted disjoint arm can still prove conflict unless an excluded type makes the comparison unknown.

These illustrative fixture inputs show the distinction; they are not observed types of repository code:

| Authored slot and claim | Expected result under the proposed proof policy |
| --- | --- |
| Parameter `::String`, claim `"hello"` | `compatible` when literal inclusion is proved. |
| Return `::String`, claim `Object` resolving to `::Object` | `compatible` when declared ancestry proves inclusion, despite different spelling. |
| Return `::String`, claim `"hello"` | `unknown`: overlap alone does not establish a trusted disjoint arm; the first slice makes no cardinality argument. |
| Return `::String \| ::Integer`, claim `::String` | `conflict` when the inhabited `::Integer` arm is proved disjoint from the claim. |
| Return project class `B`, claim project class `A`, authored `class B < A` | `compatible` if the authored relation is resolved and proved. Missing ancestry does not prove conflict. |
| Return `Array[untyped]`, claim `Array[String]` | `unknown`, including when an ordinary gradual call check would accept it. |

## Initial subject coverage

Start with `@param` and `@return` on an unambiguous method declaration with exactly one authored overload **after Rigor's own `sig/` and inline merge**: the contract call sites see. The first basis is `sig` or `inline` only. Library/gem contracts, plugin-supplied members and inferred facts yield `unknown`, even if their displayed types look usable.

Match required positional and required keyword parameters by Ruby name and kind. Unnamed RBS positions need a verified correspondence with the source definition. An undeclared or unresolvable parameter subject yields `unknown`, never a fallback to the first parameter.

Multiple overloads, argument/return correlations, unsupported generics, forwarded/destructured/optional/rest parameters, attributes, constants, yields, options, raises, unsupported declarations, ambiguous sites and contested members remain explicit `unknown` cases. Later coverage needs a producer policy and conformance fixtures; never pair overloads by array order or union their slots independently and lose correlations.

Dynamic and unavailable type evidence cannot establish either verdict. Inferred underapproximations cannot prove a universal promise; a future inferred-fact capability must define its approximation and proof guarantees. Failure to analyze a target is a separate availability state, not semantic `unknown` (below).

## Proposed lens integration

Use one existing lens session with an optional claims request:

```text
rigor lens FILE... --claims REQUEST.json --format json [--config FILE] [--workers N]
```

`--claims` and the schemas below are proposed and unimplemented. The adapter already holds the parsed ZARD export and source snapshots before invoking lens, so it can extract the request before this one batch call. No prior lens invocation, handshake or separate analysis process is needed. Rigor checks claims using that session's authoritative merged contracts and returns the same session's site keys.

Claims must never enter the signature environment or narrow inference. Ordinary diagnostics, contracts and inferred facts must be identical with claims added, changed or removed; only the new claim results differ.

The current directory remains the explicit lens project root. Reuse lens context, file statuses/digests, inputs, completeness and omissions, and its existing exit rules: `0` when at least one target is `ok`, `1` when none is, `64` for a usage error, and no document on a whole-run crash (existing fatal-error handling uses `70`). Per-target failures stay in-band. Claim verdicts do not change the lens exit status. Unsupported request schema or grammar revision is a usage error with no document, as proposed upstream. This design adds no new exit codes; detailed integrity-error reporting still needs producer agreement.

### Consumer positions

Canonical claim payloads use **RBS type-expression syntax**, not implicit YARD translation. ZARD supplies the payload as written; Rigor owns its grammar and any extended support. A first release that returns mostly `unknown` is useful because it distinguishes proven results from unchecked claims. Validated exhaustive per-claim results let the adapter calculate counts locally; the response does not need duplicate totals.

### Request, revision 1

```json
{
  "schema": "rigor-claims-request/v0",
  "revision": 1,
  "grammar": "rigor:v1",
  "files": [{"path": "lib/widget.rb", "digest": "xxh3-64:<16 lowercase hex>"}],
  "claims": [{
    "id": "app:widget-result:tag-0",
    "file": "lib/widget.rb",
    "declaration": {
      "span": {"start_offset": 80, "end_offset": 110},
      "kind": "method", "owner": "Widget", "scope": "instance", "name": "result"
    },
    "tag": {
      "span": {"start_offset": 40, "end_offset": 79},
      "name": "return", "subject": null, "owner": null,
      "claim": "String"
    }
  }]
}
```

The sample grammar label `rigor:v1` is illustrative, not an accepted request identifier or a promise of extended support. The exact grammar identifier and capability spelling await the producer ADR; the first semantic subset is plain RBS type expressions. The sample uses illustrative offsets, digest, and type text; it is not a runnable fixture or a statement about repository code. Spans count bytes in the exact file, are zero-based and end-exclusive, and contain no derived line/column identity. `id` is a caller-supplied opaque identifier unique within the request; it is not a stable Rigor symbol id. The adapter can retain its own scope and declaration/tag identifiers in that string or an external map. Duplicate Ruby names in independent documentation scopes must not merge claims.

The request uses the lens source-digest convention and covers the entire source, including prose. Existing ZARD SHA-256 export checks still guard the adapter's source snapshot. Rigor requires project-relative canonical paths, rejects duplicate file entries, duplicate claim ids, out-of-range spans, mismatched declaration identity and stale digests, and never attaches a claim to a neighboring declaration. For an `ok` target, a declaration outside the supported subject coverage yields `unknown`; a request whose supplied locator contradicts the declaration identity is an integrity error. An unanalysable target uses the separate target-availability result described below.

The adapter is responsible for extracting `tag.claim`, its tag span, and the tag's attachment to the declaration from the ZARD parser's exact source snapshot. Rigor validates the requested declaration identity, the tag span's file bounds, and parameter binding; it does not independently certify the ZARD parser's tag attachment or extraction. The adapter retains that association and checks it again when attaching the result. The request carries claim text as input, not an executable expression or an inline signature. Claims without a type payload are omitted.

### Site association without preflight

The request's source locator (file digest, declaration span, kind, owner, scope and name) is available from the parsed export. Rigor resolves it against sites generated in the same lens session and returns an authoritative `site_key`. The adapter verifies that key against the returned file/site and its own ZARD binding. No name-only or neighboring-site fallback is allowed.

The exact locator-to-site wire shape remains open for owner agreement. Requiring a prior lens `site_key` in the first request would introduce the preflight call this integration is intended to avoid; it is not a requirement of this proposal. Unsupported declarations may have an omission rather than a site, so their unknown result may have a null site key with an explicit reason.

### Proposed claims response section, revision 1

The following object is the new `claims` section inside the lens document, not a second top-level response. The parent lens document supplies producer identity, `context`, `files`, their digests/statuses/sites/inputs, and `members`. Its capabilities advertise claims plus supported grammar and subjects; exact capability spellings need producer agreement. The claims section and request each have a separate schema/revision independent of `lens/v0`.

```json
{
  "schema": "rigor-claims/v0",
  "revision": 1,
  "grammar": "rigor:v1",
  "request_digest": "sha256:<digest of the exact request bytes>",
  "results": [{
    "id": "app:widget-result:tag-0",
    "file": "lib/widget.rb",
    "site_key": "lib/widget.rb:80-110:0",
    "availability": "available",
    "relation": "documentation_coverage",
    "direction": "contract_subtype_of_claim",
    "verdict": "unknown",
    "reason": "unsupported_relation",
    "basis": null,
    "evidence": [],
    "message": "The producer cannot prove this relation."
  }]
}
```

Rigor computes `request_digest` over the exact UTF-8 request bytes. The adapter verifies it before accepting results, preventing an id reused with changed claim text from accepting an old response. Validate exactly one result for every requested id, in request order, the negotiated grammar, file references and source snapshots. Reuse the same lens context and input integrity machinery; do not copy those fields into a competing claims context. A context digest or unchanged `inputs` list is not a complete cache key.

Each available result names `documentation_coverage`, with direction `claim_subtype_of_contract` for parameters or `contract_subtype_of_claim` for returns; direction is null when no supported relation applies. `basis` is null when no authoritative slot was resolved. Otherwise it identifies the same-session member/site, authoritative single overload, slot, and `sig`/`inline` provenance. Evidence carries producer proof rules and source references, not serialized analyzer objects. Display text is explanatory only.

For example, fields on an available conflict result could be:

```json
{
  "availability": "available",
  "site_key": "lib/widget.rb:80-110:0",
  "verdict": "conflict",
  "reason": "proven_disjoint_arm",
  "basis": {
    "member": {"owner": "Widget", "scope": "instance", "name": "result"},
    "overload": 0,
    "slot": {"kind": "return", "parameter": null},
    "provenance": {
      "kind": "sig",
      "source": {"file": "sig/widget.rbs", "span": {"start_offset": 10, "end_offset": 35}}
    }
  },
  "evidence": [{
    "kind": "non_inclusion", "rule": "inhabited_trusted_disjoint_arm",
    "subset_arm_display": "::Integer", "other_side_display": "::String"
  }]
}
```

For a parameter, `slot.parameter` is `{name, kind, index}` using the producer's Ruby parameter vocabulary. The overload index cannot authorize selecting one of several overloads. Source references must be covered by the lens session's source/signature integrity records. Computed paths remain project-relative; there is no need to introduce external library proof provenance in the first authored-only basis. The adapter validates references, not the semantic proof.

| Available verdict | Required producer evidence | Consumer behavior |
| --- | --- | --- |
| `compatible` | Every subset-side arm is proved included, without a first-slice exclusion. | Show decided status; keep the authoritative contract. |
| `conflict` | An inhabited subset-side arm is proved disjoint in the trusted fragment, without a first-slice exclusion. | Emit a mismatch at the original tag span with its evidence. |
| `unknown` | Neither supported proof, or excluded grammar, subject, provenance or type evidence. | Show unchecked status/reason, not mismatch. |
| `invalid_claim` | Supported grammar conclusively rejects the payload's syntax or semantic well-formedness. | Emit invalid-claim diagnostics separately from mismatch. |

Suggested unknown reasons include `no_authored_contract`, `unsupported_provenance`, `dynamic_evidence`, `unavailable_evidence`, `contested_member`, `ambiguous_subject`, `unsupported_subject`, `unsupported_overloads`, `unsupported_correlation`, `unsupported_grammar_feature` and `unsupported_relation`. An unresolved type is unknown unless the supported grammar conclusively establishes invalidity.

### Target availability and integrity errors

A valid claims request may target a file that lens reports as `parse_error`, `failed`, `outside_project` or another unsuccessful status. Preserve that in-band target failure. Proposed per-claim fields are `availability: "target_unavailable"`, `verdict: null`, `site_key: null`, `basis: null`, empty evidence, and the file reference/reason; the authoritative failure remains on the lens file row. This availability shape is pending upstream agreement. It must not be interpreted as semantic unknown or a type mismatch, and it must not introduce a new exit status. The claims section should still account for each requested claim when lens can emit a valid document.

Malformed requests, unsupported request/schema/grammar revisions, stale digests, duplicate ids, invalid spans and contradictory source identities are protocol/integrity errors, not `invalid_claim`. Exact failure reporting for integrity errors beyond the proposed usage-error case needs producer ratification. A process crash or invalid/truncated document provides no accepted claim results. Do not accept partial claim results from an otherwise untrusted response.

After validating exhaustiveness and uniqueness, the adapter can count `compatible` and `conflict` as decided, `unknown` as unchecked, `invalid_claim` separately, and unavailable targets separately. An optional decided ratio uses all requested claims as its denominator and states that definition; zero claims displays “no claims,” not 100% checked. Missing capabilities or protocol failures are unavailable validation, never a zero-result success. No response totals are needed.

## Grammar and drift

Rigor owns RBS parsing, lexical name resolution, normalization, aliases, ancestry and proof policy. ZARD does not silently translate YARD spellings such as `Array<String>`, `Boolean` or `#to_s`; a name that also parses as RBS is resolved as that RBS name, not reinterpreted as a YARD shorthand. The precise request grammar identifier/revision and advertised subset await the producer ADR. Existing `rigor:v1` metadata does not imply full extended checking.

The first slice accepts plain RBS type expressions. A recognized valid Rigor-extended/refinement payload is `unknown` with `unsupported_grammar_feature`; an authored `@extrbs` contract is unknown until the producer supports it. Neither may silently fall back to erasure. A failed plain-RBS parse alone cannot establish that an unfamiliar extended payload is invalid. Rigor must distinguish conclusively invalid supported syntax from unsupported or unrecognized grammar conservatively; the adapter must not make that classification.

Use the lens session's drift checks for requested sources, consulted sources, signatures and context. Rigor verifies that analysis used the request's source snapshots; source or consulted input drift invalidates the affected evidence under the agreed integrity policy. The adapter rereads requested files after the subprocess and validates ids, request digest, same-session site keys, basis references and spans before accepting claim results. Stable tag bytes alone do not justify reuse after the project environment changes.

## Compatibility and release gate

The new request schema and lens `claims` section schema have independent revisions alongside `lens/v0`. They reuse the enclosing lens document rather than requiring another producer run. A breaking change increments their revision. A producer release advertises supported grammar revisions, subject coverage and proof capabilities; absent capability means unavailable, not successful validation. Zard must accept only explicitly tested released producer/schema/grammar combinations and preserve an explicit unavailable result when claim validation is not installed. Raw source-checkout engines need a separate development-only route, never an implicit release allowlist entry.

Before enabling mismatch diagnostics, release Rigor's implementation with real CLI conformance artifacts, then add the corresponding Zard adapter compatibility entry and transport integration tests. A shared schema revision is insufficient to admit a new producer version. Existing parsing and documentation generation must continue to work without Rigor.

## Acceptance matrix

Each producer fixture must execute the proposed CLI against a real isolated project and retain request, source/signature files, response, stderr, exit status, and assertions. Type spellings below are illustrative fixture inputs; expected verdicts require the released producer's semantic proof.

| Scenario | Required observable |
| --- | --- |
| Equal or included types with different resolved spelling | `compatible` when proved; never mismatch from spelling. |
| Narrower advertised parameter; broader documented return | Correct directional inclusion produces `compatible`. |
| `String` return documented as `"hello"` | `unknown`: overlap is insufficient and cardinality proofs are outside the first slice. |
| Subset-side union with one inhabited trusted disjoint arm | `conflict` even if another arm is included; all arms included yields `compatible`. |
| Authored project ancestry vs absent project ancestry | Inclusion may prove `compatible`; absence never supplies a conflict proof. |
| Trusted core/stdlib disjoint arm | `conflict`, exact tag location, authoritative merged `sig`/`inline` basis and proof reason. |
| Extended/refinement payload or authored `@extrbs` basis | `unknown` in the first slice; no erasure fallback. |
| Nested Dynamic, void, self/instance/class, type variables, interfaces | `unknown`, even if ordinary gradual acceptance would succeed. |
| Library/plugin/inference basis, unavailable type evidence or contested member | `unknown`; no compatibility or mismatch claim. |
| Overloads/correlations or unsupported tag/parameter forms | One explicit `unknown` result per claim; no first-overload fallback. |
| Malformed supported payload vs valid unsupported extension | `invalid_claim` vs `unknown`, respectively. |
| Missing named parameter or ambiguous valid definition | `unknown` with subject/association reason. |
| Altered source, request, signature, or consulted input | Integrity rejection; no accepted stale claim verdict. |
| One successful and one failed lens target; all targets failed | Available results and distinct target-unavailable rows; preserve lens exit 0/1 respectively. |
| Unsupported request/schema/grammar revision | Existing usage error 64, no document. |
| Duplicate ids, out-of-range spans, forged declaration identity | Protocol/integrity rejection under the ratified lens policy, not semantic invalidity. |
| Same Ruby name in different documentation scopes | Results remain associated with their individual ids and sources. |
| Claim inserted/changed/removed | Underlying contracts, inference and ordinary diagnostics stay unchanged. |
| Multiple claims, initial request without a site key | One lens process, one ordered result per id, same-session site keys; no preflight. |
| Counts with decided/unknown/invalid/unavailable results and zero claims | Derived from validated exhaustive rows; zero claims never reports 100% checked. |
| Unsupported producer version or missing claims capability | Explicit unavailable validation or compatibility rejection, never silent success. |

Zard's tests cover extraction, batching, integrity validation, exact tag association, diagnostics and optional operation. Semantic relation tests belong to Rigor. A mock response alone does not satisfy the end-to-end gate.

## Open decisions and handoff

Owner ratification is still required for the lens amendment, request and claims-section schemas/revisions, exact grammar/capability identifiers, and the conservative proof policy. The locator-to-site wire detail must permit constructing the first request without a prior site key. The availability/null-verdict shape for failed targets, and detailed integrity-error reporting within existing lens exits, also remain open. These are consumer positions for upstream review, not newly accepted requirements.

The implementation handoff remains gated on that agreement:

1. Review this proposal jointly with the Rigor owner, especially directional inclusion, proof meanings, unknown reasons, grammar revisioning, and authoritative contract coverage. Record an accepted producer contract before implementation.
2. Implement the optional lens request, same-session site association, non-authoritative claim channel, and conservative semantic proof operation in Rigor. Keep unsupported cases explicit; add the acceptance fixtures and claim non-interference checks.
3. Publish a Rigor release carrying the operation, schema documentation and evidence. Verify its actual CLI output against the agreed contract; no new Zard mismatch behavior ships before this dependency.
4. Extend the existing `zard-rigor` batch lens call with extracted tags/provenance, then consume the claims section and derive coverage counts. Add transport and source-binding tests plus real released-CLI fixtures. Do not duplicate semantic proofs in the adapter.
5. Integrate the results with the documentation check surface, with separate mismatch, invalid and unchecked states, and demonstrate operation both with and without the optional producer. Update user documentation and compatibility declarations after the integration passes.

This proposal is complete when its boundary and acceptance criteria are reviewable. It does not claim #5's runtime validation behavior is implemented.
