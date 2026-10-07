# frozen_string_literal: true

require "etc"

module Spacemap
  # One file or folder in the scanned tree. Folders hold their whole subtree's size and file count,
  # kept up to date while the scan runs. Equality and hash are identity: a node is a place in the
  # tree, and hashing its members would walk its parent chain.
  Node = Struct.new(:name, :parent, :dir, :size, :files, :kind, :children) do
    def dir? = dir
    def hash = object_id.hash
    def ==(other) = equal?(other)
    alias_method :eql?, :==

    # The root's name is its full path, so a path is the names from the root down.
    def path = @path ||= parent ? File.join(parent.path, name) : name

    # The folder and its ancestors up to the root, outermost first.
    def ancestors
      chain = []
      node = self
      chain.unshift(node) while (node = node.parent)
      chain
    end

    def inspect = "#<Spacemap::Node #{path}>"
  end

  # Kinds by total size, with the treemap colour of each.
  Kind = Data.define(:name, :bytes, :files, :color)

  # Disk Inventory X-like hues, given to kinds by total size; the rest are grey.
  PALETTE = [
    [70, 130, 220], [220, 70, 70], [80, 180, 80], [230, 180, 40], [170, 90, 200], [50, 190, 190],
    [240, 130, 50], [200, 90, 150], [140, 160, 60], [110, 110, 220], [180, 120, 80], [90, 160, 130]
  ].freeze
  OTHER = [120, 120, 120].freeze
  FOLDER = [85, 85, 85].freeze

  # Walks a folder with a pool of Ractors (each lists and lstats whole folders in parallel; plain
  # threads would share one lock) and builds the tree on the scanner's own thread as their results
  # come back. Readers see the live tree; `snapshot` adds the kinds and a generation that changes
  # every PUBLISH seconds while the scan runs, for caches. Symlinks are skipped and the walk stays
  # on the root's volume, like Disk Inventory X.
  class Scanner
    PUBLISH = 0.25
    BATCH = 32 # folders per message to a walker
    # SPACEMAP_WORKERS overrides how many Ractors walk the disk (0: the scanner's thread alone).
    WORKERS = Integer(ENV.fetch("SPACEMAP_WORKERS", [Etc.nprocessors, 8].min))
    # `cloud_*`: files whose content isn't on this disk (online-only Google Drive, iCloud and
    # Dropbox placeholders): they report a size but have no blocks allocated.
    # macOS stores tiny files compressed in their metadata, so they also report 0 blocks; only
    # zero-block files bigger than this count as cloud placeholders.
    CLOUD_MIN = 4096
    # `sizes`: the scanner's size mode (:disk or :logical).
    Snapshot = Data.define(:root, :generation, :kinds, :colors, :cloud_files, :cloud_bytes, :sizes, :done,
                           :seconds, :errors, :error)

    attr_reader :root

    # `workers`: how many Ractors walk the disk; 0 walks on the scanner's thread alone.
    # `sizes`: :disk counts the space a file takes on disk (its allocated blocks, as `du` does), so
    # online-only cloud files count as nothing; :logical counts the size each file reports.
    def initialize(root, workers: WORKERS, sizes: :disk)
      @workers = workers
      @sizes = sizes
      @cloud = [0, 0]
      @path = Scanner.utf8(File.expand_path(root))
      @root = Node.new(@path, nil, true, 0, 0, nil, [])
      @lock = Mutex.new
      @kinds = Hash.new { |h, k| h[k] = [0, 0] }
      @generation = 0
      @snapshot = snap(false, 0.0, 0, nil)
    end

    def snapshot = @lock.synchronize { @snapshot }

    # Scans on a thread of its own; readers follow along through `snapshot`.
    def start
      @thread ||= Thread.new { scan }
      self
    end

    # Waits for a started scan to finish (scans here if none was started). Returns the done snapshot.
    def wait
      @thread ? @thread.join : scan
      snapshot
    end

    # Scans in the calling thread (tests, snapshots). If the root can't be read, publishes a done
    # snapshot carrying the error.
    def scan
      started = clock
      device = File.lstat(@path).dev
      errors = @workers.positive? ? walk_parallel(device, started) : walk_inline(device, started)
      publish(true, clock - started, errors)
    rescue StandardError => e
      publish(true, 0.0, 1, e.message)
    end

    # Lists folders: for each [id, path], [id, path, [name, bytes on disk, bytes, dir?, ...]] (nil if
    # unreadable). Runs inside the walkers, so it touches nothing but its arguments.
    def self.list(work, device)
      work.map do |id, dir|
        flat = []
        begin
          Dir.each_child(dir) do |name|
            name = Scanner.utf8(name)
            st = File.lstat(File.join(dir, name))
            if st.file? then flat.push(name, st.blocks * 512, st.size, false)
            elsif st.directory? && st.dev == device then flat.push(name, 0, 0, true)
            end
          rescue SystemCallError
            next
          end
          [id, dir, flat]
        rescue SystemCallError
          [id, dir, nil]
        end
      end
    end

    # Names and paths are UTF-8 whatever the locale (without one, Ruby reads them as US-ASCII or
    # binary, and joining them with UTF-8 text fails). Same bytes, so the file system still finds
    # them; names that aren't valid UTF-8 are scrubbed only where they are shown.
    def self.utf8(text) = text.encoding == Encoding::UTF_8 ? text : text.dup.force_encoding(Encoding::UTF_8)

    private

    def walk_inline(device, started)
      @dirs = [@root]
      pending = [[0, @path]]
      errors = 0
      published = started
      until pending.empty?
        errors += add(Scanner.list([pending.pop], device), pending)
        published = maybe_publish(published, started, errors)
      end
      errors
    end

    def walk_parallel(device, started)
      Warning[:experimental] = false # Ractor's "experimental" notice would land on the dashboard
      @dirs = [@root]
      pending = [[0, @path]]
      inbox, workers = start_workers(device)
      inflight = Array.new(workers.size, 0)
      errors = 0
      published = started
      loop do
        workers.each_index do |i|
          while inflight[i] < 2 && !pending.empty?
            workers[i].send(pending.pop(BATCH))
            inflight[i] += 1
          end
        end
        break if inflight.sum.zero?

        i, results = inbox.call
        inflight[i] -= 1
        errors += add(results, pending)
        published = maybe_publish(published, started, errors)
      end
      errors
    ensure
      workers&.each do |w|
        w.send(:stop)
      rescue StandardError
        nil # a dead worker can't take :stop; the rest still must
      end
    end

    # Ractor::Port on Ruby 3.5+, Ractor.yield/select before it.
    def start_workers(device)
      count = @workers
      if defined?(Ractor::Port)
        port = Ractor::Port.new
        workers = Array.new(count) do |i|
          Ractor.new(port, i, device) do |out, me, dev|
            while (work = Ractor.receive) != :stop
              out << [me, Spacemap::Scanner.list(work, dev)]
            end
          end
        end
        [-> { port.receive }, workers]
      else
        workers = Array.new(count) do |i|
          Ractor.new(i, device) do |me, dev|
            while (work = Ractor.receive) != :stop
              Ractor.yield [me, Spacemap::Scanner.list(work, dev)]
            end
          end
        end
        [-> { Ractor.select(*workers).last }, workers]
      end
    end

    # Adds listed folders' contents to the tree and their subfolders to `pending`. Returns how many
    # folders couldn't be read.
    def add(results, pending)
      errors = 0
      results.each do |id, dir_path, flat|
        dir = @dirs[id]
        if flat.nil?
          errors += 1
          next
        end

        bytes = 0
        files = 0
        kids = dir.children
        flat.each_slice(4) do |name, on_disk, logical, is_dir|
          if is_dir
            child = Node.new(name, dir, true, 0, 0, nil, [])
            @dirs << child
            pending << [@dirs.size - 1, File.join(dir_path, name)]
          else
            if on_disk.zero? && logical > CLOUD_MIN # a placeholder: its content is in the cloud
              @cloud[0] += 1
              @cloud[1] += logical
            end
            size = @sizes == :disk ? on_disk : logical
            kind = -Spacemap.kind(name)
            child = Node.new(name, dir, false, size, 1, kind, nil)
            totals = @kinds[kind]
            totals[0] += size
            totals[1] += 1
            bytes += size
            files += 1
          end
          kids << child
        end
        node = dir
        while node
          node.size += bytes
          node.files += files
          node = node.parent
        end
      end
      errors
    end

    def maybe_publish(published, started, errors)
      now = clock
      return published if now - published < PUBLISH

      publish(false, now - started, errors)
      now
    end

    def publish(done, seconds, errors, error = nil)
      @dirs = nil if done
      @generation += 1
      s = snap(done, seconds, errors, error)
      @lock.synchronize { @snapshot = s }
    end

    def snap(done, seconds, errors, error)
      kinds = @kinds.sort_by { |_, (bytes, _)| -bytes }.each_with_index.map do |(name, (bytes, files)), i|
        Kind.new(name:, bytes:, files:, color: PALETTE.fetch(i, OTHER))
      end
      Snapshot.new(root: @root, generation: @generation, kinds:, colors: kinds.to_h { |k| [k.name, k.color] },
                   cloud_files: @cloud[0], cloud_bytes: @cloud[1], sizes: @sizes, done:, seconds:, errors:, error:)
    end

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # A file's kind: its lowercased extension, or "(none)".
  def self.kind(name)
    ext = File.extname(name)
    ext.empty? || ext == name ? "(none)" : ext.delete_prefix(".").downcase
  end

  # A folder's children with something in them, largest first. Sorting a big folder is costly, so
  # each reader keeps a cache per scan generation.
  class Children
    def initialize = @cache = {}.compare_by_identity

    def of(node, generation)
      return [] unless node.dir?

      @cache.clear if generation != @generation
      @generation = generation
      @cache[node] ||= node.children.select { |k| k.size.positive? }.sort_by! { |k| -k.size }
    end
  end
end
