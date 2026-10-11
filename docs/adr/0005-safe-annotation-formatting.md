# Format annotations with semantic preservation checks

Status: Accepted.

ZARD formatting normalizes annotation layout without interpreting contract payloads or converting ambiguous documentation into claims. Moving a contract can change the ownership of documentation continuation lines, so source layout alone is not sufficient to establish a safe edit.

## Interface and package

The core provides `Zard.format(source, path:)`. Its result exposes `source`, `document`, `diagnostics`, and `changed?`. Formatting does not mutate the input or read or write files. The result contains a freshly parsed document whose raw text and spans refer to the formatted source. Invalid byte encodings that cannot enter the parser produce an empty document with an error diagnostic. Formatting diagnostics also refer to the returned source.

The existing `zard-doc` executable provides `format PATH`, `format --check PATH...`, and `format --write PATH...`. Plain mode prints one formatted input; `-` reads standard input. Check and write modes support recursive directory inputs. Write mode rejects standard input. Check and write are mutually exclusive.

Exit status is 0 on success, 1 for source errors or changes required in check mode, and 2 for invocation or I/O errors. Warnings, including ambiguous documentation left unchanged, do not fail formatting. All inputs are read and validated before write mode changes any file. It leaves unchanged files untouched. Filesystem write failures are reported, but multi-file writes are not transactional.

## Allowed transformations

- Normalize the comment prefix of standalone `@extrbs` annotations to `# @extrbs`, retaining indentation, payloads, notes, and trailing whitespace. A noncanonical annotation with nonblank continuation text is left unchanged because its intended boundary is ambiguous.
- Stably move `@extrbs` lines before other annotations within an attached contiguous comment block. Preserve the relative order of contract lines and all other lines. Preserve the original sequence of line terminators, including mixed LF/CRLF and an absent final newline.
- Remove a redundant em dash from parsed `@return` and `@yieldreturn` tags without claims, except when removal would reinterpret the description's leading bracket or em dash. Keep those ambiguous descriptions with the existing diagnostic. Canonical named or typed markers already have their required delimiter and need no conversion.
- Keep missing markers, YARD-like tags, unknown tags, indented documentation, examples, string literals, embedded documents, and detached comments unchanged. Retain the parser's diagnostics rather than guessing a documentation boundary.

Before accepting a contract reorder, reparse it and compare declarations, documentation fields and order, and contract payloads/notes. Contract ordering may change only through stable `@extrbs` placement. Reject a reorder that changes these values, keep the safe spacing/marker edits, and emit `format.unsafe-extrbs-order`. This protects continuation ownership and declaration attachment. Noncanonical `@extrbs` prefix repair intentionally makes a previously raw annotation a contract; it is the only such conversion.

Malformed Ruby and non-UTF-8 source are returned unchanged with errors. The formatter does not validate types, rewrite Ruby code, generalize comment spacing, format RBS payloads, infer missing documentation markers, or migrate YARD documentation.

## Verification

Use the formatting API, existing parse API, and real CLI. Verify payloads, notes, multiline descriptions, raw text, byte spans, indentation, line terminators, safe and unsafe reorder cases, ambiguous comments, and a byte-identical second pass. Exercise stdout, stdin, check and write modes, directories, read errors, and invalid inputs before writing.
