# Use an em dash for named ZARD documentation tags

ZARD uses an em dash `—` when a named documentation tag or an optional type must be separated from its description. A typeless, nameless tag such as `@return` uses the existing `@return description` form. InlineRBS keeps `--` as its own contract-note syntax inside `@extrbs`; a YARD-like tag without the required `—` is not a ZARD type hint.

## Consequences

- `@param value — Input text.` is ZARD documentation.
- `@param value [String] — Input text.` is ZARD documentation with a claim.
- `@return Normalized text.` is ZARD documentation without a type claim.
- `@return [String] — Normalized text.` is ZARD documentation with a claim.
- `@return [String] Normalized text.` is YARD-like raw text, not a type hint.
- `@param value [String] Input text.` is preserved as raw text, not as a type hint.
- Named tags such as `@param`, `@option`, `@yieldparam`, and `@raise` require `—` before their description.
- `zard-doc lint` warns about YARD-like tags and can promote the warning to an error.
- `zard-doc lint` may warn when a documentation claim repeats a contract type.
- ZARD documentation tags require UTF-8 source text. Ruby source encoding declarations remain respected.
