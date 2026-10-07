# spacemap

Where the space in a folder went, in your terminal: a tree by size, a treemap coloured by file kind and a legend of the kinds that take the most space, like Disk Inventory X.

## Install

With Homebrew (brings its own Ruby):

```
brew install satoramoto/tap/spacemap
```

Or as a gem:

```
gem install spacemap
```

Requirements: macOS or Linux; the gem needs Ruby 3.3 or newer. On Linux, `o`, `O` and right-click use `xdg-open`.

## Usage

```
spacemap                  # the current folder
spacemap ~/Downloads      # another folder
spacemap --logical        # count the size each file reports, not the space on disk
spacemap ~/src | cat      # waits for the scan, prints one plain frame
spacemap --help           # every option
```

The tree fills in while the scan runs. In the dashboard:

| Key / mouse | Does |
|---|---|
| ↑ ↓ | Move in the tree |
| Enter / Space | Unfolds or folds the selected folder |
| click on the treemap | Selects that file in the tree, unfolding its folders |
| right-click on the treemap | Selects it and shows it in Finder (Linux: opens its folder) |
| `+` / `-` | Zooms the treemap into the selected folder, and back out |
| `o` | Shows the selection in Finder (Linux: opens its folder) |
| `O` | Opens the selection (a folder in Finder, a file in its app) |
| `/` | Searches the lines the tree has unfolded |
| `q` | Quits |

Sizes are space on disk (allocated blocks, as `du` shows), so online-only iCloud, Google Drive and Dropbox files count as nothing; the Kinds panel says how many there are and how much they would be. `--logical` counts them. Symlinks are skipped and the scan stays on the folder's volume. `SPACEMAP_WORKERS` sets how many Ractors scan (default: the number of CPUs, at most 8; 0 scans on one thread).

## Development

spacemap is built on [r2ui](https://github.com/satoramoto/r2ui), from RubyGems.

```
bundle install
bundle exec rake test
bundle exec exe/spacemap
```

See [AGENTS.md](AGENTS.md) for targeted tests and [docs/releasing.md](docs/releasing.md) for releases.

## License

MIT, see [LICENSE.txt](LICENSE.txt).
