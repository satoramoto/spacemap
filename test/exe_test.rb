# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# exe/spacemap as a real process with stdout piped, the way `brew test` runs it.
class ExeTest < Minitest::Test
  include FolderFixture

  EXE = File.expand_path("../exe/spacemap", __dir__)

  # No locale, as under `brew test`, launchd or `env -i`: Ruby's default encoding is then US-ASCII.
  def spacemap(*args)
    env = { "COLUMNS" => "120", "LINES" => "36", "LANG" => nil, "LC_ALL" => nil, "LC_CTYPE" => nil }
    Open3.capture3(env, RbConfig.ruby, EXE, *args, stdin_data: "").then do |out, err, status|
      [out.force_encoding(Encoding::UTF_8), err.force_encoding(Encoding::UTF_8), status]
    end
  end

  def test_version
    out, _err, status = spacemap("--version")

    assert_equal 0, status.exitstatus
    assert_equal "spacemap #{Spacemap::VERSION}\n", out
  end

  def test_piped_it_waits_for_the_scan_and_prints_one_plain_frame
    write("日本.txt", 500)
    out, err, status = spacemap(@dir, "--logical")

    assert_equal 0, status.exitstatus, err
    refute_includes out, "\e", "plain text"
    assert_match(/Treemap/, out)
    assert_match(/big\.mov/, out)
    assert_match(/日本\.txt/, out, "UTF-8 names without a UTF-8 locale")
    assert_match(/in 6 files/, out)
    refute_match(/Scanning/, out, "the scan finished first")
  end

  def test_a_missing_folder_is_an_error
    _out, err, status = spacemap(File.join(@dir, "missing"))

    assert_equal 1, status.exitstatus
    assert_match(/isn't a folder/, err)
  end
end
