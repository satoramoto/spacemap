# frozen_string_literal: true

require_relative "lib/spacemap/version"

# A plain `ruby` platform gem: spacemap is pure Ruby (no native extension), and runs on macOS and
# Linux. Its one runtime dependency is r2ui, which has none of its own.
Gem::Specification.new do |spec|
  spec.name = "spacemap"
  spec.version = Spacemap::VERSION
  spec.authors = ["Ryan Gavin"]
  spec.email = ["ryan.michael.gavin@gmail.com"]

  spec.summary = "Where the space in a folder went, as a treemap in your terminal"
  spec.description = "A Disk Inventory X-style disk usage browser for the terminal: a parallel scan of a folder, " \
                     "a tree by size, a squarified treemap coloured by file kind and a kinds legend, with mouse " \
                     "selection, zoom and file manager actions. Counts space on disk, so online-only cloud files " \
                     "count as nothing. macOS and Linux."
  spec.homepage = "https://github.com/satoramoto/spacemap"
  spec.license = "MIT"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["spacemap"]
  spec.require_paths = ["lib"]

  spec.add_dependency "r2ui", "~> 0.2.0" # a new r2ui minor arrives as a Dependabot PR
end
