## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues. Use the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context layout. See `docs/agents/domain.md`.

## Types come from Rigor, not from reading code

This project is type-checked by [Rigor](https://github.com/rigortype/rigor). A type you did not obtain from Rigor is a guess, and a guessed type is never written anywhere: not in `sig/`, not in an inline annotation (`#:`, `# @rbs`), not in a doc comment, not in a review comment, and not as the reason for a nil check or an `is_a?` guard.

- The type of an expression: `rigor type-of FILE:LINE:COL`, or `rigor annotate FILE` for a whole file.
- The signature of a method: `rigor sig-gen --print FILE`; paste what it prints, never what you expect.
- A parameter type is the one thing inference does not give you: derive it from the call sites with `rigor sig-gen --observe PATH` and keep it only while `rigor check` stays green.
- When Rigor answers `Dynamic[top]` or `untyped`, or `sig-gen` skips the method, do not fill the gap. Report the exact command and its output; the gap is the finding.
- Every type you state to a human carries the command that produced it, so it can be re-run.

The `rigor-type-oracle` skill (`rigor skill --full rigor-type-oracle`) has the full procedure. With the Rigor MCP server connected, `rigor_type_of`, `rigor_annotate`, and `rigor_sig_gen` are the same oracle as tool calls.
