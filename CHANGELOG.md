# Changelog

## Unreleased

## 0.1.0

First release, from r2ui's Disk Inventory X example.

- `spacemap [FOLDER]`: where the space in a folder (default: the current one) went, as a tree by size, a squarified treemap coloured by file kind and a kinds legend. The tree fills in while a parallel scan (Ractors) runs; symlinks are skipped (a symlinked folder given as the root is followed), a file with several hard links counts once, and the scan stays on the folder's volume.
- Sizes are space on disk, so online-only iCloud, Google Drive and Dropbox files count as nothing; the legend says how many there are. `--logical` counts the size each file reports.
- Mouse: a click on the treemap selects that file in the tree; a right-click also shows it in Finder. `+`/`-` zoom the treemap into the selected folder and out; `o` shows the selection in Finder, `O` opens it. On Linux these use `xdg-open`.
- Off a terminal (`spacemap | cat`) it waits for the scan and prints one plain frame. `--version`, `--help`; `SPACEMAP_WORKERS` sets how many Ractors scan.
