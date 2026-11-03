# Documentation claim validation through Rigor

Status: proposal for Zard #5. The command, schemas, and semantic proof capability below are unimplemented. This document does not change the accepted ADRs or authorize a release.

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

A narrower advertised parameter domain or a broader documented return domain is compatible under this rule. This proposal does not check whether documentation exhaustively describes the whole contract. Conversely, an overlapping type can violate inclusion without being disjoint. Rigor may report a mismatch only when it proves the required inclusion false; a failed proof attempt is `unknown`.

For example, an isolated fixture can declare the RBS alias `type text = String` and compare a return claim `text` with an authoritative return `::String`. Once Rigor resolves both to the same type, different spelling must still yield `compatible`. Conversely, consider a return contract `Project::A | Project::B` and a claim `Project::B | Project::C`: the shared `Project::B` arm establishes overlap only. If the producer cannot establish whether `Project::A` is covered by the claim, nor prove a counterexample, the result must be `unknown`. These are proposed test inputs, not inferred types of repository code.

A mismatch states that the contract does not support the documented promise. It does not claim a particular runtime execution violated it. A narrower inferred body return cannot override a broader authoritative return contract to make that contract comparison pass. Neither string inequality nor a missing diagnostic is evidence of either outcome.

The first producer implementation may prove only a conservative subset of these relations. It must expose its supported subject/grammar capabilities and return `unknown` elsewhere. It must not copy the existing signature-collision diagnostic's disjointness test and describe all other pairs as compatible.

## Initial subject coverage

Start with `@param` and `@return` on an unambiguous method declaration with one authored overload. Match a parameter by its Ruby name and parameter kind; unnamed RBS positions require a verified correspondence with the source definition. Limit the first parameter implementation to required positional and required keyword parameters. An undeclared or unresolvable parameter subject is an explicit `unknown` result with a reason, never a fallback to the first parameter.

Return `unknown` for multiple overloads, argument/return correlations, generic binders the producer cannot instantiate soundly, forwarded or destructured parameters, optional/rest parameters, attributes, constants, yields, options, raises, unsupported declarations, ambiguous sites, and contested members. Each claim still gets a result. Later coverage requires a documented producer policy and conformance fixtures; overloads must never be paired by array order or collapsed into independently unioned slots that lose correlations.

Dynamic or unavailable evidence cannot prove compatibility or incompatibility. Inferred facts are not accepted as the comparison basis in the first version. In particular, observed examples and inferred underapproximations cannot prove a universal input or return promise. A future inferred-fact capability must define whether evidence is a sound upper bound, lower bound, or exact result and which proofs it permits; a display slot alone is insufficient.

## Proposed batch CLI

Use one new external operation rather than reinterpreting existing lens output:

```text
rigor claims check --request claim-request.json --format json [--config FILE] [--workers N]
```

This spelling is proposed, not an available command. The current directory is the explicit project root. The request file is UTF-8 JSON. Rigor analyzes the requested files together in the same configured environment it uses for `check`; it must not import the claims into that environment. Diagnostics and facts computed with a claim present must equal those computed without it, apart from the new claim results.

Successful processing writes one response object to stdout, in request order; progress goes to stderr. Exit `0` means the response is complete and valid, including when it contains incompatibility or unknown results. Exit `64` means the request cannot be trusted or supported as a protocol request; exit `70` means the process failed. Neither failure emits a successful response. The consumer decides whether proven claim mismatches fail its documentation check.

### Request, revision 1

```json
{
  "schema": "rigor-claims-request/v0",
  "revision": 1,
  "grammar": "rigor:v1",
  "files": [{"path": "lib/widget.rb", "digest": "sha256:<64 lowercase hex>"}],
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

The sample uses illustrative offsets, digest, and type text; it is not a runnable fixture or a statement about repository code. Spans count bytes in the exact file, are zero-based and end-exclusive, and contain no derived line/column identity. `id` is a caller-supplied opaque identifier unique within the request; it is not a stable Rigor symbol id. The adapter can retain its own scope and declaration/tag identifiers in that string or an external map. Duplicate Ruby names in independent documentation scopes must not merge claims.

The file digest covers the entire source, including prose. Rigor requires project-relative canonical paths, rejects duplicate file entries, duplicate claim ids, out-of-range spans, mismatched declaration identity and stale digests, and never attaches a claim to a neighboring declaration. A declaration that exists but is outside the producer's supported coverage yields `unknown`; a request whose supplied span does not identify the declared source object is an integrity error.

The adapter is responsible for extracting `tag.claim`, its tag span, and the tag's attachment to the declaration from the ZARD parser's exact source snapshot. Rigor validates the requested declaration identity, the tag span's file bounds, and parameter binding; it does not independently certify the ZARD parser's tag attachment or extraction. The adapter retains that association and checks it again when attaching the result. The request carries claim text as input, not an executable expression or an inline signature. Claims without a type payload are omitted.

### Response, revision 1

```json
{
  "schema": "rigor-claims/v0",
  "revision": 1,
  "producer": {"name": "rigor", "version": "<released version>", "engine_source": null},
  "grammar": "rigor:v1",
  "request_digest": "sha256:<digest of the exact request bytes>",
  "capabilities": ["authored-single-overload-param", "authored-single-overload-return"],
  "context": {"digest": "<opaque analysis identity>"},
  "files": [{"path": "lib/widget.rb", "digest": "sha256:<64 lowercase hex>"}],
  "results": [{
    "id": "app:widget-result:tag-0",
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

The producer computes `request_digest` over the exact UTF-8 request file bytes. The adapter verifies it before accepting any verdict, so an id reused with different claim text cannot accept a response for the old request. The response must also echo exactly the requested ids, order, grammar, and file digests, with one result per claim. Its context must identify configuration, target Ruby, loaded RBS and plugins, signature roots/digests, lockfiles, and analysis engine, with the same completeness caveats as lens context. Include digested project source inputs consulted by the proof. The context digest is opaque and must not be treated as a complete cache key by the adapter.

Each result names the `documentation_coverage` relation. Its `direction` is `claim_subtype_of_contract` for a supported parameter or `contract_subtype_of_claim` for a supported return; direction is `null` when no supported relation applies. `basis` is null when no authoritative slot was resolved. Otherwise it identifies the member tuple, exact definition site, overload index, slot (`return` or parameter name/kind/index), provenance, and contract source path/span where available. Evidence entries identify the producer's proof kind and source facts; human-readable type text and messages are explanatory only. No internal analyzer objects or serialized implementation classes cross the boundary.

For example, a producer proving that an authored `Integer` result is outside a `String` claim could return these fields on the result (illustrative source offsets):

```json
{
  "verdict": "conflict",
  "reason": "proven_non_inclusion",
  "basis": {
    "member": {"owner": "Widget", "scope": "instance", "name": "result"},
    "definition": {"file": "lib/widget.rb", "span": {"start_offset": 80, "end_offset": 110}},
    "overload": 0,
    "slot": {"kind": "return", "parameter": null},
    "provenance": {
      "kind": "sig",
      "source": {"file": "sig/widget.rbs", "span": {"start_offset": 10, "end_offset": 35}}
    }
  },
  "evidence": [{
    "kind": "non_inclusion", "rule": "disjoint_types",
    "contract_display": "::Integer", "claim_display": "::String"
  }]
}
```

For a parameter slot, `parameter` is `{name, kind, index}` and `kind` uses the producer's documented Ruby parameter vocabulary; for a return it is null. The overload index addresses the authoritative single overload and does not authorize selecting one branch of an overloaded contract. Contract source files are among the response's digested inputs. The adapter validates these references but trusts only the allowlisted producer to perform the proof; it must not recheck it using `contract_display` or `claim_display`. Computed paths must not disclose absolute local filesystem paths. Evidence outside the project needs a documented package/source identity; the first implementation may return `unknown` until that identity is supported.

| Verdict | Required producer evidence | Consumer behavior |
| --- | --- | --- |
| `compatible` | A proof that the required inclusion holds on a supported authoritative basis. | Show checked status; do not alter the contract. |
| `conflict` | A proof that the required inclusion is false, with a structured reason such as `proven_counterexample` or `proven_disjoint`. | Emit a claim mismatch at the tag span with the evidence reference. |
| `unknown` | No supported proof, dynamic/unavailable basis, unsupported grammar feature/subject, or unresolved association within valid source. | Show unchecked status and reason; do not emit a type mismatch. |
| `invalid_claim` | The selected supported grammar rejects the payload's syntax or semantic well-formedness. | Emit an invalid-claim diagnostic, distinct from mismatch. |

Suggested unknown reasons include `no_authored_contract`, `dynamic_evidence`, `unavailable_evidence`, `contested_member`, `ambiguous_subject`, `unsupported_subject`, `unsupported_overloads`, `unsupported_correlation`, `unsupported_grammar_feature`, and `unsupported_relation`. A claim referring to an unresolved type whose meaning the environment cannot establish is `unknown`, unless the supported grammar conclusively establishes that it is invalid.

Unsupported protocol/schema or grammar revisions, malformed JSON, stale source, and invalid identity fields are whole-request integrity errors. They must not be disguised as per-claim `invalid_claim` results. A valid extended payload outside the implementation's advertised semantic subset is `unknown`, not invalid syntax.

## Grammar and drift

Rigor owns parsing and normalization of plain RBS and extended types, name resolution in the declaration's lexical context, aliases, inheritance, variance, refinements, and proof policy. It must compare semantic types before any lens erasure. The proposed grammar revision is a negotiated protocol field; the adapter's existing `rigor:v1` string alone is not proof that all extended forms can be checked.

For a plain-RBS-only initial producer, report valid extended claims as unsupported and advertise that limitation. An authored `@extrbs` contract cannot silently fall back to its erased plain-RBS type: return `unknown` until the producer can resolve the authoritative extended contract. Do not make `@extrbs` support appear by changing Zard's compatibility manifest.

Rigor checks requested source digests before analysis and verifies the analysis read those bytes. Source or consulted signature/input drift during the operation invalidates the response. The adapter also rereads the requested files after the subprocess returns, validates the response's ids, basis references and spans, and rejects drift atomically. A response cannot be reused merely because tag or declaration bytes remain unchanged; the surrounding project environment may have changed.

## Compatibility and release gate

The new request/response schemas are independent of `lens/v0`. A breaking change increments their revision. A producer release advertises supported grammar revisions, subject coverage and proof capabilities; absent capability means unavailable, not successful validation. Zard must accept only explicitly tested released producer/schema/grammar combinations and preserve an explicit unavailable result when claim validation is not installed. Raw source-checkout engines need a separate development-only route, never an implicit release allowlist entry.

Before enabling mismatch diagnostics, release Rigor's implementation with real CLI conformance artifacts, then add the corresponding Zard adapter compatibility entry and transport integration tests. A shared schema revision is insufficient to admit a new producer version. Existing parsing and documentation generation must continue to work without Rigor.

## Acceptance matrix

Each producer fixture must execute the proposed CLI against a real isolated project and retain request, source/signature files, response, stderr, exit status, and assertions. Type spellings below are illustrative fixture inputs; expected verdicts require the released producer's semantic proof.

| Scenario | Required observable |
| --- | --- |
| Equal semantic type with different alias/absolute spelling | `compatible` if resolved and proven; never mismatch from spelling. |
| Narrower advertised parameter; broader documented return | Correct directional inclusion produces `compatible`. |
| Broader advertised parameter; narrower documented return | `conflict` only with proof of failed inclusion; otherwise `unknown`. |
| Proven disjoint claim/contract | `conflict`, exact tag location, authoritative basis and proof reason. |
| Same erasure with incompatible extended refinements | Full semantic result when supported; otherwise `unknown`. |
| Dynamic, unavailable, contested, or inference-only evidence | `unknown`; no compatibility or mismatch claim. |
| Overloads/correlations or unsupported tag/parameter forms | One explicit `unknown` result per claim; no first-overload fallback. |
| Malformed supported payload vs valid unsupported extension | `invalid_claim` vs `unknown`, respectively. |
| Missing named parameter or ambiguous valid definition | `unknown` with subject/association reason. |
| Altered source, signature, or consulted input during analysis | Integrity failure; no accepted successful response. |
| Duplicate ids, out-of-range spans, forged declaration identity | Exit 64; no successful response. |
| Same Ruby name in different documentation scopes | Results remain associated with their individual ids and sources. |
| Claim inserted/changed/removed | Underlying contracts, inference and ordinary diagnostics stay unchanged. |
| Multiple claims, unsupported version, missing producer | One ordered batch; strict protocol rejection or explicit unavailable capability, never silent success. |

Zard's tests cover extraction, batching, integrity validation, exact tag association, diagnostics and optional operation. Semantic relation tests belong to Rigor. A mock response alone does not satisfy the end-to-end gate.

## Implementation order and handoff

1. Review this proposal jointly with the Rigor owner, especially directional inclusion, proof meanings, unknown reasons, grammar revisioning, and authoritative contract coverage. Record an accepted producer contract before implementation.
2. Implement the request parser, source identity checks, non-authoritative claim channel, and conservative semantic proof operation in Rigor. Keep unsupported cases explicit; add the acceptance fixtures and claim non-interference checks.
3. Publish a Rigor release carrying the operation, schema documentation and evidence. Verify its actual CLI output against the agreed contract; no new Zard mismatch behavior ships before this dependency.
4. Add a thin batch client to `zard-rigor`, extracting existing tags/provenance and consuming producer verdicts. Add transport and source-binding tests plus real released-CLI fixtures. Do not duplicate semantic proofs in the adapter.
5. Integrate the results with the documentation check surface, with separate mismatch, invalid and unchecked states, and demonstrate operation both with and without the optional producer. Update user documentation and compatibility declarations after the integration passes.

This proposal is complete when its boundary and acceptance criteria are reviewable. It does not claim #5's runtime validation behavior is implemented.
