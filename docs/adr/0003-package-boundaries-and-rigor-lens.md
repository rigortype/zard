# Keep the core independent from Rigor

The project uses a monorepo with separate gems for the ZARD core, API documentation, and Rigor integration. The core owns parsing, the versioned public model, provenance, and syntax diagnostics; Rigor owns inference and facts; API documentation consumes a versioned structured Rigor lens result when it is available. Subtree splitting is not part of the initial distribution plan.

## Consequences

- The core can parse and model ZARD without Rigor.
- API documentation can be generated without Rigor, but resolved type facts are then unavailable.
- The Rigor adapter must not expose Rigor internal analyzer classes as the package boundary.
- The first vertical slice is Ruby source to the ZARD model to Markdown documentation.
