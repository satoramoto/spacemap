# frozen_string_literal: true

require "set"

module Spacemap
  # The dashboard: where the space in a folder went, as a tree, a treemap and file kinds.
  #
  # The tree fills in while the scan runs. Selecting a line outlines it in the treemap; clicking the
  # treemap selects that file in the tree. + zooms the treemap into the selected folder, - zooms out.
  # o shows the selection in Finder (so does a right-click on the treemap); O opens it (a folder in
  # Finder, a file in its app). On Linux both go through xdg-open: o opens the folder the selection
  # is in, O the selection itself. Search (/) looks through the lines the tree has unfolded.
  #
  # Sizes are space on disk (allocated blocks, as `du` shows), so online-only Google Drive, iCloud and
  # Dropbox files count as nothing; the Kinds panel says how many there are. `sizes: :logical`
  # (`spacemap --logical`) counts the size each file reports instead.
  module Dashboard
    RIGHT_BUTTON = 2 # the terminal's SGR button number, which Bubbletea 0.1.4 passes through
    MACOS = RUBY_PLATFORM.include?("darwin")
    FILE_MANAGER = MACOS ? "Finder" : "file manager"

    # A tree line: a file, or a folder with its whole subtree's size and file count.
    Line = Data.define(:path, :parent, :name, :size, :files, :kind, :node)

    SCANNER_LOCK = Mutex.new
    TREEMAP_LOCK = Mutex.new

    module_function

    # Which folder to scan and how; forgets any earlier scan, tree and treemap.
    def configure(root, sizes: :disk, workers: Scanner::WORKERS)
      SCANNER_LOCK.synchronize do
        @root = Scanner.utf8(File.expand_path(root))
        @sizes = sizes
        @workers = workers
        @scanner = @rows = @synced = @seen = @announced = @zoom = nil
      end
      TREEMAP_LOCK.synchronize { @treemap = @treemap_key = @treemap_lines = @children = nil }
      self
    end

    def root = @root || configure(Dir.pwd).root

    # Configures the scan and registers the resource and dashboard with R2UI.
    def install(root, sizes: :disk, workers: Scanner::WORKERS)
      configure(root, sizes:, workers:)
      define_resource
      define_dashboard
    end

    # Exactly one scanner, whichever thread (feed or update) asks first.
    def scanner
      @scanner || SCANNER_LOCK.synchronize do
        @scanner ||= Scanner.new(root, workers: @workers || Scanner::WORKERS, sizes: @sizes || :disk).start
      end
    end

    def panel(app, name) = app.dashboard.panels.find { |p| p.name == name }

    # The tree's rows. A big scan has far too many rows to hand the table every frame, so it gets
    # the unfolded folders' contents only, plus one level more so folded folders can unfold at once.
    # Built on the update thread by `sync`; before that (a snapshot), with everything folded.
    def rows = @rows || visible(scanner.root, Set.new, Set.new)

    def visible(root, collapsed, seen)
      lines = [line(root)]
      open = [root]
      while (dir = open.pop)
        dir.children.each do |node|
          lines << line(node)
          next unless node.dir? && !node.children.empty?

          collapsed << node.path if seen.add?(node.path) # new folders start folded
          if collapsed.include?(node.path)
            node.children.each { |kid| lines << line(kid) }
          else
            open << node
          end
        end
      end
      lines
    end

    def line(node)
      Line.new(path: node.path, parent: node.parent&.path, name: File.basename(node.name).scrub("?"), size: node.size,
               files: node.files, kind: node.kind, node:)
    end

    # Runs on a timer: rebuilds the rows when the scan publishes or a folder (un)folds.
    def sync(ctx)
      snap = scanner.snapshot
      collapsed = ctx.app.panel_state(panel(ctx.app, :file)).collapsed
      return if [snap.generation, collapsed.hash] == @synced

      @seen ||= Set.new
      @rows = visible(snap.root, collapsed, @seen).freeze
      @synced = [snap.generation, collapsed.hash]
      ctx.refresh(:file)
      return unless snap.done && !@announced

      @announced = true
      ctx.flash "Scanned #{snap.root.files} files in #{snap.seconds.round(1)}s"
    end

    # The node on the tree's selected line.
    def selected(app)
      tree = panel(app, :file)
      app.panel_lines(tree)[app.panel_state(tree).selected]&.rows&.first&.node
    end

    def zoom_root = @zoom || scanner.root

    def zoom_in(app)
      node = selected(app) or return
      @zoom = node.dir? ? node : node.parent
    end

    def zoom_out
      @zoom = zoom_root.parent
    end

    # The treemap is laid out once per scan generation, zoom and size; each frame only outlines the
    # selection. Locked: the renderer calls this, and so does the mouse extension (on the update
    # thread) when it measures the panel.
    def treemap_view(app, width, height)
      sel = selected(app)
      TREEMAP_LOCK.synchronize do
        snap = scanner.snapshot
        key = [snap.generation, zoom_root.object_id, width, height]
        if key != @treemap_key
          @children ||= Children.new
          @treemap = Treemap.new(zoom_root, width, height, colors: snap.colors, children: @children,
                                                           generation: snap.generation)
          @treemap_key = key
          @treemap_lines = nil
        end
        cached = @treemap_lines
        return cached.last if cached && cached.first.equal?(sel)

        text = @treemap.lines(sel).join("\n")
        @treemap_lines = [sel, text]
        text
      end
    end

    # A click on the treemap selects that file in the tree, unfolding its folders; a right-click
    # also shows it in the file manager.
    def click(ctx, msg)
      app = ctx.app
      rect = app.panel_rects[panel(app, :treemap)]&.inner
      node = rect && TREEMAP_LOCK.synchronize { @treemap&.at(msg.x - rect.x, msg.y - rect.y) } or return
      select(ctx, node)
      reveal(ctx, node) if msg.button == RIGHT_BUTTON
    end

    def select(ctx, node)
      app = ctx.app
      state = app.panel_state(panel(app, :file))
      folders = node.ancestors.map(&:path)
      (@seen ||= Set.new).merge(folders) # so sync doesn't fold them as new
      folders.each { |path| state.collapsed.delete(path) }
      sync(ctx)
      lines = R2UI::Query.new(R2UI.registry.resource(:file), @rows, scope: state.scope, grouping: state.grouping,
                                                                     search: state.search, sort: state.sort,
                                                                     collapsed: state.collapsed).lines
      at = lines.index { |l| l.id == node.path }
      state.move(at - state.selected, lines.size) if at
    end

    # The command that shows (`:reveal`) or opens (`:open`) a path. macOS: `open -R` selects it in
    # Finder, `open` opens it. Elsewhere xdg-open: reveal opens the folder it is in.
    def open_command(action, path, macos: MACOS)
      if macos
        action == :reveal ? ["open", "-R", path] : ["open", path]
      else
        ["xdg-open", action == :reveal ? File.dirname(path) : path]
      end
    end

    def reveal(ctx, node) = node && run_open(ctx, open_command(:reveal, node.path))
    def open_node(ctx, node) = node && run_open(ctx, open_command(:open, node.path))

    def run_open(ctx, command)
      Process.detach(spawn(*command, %i[in out err] => File::NULL))
    rescue SystemCallError => e
      ctx.flash "Can't run #{command.first}: #{e.message}"
      nil
    end

    # Totals, then the kinds by total size, each with its treemap colour.
    def legend(width, height)
      snap = scanner.snapshot
      return "Can't scan #{scanner.root.path}: #{snap.error}"[0, width] if snap.error

      root = snap.root
      head = "#{snap.done ? "" : "Scanning… "}#{R2UI::Format.bytes(root.size)} in #{root.files} files"
      zoom = zoom_root.equal?(root) ? nil : "zoom: …#{zoom_root.path.delete_prefix(root.path)}"
      cloud = if snap.cloud_files.positive?
                "#{snap.cloud_files} cloud-only files (#{R2UI::Format.bytes(snap.cloud_bytes)}) " \
                  "#{snap.sizes == :disk ? "not counted" : "counted"}"
              end
      lines = [head, cloud, zoom].compact.flat_map { |l| wrap(l, width) }
      kinds = snap.kinds.first([height - lines.size, 0].max)
      lines.concat(kind_lines(kinds, width)).join("\n")
    end

    KIND_NAME = 4 # the fewest cells a kind's name gets

    # Swatch, name, size and file count. The count is dropped when the panel is too narrow for it,
    # and names get what's left.
    def kind_lines(kinds, width)
      sizes = kinds.map { |k| R2UI::Format.bytes(k.bytes) }
      size_w = sizes.map(&:length).max.to_i
      files_w = kinds.map { |k| k.files.to_s.length }.max.to_i
      fixed = 3 + 1 + size_w # swatch and a space; a space and the size
      show_files = width - fixed - 1 - files_w >= KIND_NAME + 2
      name_w = [width - fixed - (show_files ? 1 + files_w : 0), KIND_NAME].max
      kinds.zip(sizes).map do |k, size|
        name = k.name.length > name_w ? "#{k.name[0, name_w - 1]}…" : k.name.ljust(name_w)
        swatch = "\e[48;2;#{k.color.join(";")}m  \e[0m"
        "#{swatch} #{name} #{size.rjust(size_w)}#{show_files ? " #{k.files.to_s.rjust(files_w)}" : ""}"
      end
    end

    # Splits text into lines of at most `width` cells, at spaces where it can.
    def wrap(text, width)
      return [text] if width <= 0 || text.length <= width

      text.split(" ").each_with_object([+""]) do |word, out|
        word.scan(/.{1,#{width}}/).each do |part|
          if out.last.empty? then out.last << part
          elsif out.last.length + 1 + part.length <= width then out.last << " " << part
          else out << part.dup
          end
        end
      end
    end

    def define_resource
      R2UI.resource :file do
        source { Spacemap::Dashboard.rows }
        refresh every: 2
        key :path, parent: :parent

        group_by :folder, label: "Folders", tree: true

        index do
          column :name
          # Lines carry their subtree totals already, so the tree shows each line's own value.
          column :size, format: :bytes, aggregate: :own, sort: :desc
          column :files, format: :integer, aggregate: :own
          column :kind
        end

        filter :name, :kind
      end
    end

    def define_dashboard
      dash = self
      R2UI.dashboard do
        title "spacemap · #{dash.root}"
        mouse

        every(0.25) { dash.sync(self) }
        on_click { |msg, panel| dash.click(self, msg) if panel&.name == :treemap }
        on_key("+", "=", help: "zoom in") { dash.zoom_in(app) }
        on_key("-", help: "zoom out") { dash.zoom_out }
        on_key("o", help: "show in #{FILE_MANAGER}") { dash.reveal(self, dash.selected(app)) }
        on_key("O", help: "open") { dash.open_node(self, dash.selected(app)) }

        row height: 16 do
          panel :file, span: 3, title: "Files" do
            table group_by: :folder
          end
          panel :kinds, resource: nil, span: 1 do
            view { dash.legend(width, height) }
          end
        end

        row do
          panel :treemap, resource: nil, title: "Treemap (click: select · right-click: show in #{FILE_MANAGER})" do
            view { dash.treemap_view(app, width, height) }
          end
        end
      end
    end
  end
end
