# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "spacemap"

# A small folder to scan, made fresh for each test:
#   big.mov 6000, notes.txt 1000, src/a.rb 2000, src/b.rb 1000, src/deep/c.rb 0, link.mov -> big.mov
module FolderFixture
  def setup
    @dir = Dir.mktmpdir("spacemap")
    write("big.mov", 6000)
    write("notes.txt", 1000)
    write("src/a.rb", 2000)
    write("src/b.rb", 1000)
    write("src/deep/c.rb", 0)
    File.symlink(File.join(@dir, "big.mov"), File.join(@dir, "link.mov"))
    @snap = scan
  end

  def teardown = FileUtils.remove_entry(@dir)

  def write(name, bytes)
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "x" * bytes)
  end

  # Logical sizes by default, so the numbers don't depend on the file system's block size.
  def scan(dir = @dir, workers: 2, sizes: :logical)
    scanner = Spacemap::Scanner.new(dir, workers:, sizes:)
    scanner.scan
    scanner.snapshot
  end

  def find(node, rel) = rel.split("/").reduce(node) { |n, name| n.children.find { |k| k.name == name } }
  def names(node) = node.children.to_a.flat_map { |k| [k.name, *names(k).map { |n| "#{k.name}/#{n}" }] }.sort
  def treemap(snap, width, height) = Spacemap::Treemap.new(snap.root, width, height, colors: snap.colors)
  def plain(text) = text.gsub(/\e\[[0-9;]*m/, "")
end
