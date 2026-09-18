# Separate contract channels from API documentation

ZARD reads typed contracts from `@rbs`, `#:`, and `@extrbs`, and keeps API documentation in tags such as `@param` and `@return`. Plain RBS belongs in `@rbs` or `#:`, while `@extrbs` carries information that plain RBS cannot express; plain RBS in `@extrbs` is valid but not preferred. This lets people and AI agents write useful prose without making type text mandatory, while Rigor can check optional documentation claims without treating them as the source of truth.

## Consequences

- `@rbs` and `#:` remain the public contract forms that other RBS tools can read inline.
- `@extrbs` uses the `@rbs` tag forms and carries Rigor's extended type vocabulary.
- API documentation may omit types.
- A type in an API documentation tag is an optional documentation claim.
- When a documentation claim conflicts with a contract, the contract wins and Rigor reports the conflict.
- `zard-doc lint` may warn when a documentation claim only repeats the contract.
- Contract notes and API documentation remain separate.
