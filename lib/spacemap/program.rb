# frozen_string_literal: true

module Spacemap
  # The `spacemap [FOLDER]` command line, an r2ui CLI program. On a terminal it opens the
  # dashboard while the scan runs; off one (a pipe, `brew test`) it waits for the scan and prints
  # one plain frame.
  module Program
    module_function

    def build
      R2UI.cli("spacemap") do
        version Spacemap::VERSION
        summary "Where the space in a folder went: a tree, a treemap and file kinds"
        description <<~TEXT.chomp
          Scans FOLDER (default: the current folder) and shows its files as a tree by size, a
          treemap and the file kinds that take the most space. Sizes are space on disk, so
          online-only cloud files (iCloud, Google Drive, Dropbox) count as nothing; --logical
          counts the size each file reports. Off a terminal it waits for the scan and prints one
          frame. SPACEMAP_WORKERS sets how many Ractors scan (0: one thread).
        TEXT

        argument :folder, default: ".", desc: "The folder to scan"
        flag :logical, desc: "Count the size each file reports instead of the space it takes on disk"

        run do
          root = File.expand_path(args[:folder])
          abort!("#{args[:folder]} isn't a folder") unless File.directory?(root)

          Spacemap::Dashboard.install(root, sizes: options[:logical] ? :logical : :disk)
          Spacemap::Dashboard.scanner.wait unless shell.interactive?
          dashboard
        end
      end
    end

    def start(argv = ARGV) = build.start(argv)
  end
end
