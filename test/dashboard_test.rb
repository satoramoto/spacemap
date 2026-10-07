# frozen_string_literal: true

require "test_helper"

# The dashboard: its frame, the kinds legend and the file manager commands.
class DashboardTest < Minitest::Test
  include FolderFixture

  Dashboard = Spacemap::Dashboard

  def setup
    super
    R2UI.reset!
    Dashboard.install(@dir, sizes: :logical, workers: 0)
  end

  def teardown
    R2UI.reset!
    Dashboard.configure(Dir.pwd)
    super
  end

  def app = R2UI::App.new(R2UI.registry)

  # The first frame comes before the tree has a line to select.
  def test_the_dashboard_draws_before_anything_is_selected
    app = self.app

    assert_nil Dashboard.selected(app)
    assert_match(/Treemap/, app.frame(100, 30).plain_lines.join("\n"))
    assert_match(/Treemap/, app.frame(100, 30).plain_lines.join("\n"), "and again from the cache")
  end

  def test_a_finished_scan_shows_the_tree_and_the_totals
    Dashboard.scanner.wait
    frame = app.snapshot(width: 120, height: 36)

    assert_match(/big\.mov/, frame)
    assert_match(/in 5 files/, frame)
    refute_match(/Scanning/, frame)
  end

  def test_legend_lines_fit_a_narrow_panel
    kinds = [Spacemap::Kind.new(name: "plist", bytes: 27 * 2**20, files: 12_345, color: [1, 2, 3]),
             Spacemap::Kind.new(name: "(none)", bytes: 7 * 2**20, files: 3, color: [4, 5, 6])]
    lines = ->(width) { Dashboard.kind_lines(kinds, width).map { |l| plain(l) } }

    fits = lines.(20)
    assert_equal ["   plist   27M 12345", "   (none) 7.0M     3"], fits, "the count fits beside a 6-cell name"

    narrow = lines.(16)
    assert(narrow.all? { |l| l.length <= 16 }, narrow.inspect)
    refute_match(/12345/, narrow.join, "no room for the count")
    assert_match(/plist/, narrow.first)

    wide = lines.(40)
    assert(wide.all? { |l| l.length <= 40 })
    assert_match(/plist .* 12345\z/, wide.first)

    cloud = "2770 cloud-only files (180G) not counted"
    assert_equal ["2770 cloud-only files", "(180G) not counted"], Dashboard.wrap(cloud, 21)
    assert_equal [cloud], Dashboard.wrap(cloud, 80)
  end

  def test_finder_on_macos_and_xdg_open_on_the_folder_elsewhere
    file = File.join(@dir, "src/a.rb")

    assert_equal ["open", "-R", file], Dashboard.open_command(:reveal, file, macos: true)
    assert_equal ["open", file], Dashboard.open_command(:open, file, macos: true)
    assert_equal ["xdg-open", File.join(@dir, "src")], Dashboard.open_command(:reveal, file, macos: false)
    assert_equal ["xdg-open", file], Dashboard.open_command(:open, file, macos: false)
  end
end
