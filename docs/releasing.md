# Releasing spacemap

A release is a `vX.Y.Z` tag on a commit on `main`. Pushing the tag runs
`.github/workflows/publish.yml`, which publishes the gem to RubyGems and creates the GitHub Release.
Agents never tag or publish; the owner does.

## Changelog

User-facing changes go under `## Unreleased` at the top of CHANGELOG.md, in the PR that makes them.

## Cut a release

1. On `main`, set `VERSION` in `lib/spacemap/version.rb` to `X.Y.Z`.
2. In CHANGELOG.md, move the `## Unreleased` entries under a new `## X.Y.Z` heading, leaving
   `## Unreleased` empty above it.
3. Commit both on `main` (directly or through a PR), then tag and push:

   ```
   git tag vX.Y.Z && git push origin main vX.Y.Z
   ```

The first release, 0.1.0, needs no version or changelog commit (both are in the initial gem); after
the one-time setup below it is just:

```
git checkout main && git pull && git tag v0.1.0 && git push origin v0.1.0
```

Publish then:
- checks the tag is `vX.Y.Z` and equals `Spacemap::VERSION`;
- checks the tagged commit is on `main` (an ancestor of `origin/main`);
- checks RubyGems doesn't already have spacemap `X.Y.Z` (HTTP 404 from its API; a 200 or any
  other answer fails without publishing);
- takes the release notes from CHANGELOG.md's `## X.Y.Z` section (fails if it's empty);
- builds `spacemap-X.Y.Z.gem`, pushes it with trusted publishing (no API key) in the GitHub
  environment `release`;
- creates the GitHub Release `vX.Y.Z` with the gem attached and the changelog section as notes.

When Publish succeeds, `.github/workflows/homebrew.yml` writes the Homebrew formula
`Formula/spacemap.rb` in [satoramoto/homebrew-tap](https://github.com/satoramoto/homebrew-tap):
the new `.gem` and the newest r2ui the gemspec allows (url and sha256 from RubyGems), as a resource
for each runtime gem. It installs the formula from source, runs `brew test` and
`brew audit --strict` on macOS, and pushes the tap. The first release creates the formula. The
whole formula is written by the workflow, so change it there (in `homebrew.yml`), not in the tap.
If it fails, nothing is pushed; fix it and run the workflow by hand (Actions → Homebrew → Run
workflow, optionally with a version). The formula changes only with a spacemap release: a new r2ui
reaches it through a Dependabot PR and the next release.

## When something fails

- A check fails (wrong version, not on main, no changelog section): nothing was published. Fix it
  on main, move the tag (`git tag -f vX.Y.Z <commit> && git push -f origin vX.Y.Z`) or delete it
  (`git push origin :refs/tags/vX.Y.Z`) and tag again.
- Build or credentials fail before "Push the gem to RubyGems": re-run the failed job.
- It fails after the gem is on RubyGems: re-running stops at the "already on RubyGems" check by
  design. Create the release by hand: `gem build spacemap.gemspec`, then
  `gh release create vX.Y.Z spacemap-X.Y.Z.gem --verify-tag --title "spacemap X.Y.Z" --notes-file <notes>`.
- A version on RubyGems can't be replaced: fix forward with `X.Y.(Z+1)`.

## One-time setup (owner)

1. spacemap doesn't exist on RubyGems yet, so add a *pending* trusted publisher: rubygems.org →
   your profile → Trusted publishers → Create (pending trusted publisher): gem name `spacemap`,
   GitHub Actions, repository owner `satoramoto`, repository name `spacemap`, workflow filename
   `publish.yml`, environment `release`. The first publish creates the gem and turns it into a
   normal trusted publisher.
2. For the Homebrew update: create a fine-grained token with Contents read/write on
   `satoramoto/homebrew-tap` only (prefilled; under "Repository access" pick *Only select
   repositories* → `homebrew-tap`, which the link can't preselect):

   https://github.com/settings/personal-access-tokens/new?name=spacemap-homebrew-tap&description=Lets+satoramoto%2Fspacemap%27s+homebrew.yml+push+Formula%2Fspacemap.rb+to+satoramoto%2Fhomebrew-tap&target_name=satoramoto&expires_in=365&contents=write

   Then add it to this repo as the Actions secret `TAP_TOKEN` (paste the token when asked):

   ```
   gh secret set TAP_TOKEN --repo satoramoto/spacemap
   ```
3. The GitHub environment `release` is created on first use; add required reviewers to it to
   approve each publish. If you restrict its deployment refs, allow tags `v*.*.*`.
