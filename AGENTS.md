# spacemap

A terminal disk usage browser, like Disk Inventory X: a tree by size, a squarified treemap coloured by file kind and a kinds legend, for macOS and Linux. Built on [r2ui](https://github.com/satoramoto/r2ui) (the dashboard with `require "r2ui"`, the command line with `require "r2ui/cli"`), as a real consumer of that library: if r2ui gets in the way, say so in your result.

## Layout

- `lib/spacemap/scanner.rb` — `Scanner` walks a folder with a pool of Ractors into a tree of `Node`s; `snapshot` gives readers the kinds, cloud-only totals and a generation for caches.
- `lib/spacemap/treemap.rb` — `Treemap` lays one folder out in terminal cells and draws it (ANSI lines, the selection outlined).
- `lib/spacemap/dashboard.rb` — `Dashboard`, the r2ui resource and dashboard: tree rows, sync, legend, treemap view, mouse, zoom and Finder / xdg-open actions. `install(root, sizes:)` registers them.
- `lib/spacemap/program.rb` + `exe/spacemap` — the command line (`R2UI.cli`): on a terminal the dashboard, off one a plain frame after the scan.

## Tests

| Command | When |
|---|---|
| `bundle exec rake test` | After any change; CI runs it on macOS and Linux |
| `bundle exec ruby -Itest -Ilib test/<file>_test.rb` | Targeted: one file (`test/<file>_test.rb` for `lib/spacemap/<file>.rb`; `exe_test.rb` runs `exe/spacemap`) |
| `COLUMNS=140 LINES=45 bundle exec exe/spacemap <folder> \| cat` | After changing the dashboard or drawing: prints one real frame (plain, no terminal needed) |

Tests scan a temporary folder (`test/test_helper.rb`), with logical sizes so they don't depend on the file system's block size. The interactive dashboard needs a terminal; tests drive it through `R2UI::App` (`app.frame`, `app.snapshot`).

CI (`.github/workflows/ci.yml`: macOS and Linux on Ruby 3.4, Linux on Ruby 3.3) is the final check.

spacemap builds on released r2ui only: the gemspec's `r2ui ~> 0.2.0` from RubyGems, in CI and locally. A new r2ui minor arrives as a Dependabot PR; taking it is spacemap's call. To try an unreleased r2ui locally, set `R2UI_PATH` (`R2UI_PATH=../r2ui bundle exec rake test`), but don't merge code that needs it. Don't change r2ui from this repo; report what you need from it.

## Releasing

Agents never tag or publish: a pushed `vX.Y.Z` tag publishes the gem (`.github/workflows/publish.yml`), and only the owner pushes one. Put user-facing changes under `## Unreleased` in CHANGELOG.md, in the PR that makes them. The steps are in `docs/releasing.md`.

## Review checklist

Reviewers flag only real bugs and these rules, never style:
- Wrong sizes: disk vs logical bytes, a file counted twice, symlinks followed, the scan leaving the root's volume.
- Work per frame that should be per scan generation (layout, sorting a big folder).
- State shared between the update thread, the renderer and the scanner without its lock.
- Terminal state not restored on every exit path.
- Behaviour that only works on macOS where Linux is supported.
