# Use an em dash for ZARD documentation tags

ZARD recognizes API documentation tags only when an em dash `—` separates the name or optional type from the description. InlineRBS keeps `--` as its own contract syntax inside `@extrbs`; a YARD-like tag without `—` is not a ZARD type hint.

## Consequences

- `@param value — Input text.` is ZARD documentation.
- `@param value [String] — Input text.` is ZARD documentation with a claim.
- `@param value [String] Input text.` is preserved as raw text, not as a type hint.
- `zard-doc lint` warns about YARD-like tags and can promote the warning to an error.
- ZARD documentation tags require UTF-8 source text. Ruby source encoding declarations remain respected.
