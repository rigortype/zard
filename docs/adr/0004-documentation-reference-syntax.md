# Use BitClust references and YARD-compatible see tags

ZARD adopts BitClust Markdown references, accepts their RD link forms for compatibility, and supports YARD-style shorthand in `@see`. All forms share reference resolution, while original comment text and source provenance remain available. Compatibility makes existing Ruby documentation familiar and avoids a separate ZARD spelling for each kind of method.

Status: Accepted. The current implementation covers shorthand `@see` references and URLs; explicit BitClust and RD forms are specified here for subsequent implementation. This ADR records the language decision, not a claim that every form is already shipped.

## Problem Statement

Authors need links between Ruby declarations in API documentation. BitClust and YARD provide familiar conventions, but differ in delimiters, labels, and module-function spelling. Documentation must retain its original text even when a reference cannot be linked.

## Solution

Use explicit BitClust forms in prose and allow concise YARD-compatible targets in `@see`. Accept both `Kernel.#puts` and `Kernel?.puts` with identical meaning. Generated documentation links only to destinations it can identify reliably.

## User Stories

1. As an author, I want to link an instance method, so that readers can find related behavior.
2. As an author, I want to link a class method, so that readers can find construction and utility APIs.
3. As an author, I want either module-function spelling to work, so that existing comments remain usable.
4. As an author, I want relative method targets, so that comments need not repeat their owner.
5. As an author, I want an absolute target, so that a local namespace cannot change its meaning.
6. As an author, I want a custom label, so that references fit the surrounding explanation.
7. As an author, I want RD links accepted, so that migrating documentation does not require rewriting every reference.
8. As an author, I want links in prose and documentation tags, so that related APIs can be mentioned where they matter.
9. As an author, I want code examples preserved, so that literal reference syntax is not expanded inside code.
10. As a reader, I want links across generated input files, so that related declarations remain reachable.
11. As a reader, I want unresolved references preserved, so that incomplete documentation retains useful context.
12. As a tool author, I want original comments and source spans, so that normalization does not erase provenance.

## Implementation Decisions

### Accepted forms

| Form | Meaning | Availability |
| --- | --- | --- |
| `[m:Foo#bar]` | Explicit instance-method reference | Planned |
| `[m:Foo.bar]` | Explicit class-method reference | Planned |
| `[m:Kernel?.puts]` | Explicit module-function reference | Planned |
| `[label](m:Foo#bar)` | Explicit reference with a display label | Planned |
| `[c:Foo]` | Class or module reference | Planned |
| `[m:Math::PI]` | Constant reference | Planned |
| `[[m:Foo#bar]]` | RD-compatible method reference | Planned |
| `[[m:Kernel.#puts]]` | RD-compatible module-function reference | Planned |
| `[[c:Foo]]` | RD-compatible class or module reference | Planned |
| `@see Foo#bar` | Shorthand instance-method reference | Implemented |
| `@see Foo` / `@see Foo::CONST` | Shorthand class, module, or constant reference | Implemented |
| `@see Foo.bar Label` | Shorthand class-method reference with a label | Implemented |
| `@see #bar` / `@see .bar` | Reference relative to the current owner | Implemented |
| `@see Kernel.#puts` / `@see Kernel?.puts` | Equivalent module-function references | Implemented |
| `@see https://example.com Label` | External URL with an optional label | Implemented |

The `@see` examples are comment payloads, written as `# @see ...` in Ruby source. Explicit forms also belong in `@see` descriptions once implemented; they are not shorthand target tokens and must be recognized before shorthand parsing.

### Targets and normalization

- `Foo#bar` selects an instance method. `Foo.bar` selects a singleton method.
- `Kernel.#puts` and `Kernel?.puts` select the same module-function reference and link to its public singleton copy. Normalization preserves the original spelling for display and provenance. Relative `.#puts` and `?.puts` follow the same rule.
- A leading `::` requests a root target. Relative `#bar` and `.bar` use the current class or module; shorthand top-level instance methods use the empty owner.
- Qualified targets search the current namespace and its namespace prefixes. This matches YARD's namespace-based convention, including qualified openings such as `class Outer::Caller`; it does not reproduce Ruby's lexical constant lookup.
- A nearer declared owner shadows outer owners. If its requested member is missing, private, or undocumented, resolution stops and preserves the reference as text.
- Attribute writers use their actual method name with `=`. An accessor exposes reader and writer references, which may share one rendered declaration. A replacement reader remains distinct from a retained writer.
- Valid Unicode owners and method names participate in lookup. Method punctuation remains part of the target; normalization changes only the owner/method separator.
- Explicit constant receiver paths are matched against declared namespace candidates. Dynamic receiver expressions and runtime aliases do not establish object identity.

### Labels and comment boundaries

- Shorthand `@see` uses the first whitespace-separated token as its target and the remaining text as an optional display label. Leading and trailing whitespace is trimmed for rendering. No `—` is required, as clarified by ADR 0002.
- If no label is supplied, the original target spelling supplies the display text. Labels and destinations must be escaped appropriately for generated Markdown.
- Existing documentation continuation rules apply. Continuation lines remain part of the same `@see` description and, for a resolved shorthand reference, its label.
- Explicit Markdown forms use `[label](m:target)` for labels. A label consisting entirely of a backtick code span keeps that code presentation, following BitClust.
- Method names containing brackets use BitClust escaping: `[m:Hash#\[\]]`. RD compatibility accepts the historical form `[[m:Hash#[] ]]`, including its delimiter-separating space.
- References are recognized in prose, including documentation tag descriptions, while inline code and fenced or indented code blocks remain literal. An `@example` code region is not implicitly a reference region.
- RD compatibility covers link syntax only. It does not reinterpret the entire comment as an RD document.

### Resolution and output

- Resolve against explicit declarations in the generated input set. The single-document API uses that document; the CLI uses all input files in its combined output.
- A destination must identify exactly one public declaration with rendered API documentation. Private, undocumented, ambiguous, unresolved, and refinement targets remain text with their original description intact.
- Equivalent forms resolve to the same destination. References to a shared declaration use one stable, collision-free anchor, independent of parameter display and heading slug rules.
- URL shorthand supports HTTP, HTTPS, and mailto. It does not require declaration lookup.
- Declaration lookup does not follow inheritance or mixins, evaluate Ruby, infer runtime receiver identity, or fetch external API inventories. These limits are deliberate even where YARD can resolve more broadly.
- The core retains documentation descriptions, raw source, and spans. Reference interpretation belongs to documentation generation and does not turn a reference into a contract or documentation claim.
- A future structured reference representation must preserve provenance and respect the versioned model boundary; this ADR does not add a public model field or resolver API.

## Testing Decisions

Use the existing parse API, Markdown generation API, and CLI as the acceptance seams. Assert rendered destinations and preserved source text rather than requiring a new resolver interface.

- Cover qualified and relative instance/class methods, root targets, namespace-prefix lookup, and shadowing.
- Verify that both module-function spellings, with or without an owner, produce the same destination and one anchor.
- Cover reader/writer accessors, aliases, operator methods, Unicode owners, and Unicode method names.
- Verify labels, continuation lines, spacing, URL escaping, empty descriptions, and punctuation-only unresolved targets.
- Verify private, undocumented, missing, ambiguous, dynamic-receiver, and refinement cases retain text rather than linking to an unrelated declaration.
- Exercise multiple CLI input files, deterministic output, and cross-file ambiguity through the existing CLI.
- When explicit forms are implemented, verify BitClust/RD equivalence, bracket escaping, custom labels, literal code regions, and unchanged raw comments and source spans through the same seams.

## Out of Scope

Full RD rendering, YARD's `{target}` prose syntax, documentation copying via `(see target)`, runtime ancestry resolution, external reference databases, BitClust schemes beyond `m:` and `c:`, BitClust document/method fragment schemes, and the proposed `[label][m:target]` reference-style form are outside this decision. Unresolved-reference lint diagnostics are a separate decision; this ADR requires lossless fallback rather than a new warning policy.

## Further Notes

The explicit forms are a compatibility subset, not a claim of complete BitClust or YARD rendering compatibility. ADR 0001 keeps API documentation separate from contracts, ADR 0002 governs documentation markers and continuation, and ADR 0003 preserves the core/documentation package boundary.

Primary references:

- [BitClust Markdown specification, cross references](https://github.com/rurema/bitclust/blob/581943661862910ff2035df2974709aef816a1c0/doc/markdown-samples/MARKUP_SPEC.md#7-クロスリファレンスハイパーリンク).
- [BitClust Markdown reference implementation](https://github.com/rurema/bitclust/blob/581943661862910ff2035df2974709aef816a1c0/lib/bitclust/mdcompiler.rb#L849).
- [Rurema Markdown migration notes](https://blog.n-z.jp/blog/2026-07-23-rurema-to-markdown.html).
- [YARD reference syntax and automatic `@see` linking](https://github.com/lsegal/yard/blob/3d8670543d2408baea3a1360b2258fde2ee65917/docs/GettingStarted.md#L395-L409).
- [YARD `@see` tag definition](https://github.com/lsegal/yard/blob/3d8670543d2408baea3a1360b2258fde2ee65917/lib/yard/tags/library.rb#L503-L513).
- [YARD namespace lookup](https://github.com/lsegal/yard/blob/3d8670543d2408baea3a1360b2258fde2ee65917/lib/yard/registry_resolver.rb#L50-L100).
