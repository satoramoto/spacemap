# frozen_string_literal: true

require "r2ui"
require "r2ui/cli"

require_relative "spacemap/version"
require_relative "spacemap/scanner"
require_relative "spacemap/treemap"
require_relative "spacemap/dashboard"
require_relative "spacemap/program"

# spacemap: where the space in a folder went, in the terminal. Scanner walks the folder (Ractors)
# into a tree of Nodes; Treemap lays a folder out in cells; Dashboard is the r2ui dashboard (tree,
# kinds legend, treemap); Program is the `spacemap` command line.
module Spacemap
end
