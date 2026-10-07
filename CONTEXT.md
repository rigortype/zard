# ZARD

ZARD is a Ruby self-documentation notation for people and AI agents. It uses plain RBS contracts, Rigor extensions, and separate API documentation so that prose does not require repeated type text.

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
A type-facing statement about Ruby code. Plain RBS contracts use `@rbs` or `#:`; extended contracts use `@extrbs`.
_Avoid_: API description

**`@extrbs`**:
A typed comment channel for contract information that plain RBS cannot express. It may carry plain RBS, but `@rbs` and `#:` are preferred for plain RBS.
_Avoid_: API documentation tag

**API documentation**:
Human-facing information about a public Ruby declaration.
_Avoid_: type contract

**Declaration**:
A Ruby class, module, constant, attribute, or method represented in the versioned ZARD model.
_Avoid_: documentation item

**Alias target**:
The method name that an alias refers to in the same Ruby scope.
_Avoid_: copied documentation

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

**Grammar revision**:
A named revision of the `@extrbs` type grammar that a tool reads or writes.
_Avoid_: package version

**Provenance**:
The source, location, syntax, and origin of a contract, documentation item, or fact.
_Avoid_: inferred origin

**ZARD documentation marker**:
The em dash `—` that separates a named documentation tag or an optional type from its description. A tag with neither a name nor a type writes its description directly, without this marker.
_Avoid_: `--` in documentation tags

**Documentation continuation line**:
A plain comment line that extends the preceding canonical ZARD documentation tag until another annotation or contract begins.
_Avoid_: explicit continuation marker

**YARD-like comment**:
A familiar documentation tag without the ZARD em dash. It may be preserved as raw text, but it is not a ZARD documentation claim.
_Avoid_: ZARD documentation
