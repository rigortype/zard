# Keep the core independent from Rigor and pin the grammar

The project uses a monorepo with separate gems for the ZARD core, API documentation, and Rigor integration. The core owns ZARD syntax, tag boundaries, source spans, provenance, and the versioned public model; it keeps `@extrbs` type payloads as text. Rigor owns the payload grammar, grammar revision, inference, and facts; API documentation consumes a versioned structured Rigor lens result when it is available. Subtree splitting is not part of the initial distribution plan.

## Consequences

- The core can parse and model ZARD without Rigor.
- The core does not duplicate Rigor's type parser or type semantics.
- An adapter declares the supported `rigor:v1` grammar revision.
- `@extrbs` comes first in an annotation block and uses exactly `# @extrbs` with one space.
- A formatter preserves that order and spacing.
- Rigor generates `sig/`; the project does not hand-maintain duplicate contracts there.
- API documentation can be generated without Rigor, but resolved type facts are then unavailable.
- The Rigor adapter must not expose Rigor internal analyzer classes as the package boundary.
- The first vertical slice carries class, module, constant, attribute, and method declarations from Ruby source through the ZARD model to Markdown documentation.
