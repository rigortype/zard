---
name: zard-release-prep
description: Prepare a ZARD release by aligning both gem versions, sealing the changelog, and verifying installed packages. Use when preparing or cutting a ZARD release.
---

# ZARD Release Prep

Prepare `zard` and `zard-doc` as one release from this monorepo. Preparation ends with a reviewable release diff, built packages, and verification results. Publishing is a separate step requiring user authorization for the target version; a request to prepare a release authorizes preparation only.

## Establish the release candidate

Read `CONTEXT.md`, the package-boundary ADR, both gemspecs, `Rakefile`, and the current CI workflow. Resolve the repository root from this skill's location (`../..`) and run commands there.

Confirm the target version and milestone scope from the request and GitHub. Check the working tree and account for existing edits before switching branches. Prepare on `release/X.Y.Z` from the current mainline, preserving unrelated work. Use the repository's worktree convention if isolation is needed.

For `v0.0.1`, the release path is Ruby source → versioned ZARD model → public API Markdown and lint, without Rigor. Rigor lens integration and a formatter are later work. Follow subsequent milestones for later releases rather than carrying this initial scope forward.

Completion: the target version, candidate revision, included issues, and remaining blockers are identified.

## Align package metadata and release notes

Update these together:

- `lib/zard/version.rb` and `zard-doc/lib/zard/doc/version.rb` to the same version.
- The `zard` dependency in `zard-doc/zard-doc.gemspec` so it admits the released core and excludes incompatible versions. For the initial release, `~> 0.0.1` admits the intended `0.0.x` line.
- Both READMEs with installation and usage instructions for the published gems.
- `CHANGELOG.md` with the released version and release date in the user's timezone.

Seal `[Unreleased]` by consolidating every entry into user-facing changes. Several parser commits may become one capability; preserve meaningful limitations and behavior changes. Keep one unwrapped line per bullet and use the existing Keep a Changelog sections. Add real PR links where available; omit invented references. Compare the candidate history with the previous release tag, or the complete history for the first release, to catch missing user-facing changes.

Keep an empty `[Unreleased]` section above the release section. For the first release, link `[0.0.1]` to the tag and `[Unreleased]` to `compare/v0.0.1...HEAD`; later release links compare the previous and current tags. Add a short release summary describing the principal capabilities.

Run `bundle install` after changing package versions. `Gemfile.lock` is currently ignored; use it locally without adding it to Git. Generated gems in `pkg/` also remain untracked.

Completion: both package versions, the dependency constraint, installation examples, and release notes agree on the target version.

## Verify built and installed packages

Run the repository's default gate after the final code and metadata edits:

```sh
bundle exec rake
git diff --check
```

If the sandbox prevents Standard from writing its cache, set `RUBOCOP_CACHE_ROOT` to a writable temporary directory and rerun. Report actual failures separately from environment restrictions.

The default task builds both gems. Check the target-version artifacts in `pkg/`, including their packaged files, executable, required Ruby version, and runtime dependencies. Validate installation in a fresh temporary `GEM_HOME`, outside the development bundle:

1. Resolve runtime dependencies and install the built `zard` and `zard-doc` packages. Use the temporary gem home for all installation writes.
2. With `RUBYLIB`, `RUBYOPT`, and Bundler environment overrides cleared, run Ruby outside the checkout. Require `zard` and `zard/doc`, parse documented Ruby source, and render the resulting model. Verify loaded gem paths belong to the temporary installation.
3. Invoke the installed `zard-doc` executable to render a multi-file fixture and stdin input. Compare output with the expected public API Markdown.
4. Check lint behavior: clean input returns 0, warnings return 0 by default and 1 with `--fail-on warning`, syntax errors return 1, and unreadable input returns 2. Rendering invalid or unreadable input emits no partial Markdown.

If package installation cannot resolve dependencies because of network or credentials, retain the artifacts and report that installed-package verification remains incomplete.

Confirm the release candidate's CI passes on every Ruby version listed in `.github/workflows/main.yml`; local success on one Ruby version does not establish the matrix result. Review the final diff for scope and record commands and results in the release PR or handoff.

Completion: repository gates, both package builds, independent installed-package checks, and candidate CI are green, or the preparation handoff explicitly identifies unfinished checks and blockers.

## Hand off the release candidate

When committing or opening a PR is authorized, keep unrelated fixes separate from release metadata and use a release commit such as `Bump up version to X.Y.Z`. Open the release PR against the repository's mainline and attach it to the chat with the available artifact tool. Include the summary, milestone blockers, gate results, and installed-package verification.

Before landing, confirm included issues are complete and the checked revision is still the candidate. Mainline changes that alter the candidate require reconciling the release notes and rerunning affected checks. Obtain any missing authorization for merge or publication after the candidate is ready for review.

## Publish an authorized version

Use a clean checkout of the approved, landed revision. Build and identify both artifacts from that revision and verify the version is still unused on RubyGems. Check publisher access and MFA availability without printing credentials.

The current `Rakefile` loads `bundler/gem_tasks` for the root gem and adds a build task for `zard-doc`; it has no coordinated two-gem publication or GitHub Release hook. Use explicit publication steps unless that mechanism has been implemented and verified:

1. Publish `pkg/zard-X.Y.Z.gem` to RubyGems and confirm the version is available.
2. Publish `pkg/zard-doc-X.Y.Z.gem` and confirm its dependency resolves to the published core.
3. Create `vX.Y.Z` on the approved release revision and push that tag. If the tag already exists, verify its revision instead of replacing it.
4. Create the GitHub Release for that tag using the sealed changelog section as its body. Use a body file to preserve Markdown. Attach both artifacts when appropriate.
5. Repeat installed-package smoke checks in a fresh temporary gem home, installing the published versions from RubyGems. Confirm both versions, parse/render, and the CLI work.
6. Close the release issue and milestone only after both published gems, the correct tag, the GitHub Release, and the published-package smoke checks are confirmed.

On partial failure, record which external steps succeeded. Verify remote state before retrying and resume at the missing step; published gem versions are immutable. Completion means every publication result above is observed, with links and the final revision reported to the user.
