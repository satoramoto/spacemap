# frozen_string_literal: true

require "test_helper"

# The squarified treemap layout and its drawing.
class TreemapTest < Minitest::Test
  include FolderFixture

  def test_treemap_gives_each_file_an_area_in_proportion_to_its_size
    map = treemap(@snap, 40, 10)
    counts = Hash.new(0)
    10.times { |y| 40.times { |x| counts[map.at(x, y)&.name] += 1 } }

    assert_equal 0, counts[nil], "every cell is filled"
    assert_in_delta 240, counts["big.mov"], 20
    assert_in_delta 80, counts["a.rb"], 20
    refute counts.key?("c.rb"), "empty files take no space"
  end

  def test_treemap_lays_out_a_folder_whose_size_lags_its_children_mid_scan
    root = Spacemap::Node.new("/r", nil, true, 0, 0, nil, [])
    root.children << Spacemap::Node.new("f.txt", root, false, 500, 1, "Text", nil)
    map = Spacemap::Treemap.new(root, 20, 6)

    assert(6.times.all? { |y| 20.times.all? { |x| map.at(x, y) } }, "every cell is filled")
  end

  def test_treemap_labels_never_write_escapes_or_wide_characters
    write("\e[31mred", 5000)
    write("日本.txt", 5000)
    lines = treemap(scan, 60, 12).lines

    lines.each do |l|
      text = plain(l)
      refute_includes text, "\e"
      assert_equal 60, R2UI::Compat::Tea::ANSI.string_width(text)
      assert_equal 60, text.length
    end
    assert(lines.any? { |l| l.include?("?[31mred") })
  end

  def test_treemap_outlines_the_selection_or_the_folder_it_is_drawn_in
    map = treemap(@snap, 40, 10)
    src = find(@snap.root, "src")
    rect = map.rect(src)

    refute_nil rect
    assert_equal rect, map.rect(find(src, "deep/c.rb")), "empty, so drawn as part of src"
    lines = map.lines(src).map { |l| plain(l) }

    assert_equal "┏", lines[rect[1]][rect[0]]
    refute_includes map.lines.join, "┏", "nothing selected, no outline"
  end
end
