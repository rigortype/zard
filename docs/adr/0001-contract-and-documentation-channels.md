# Separate contracts from API documentation

ZARD keeps typed contracts in `@extrbs` and keeps API documentation in tags such as `@param` and `@return`. This lets people and AI agents write useful prose without making type text mandatory, while Rigor can check optional documentation claims without treating them as the source of truth.

## Consequences

- `@extrbs` accepts InlineRBS and RBS::Extended.
- API documentation may omit types.
- A type in an API documentation tag is an optional documentation claim.
- Contract notes and API documentation remain separate.
