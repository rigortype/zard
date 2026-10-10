# Use an em dash for named or typed ZARD documentation tags

ZARD uses an em dash `—` when a named documentation tag or an optional type must be separated from its description. A tag with neither a name nor a type writes its description directly. InlineRBS keeps `--` as its own contract-note syntax inside `@extrbs`; a YARD-like tag without the required `—` is not a ZARD type hint.

## Consequences

- `@param value — Input text.` is ZARD documentation.
- `@param value [String] — Input text.` is ZARD documentation with a claim.
- `@return Normalized text.` is ZARD documentation without a type claim.
- `@return — Normalized text.` is accepted, but `zard-doc lint` recommends removing the redundant em dash.
- `@return [String] — Normalized text.` is ZARD documentation with a claim.
- `@return [String] Normalized text.` is YARD-like raw text, not a type hint.
- `@yieldreturn yielded value.` follows the same rule as `@return`.
- `@option options :format — Output format.` is ZARD documentation.
- `@option options :format [Symbol] — Output format.` is ZARD documentation with a claim.
- Tags with no name and no type, such as `@note`, `@see`, `@deprecated`, and `@example`, write their description directly.
- For YARD compatibility, `@see` descriptions may contain a reference followed by a whitespace-separated display label; this form does not require `—`.
- `@param value [String] Input text.` is preserved as raw text, not as a type hint.
- Named tags such as `@param`, `@option`, `@yieldparam`, and `@raise` require `—` before their description.
- `zard-doc lint` warns about YARD-like tags and can promote the warning to an error.
- `zard-doc lint` may warn when a documentation claim repeats a contract type.
- ZARD documentation tags require UTF-8 source text. Ruby source encoding declarations remain respected.
- Every canonical ZARD documentation tag may continue across plain comment lines until another annotation or contract begins; no explicit continuation marker is used.
- An annotation is recognized only in the first content column immediately after `# `. Indented `@` text remains description content.
- Internal blank lines, relative indentation, and trailing whitespace are preserved. Leading and trailing blank continuation lines are removed from the normalized description.
- A multiline description remains one LF-normalized string. Its source span and raw text cover the complete comment block, with raw source bytes and line endings preserved.
- YARD-like and unknown tags keep their continuation lines as raw text and do not leak them into API documentation.
- Empty descriptions are preserved with a `documentation.empty-description` warning.
- Contract annotations end documentation continuation. Contract notes do not use documentation continuation rules.
- Markdown renderers keep multiline descriptions inside their list item and do not automatically fence `@example` content as code.
