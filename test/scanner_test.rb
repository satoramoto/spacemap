# frozen_string_literal: true

require "test_helper"

# The scanner and the tree it builds.
class ScannerTest < Minitest::Test
  include FolderFixture

  def test_scan_finds_files_and_folders_but_not_symlinks
    assert @snap.done
    assert_equal %w[big.mov notes.txt src src/a.rb src/b.rb src/deep src/deep/c.rb], names(@snap.root)
    assert_equal File.join(@dir, "src/deep/c.rb"), find(@snap.root, "src/deep/c.rb").path
  end

  def test_the_walkers_and_the_inline_walk_build_the_same_tree
    inline = scan(workers: 0)

    assert_equal names(@snap.root), names(inline.root)
    assert_equal @snap.root.size, inline.root.size
  end

  def test_folders_sum_their_subtrees_and_kinds_rank_by_size
    root = @snap.root

    assert_equal [10_000, 5], [root.size, root.files]
    assert_equal [3000, 3], [find(root, "src").size, find(root, "src").files]
    assert_equal %w[mov rb txt], @snap.kinds.map(&:name)
    assert_equal [3000, 3], [@snap.kinds[1].bytes, @snap.kinds[1].files]
    assert_equal [root, find(root, "src"), find(root, "src/deep")], find(root, "src/deep/c.rb").ancestors
  end

  # A sparse file reports a size with no blocks allocated, like an online-only cloud file.
  def test_disk_sizes_count_cloud_only_files_as_nothing
    File.open(File.join(@dir, "drive.mov"), "w") { |f| f.truncate(50_000_000) }
    skip "this file system allocates blocks for sparse files" unless File.lstat(File.join(@dir, "drive.mov")).blocks.zero?

    disk = scan(sizes: :disk)
    logical = scan

    assert_equal 0, find(disk.root, "drive.mov").size
    assert_operator disk.root.size, :<, 1_000_000, "the real files only, rounded up to blocks"
    assert_equal [1, 50_000_000], [disk.cloud_files, disk.cloud_bytes]
    assert_equal 50_010_000, logical.root.size
    assert_equal [1, 50_000_000], [logical.cloud_files, logical.cloud_bytes]
    assert_equal %i[disk logical], [disk.sizes, logical.sizes]
  end

  # macOS compresses tiny files into their metadata, so they report 0 blocks too; they aren't cloud files.
  def test_small_zero_block_files_are_not_cloud_only
    path = File.join(@dir, "tiny.dat")
    File.open(path, "w") { |f| f.truncate(Spacemap::Scanner::CLOUD_MIN) }
    skip "this file system allocates blocks for sparse files" unless File.lstat(path).blocks.zero?

    snap = scan(sizes: :disk)

    assert_equal [0, 0], [snap.cloud_files, snap.cloud_bytes]
  end

  def test_scanning_a_missing_folder_gives_a_done_snapshot_with_an_error
    snap = scan(File.join(@dir, "missing"))

    assert snap.done
    assert_match(/No such file/, snap.error)
  end

  def test_wait_returns_the_done_snapshot_of_a_started_scan
    scanner = Spacemap::Scanner.new(@dir, workers: 2, sizes: :logical).start
    snap = scanner.wait

    assert snap.done
    assert_equal 10_000, snap.root.size
  end
end
