# Issue tracker: GitHub

Issues and specs for this repo live in GitHub Issues. Use the `gh` CLI.

## Conventions

- Create: `gh issue create --title "..." --body "..."`
- Read: `gh issue view <number> --comments`
- List: `gh issue list --state open`
- Comment: `gh issue comment <number> --body "..."`
- Add a label: `gh issue edit <number> --add-label "..."`
- Remove a label: `gh issue edit <number> --remove-label "..."`
- Close: `gh issue close <number> --comment "..."`

PRs are not a triage request surface.

When a skill says to publish to the issue tracker, create a GitHub issue.
When a skill says to fetch a ticket, run `gh issue view <number> --comments`.
