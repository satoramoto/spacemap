# frozen_string_literal: true

source "https://rubygems.org"

# The runtime dependency (r2ui) comes from spacemap.gemspec, from RubyGems: spacemap builds on
# released r2ui versions only, and Dependabot proposes new ones.
gemspec

# To try an unreleased r2ui locally: R2UI_PATH=../r2ui bundle exec rake test
gem "r2ui", path: ENV["R2UI_PATH"] if ENV["R2UI_PATH"]

gem "minitest", "~> 5.25"
gem "rake", "~> 13.0"
