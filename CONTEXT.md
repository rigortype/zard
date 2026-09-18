# ZARD

ZARD is a Ruby self-documentation notation for people and AI agents. It uses InlineRBS and RBS::Extended for type contracts, while keeping API documentation separate from type contracts.

## Language

**ZARD**:
The self-documentation language defined by this project.
_Avoid_: YARD, RDoc

**InlineRBS**:
RBS type notation written in Ruby source comments.
_Avoid_: YARD type syntax

**RBS::Extended**:
Rigor's extra type information attached to RBS declarations.
_Avoid_: a second type system

**Contract**:
A type-facing statement about Ruby code.
_Avoid_: API description

**`@extrbs`**:
A typed comment channel for InlineRBS and RBS::Extended.
_Avoid_: API documentation tag

**API documentation**:
Human-facing information about a public Ruby declaration.
_Avoid_: type contract

**Documentation claim**:
An optional type written in an API documentation tag. Rigor may check it, but it does not replace a contract or an inferred fact.
_Avoid_: authoritative type

**Contract note**:
Prose attached to a typed contract for people reading the code directly.
_Avoid_: API documentation

**Rigor fact**:
Type or provenance information produced by Rigor from code, contracts, and analysis.
_Avoid_: documentation claim

**Rigor lens**:
A structured summary of code, contracts, Rigor facts, and diagnostics.
_Avoid_: a second analyzer

**Provenance**:
The source, location, syntax, and origin of a contract, documentation item, or fact.
_Avoid_: inferred origin

**ZARD documentation marker**:
The em dash `—` that separates a documentation tag name or optional type from its description.
_Avoid_: `--` in documentation tags

**YARD-like comment**:
A familiar documentation tag without the ZARD em dash. It may be preserved as raw text, but it is not a ZARD documentation claim.
_Avoid_: ZARD documentation
