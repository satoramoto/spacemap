# frozen_string_literal: true

module Spacemap
  # A squarified treemap (Bruls, Huizing, van Wijk) of one folder, drawn into terminal cells.
  # Build it once per scan generation and size; `lines` is cheap enough for every frame.
  class Treemap
    Box = Data.define(:node, :x, :y, :w, :h, :leaf, :style)
    ASPECT = 2.0 # a cell is about twice as tall as it is wide
    TINY = ASPECT / 8 # layout area of an eighth of a cell
    LABEL = "38;2;20;20;20"
    OUTLINE = "1;38;2;255;255;255"

    attr_reader :width, :height, :boxes

    # `colors`: kind name => [r, g, b]; `children`: a Spacemap::Children cache.
    def initialize(root, width, height, colors: {}, children: Children.new, generation: 0)
      @colors = colors
      @children = children
      @generation = generation
      @width = width
      @height = height
      @boxes = []
      @by_node = {}.compare_by_identity
      @cells = Array.new([height, 0].max) { Array.new([width, 0].max) }
      return if width <= 0 || height <= 0 || total(root, @children.of(root, generation)).zero?

      place(root, 0.0, 0.0, width.to_f, height * ASPECT)
      @base = render_base
    end

    # The file (or folder too small to split) drawn at cell x, y.
    def at(x, y) = (0...@width).cover?(x) && (0...@height).cover?(y) ? @cells[y][x]&.node : nil

    # The cell rectangle [x, y, w, h] where `node` was drawn (or its nearest drawn folder), or nil.
    def rect(node)
      box = drawn(node)
      box && [box.x, box.y, box.w, box.h]
    end

    # The box for `node`, or for its nearest drawn ancestor (small files merge into their folder).
    def drawn(node)
      node = node.parent while node && !@by_node.key?(node)
      node && @by_node[node]
    end

    # ANSI lines: each kind's colour, shaded so neighbours stay apart, names where they fit, and
    # `selected` (a node) outlined.
    def lines(selected = nil)
      return Array.new([@height, 0].max, "") unless @base

      chars, fg = @base
      if (box = selected && drawn(selected))
        chars = chars.map(&:dup)
        fg = fg.map(&:dup)
        outline(box, chars, fg)
      end
      @cells.each_with_index.map do |row, y|
        line = +""
        last = nil
        crow = chars[y]
        frow = fg[y]
        row.each_with_index do |box, x|
          style = box ? (frow[x] ? "#{box.style};#{frow[x]}" : box.style) : "0"
          line << "\e[0m\e[" << style << "m" unless style == last
          last = style
          line << crow[x]
        end
        line << "\e[0m"
      end
    end

    private

    def place(node, x, y, w, h)
      cx, cy, cw, ch = cell_rect(x, y, w, h)
      return if cw <= 0 || ch <= 0

      kids = cw < 2 || ch < 2 ? [] : @children.of(node, @generation)
      kids = [] if total(node, kids).zero?
      box = Box.new(node:, x: cx, y: cy, w: cw, h: ch, leaf: kids.empty?, style: style(node, @boxes.size.odd?))
      @boxes << box
      @by_node[node] = box
      return cover(box) if box.leaf

      squarify(node, kids, x, y, w, h, total(node, kids).to_f)
    end

    # Mid-scan a folder's own size can lag its children's (a file's size lands before its
    # ancestors' are bumped), so lay out by whichever is larger.
    def total(node, kids) = [node.size, kids.sum(&:size)].max

    def cover(box)
      box.h.times { |dy| row = @cells[box.y + dy]; box.w.times { |dx| row[box.x + dx] = box } }
    end

    # Lays `kids` (largest first) out in rows along the shorter side, keeping each row's
    # rectangles as square as possible. Files smaller than a fraction of a cell aren't laid out one
    # by one: the space they share is drawn as their folder.
    def squarify(parent, kids, x, y, w, h, total)
      scale = w * h / total
      i = 0
      while i < kids.size
        if kids[i].size * scale < TINY
          fill(parent, x, y, w, h)
          return
        end

        side = [w, h].min
        sum = min = max = kids[i].size * scale
        j = i + 1
        while j < kids.size
          a = kids[j].size * scale
          break if worst(sum + a, [min, a].min, max, side) > worst(sum, min, max, side)

          sum += a
          min = a if a < min
          j += 1
        end
        # The last row and the last rectangle in each take whatever is left, so float error can't
        # leave a gap of unfilled cells along the parent's edge.
        last = j == kids.size
        if w >= h # a column on the left
          cw = last ? w : sum / h
          oy = y
          (i...j).each do |k|
            kh = k == j - 1 ? y + h - oy : kids[k].size * scale / cw
            place(kids[k], x, oy, cw, kh)
            oy += kh
          end
          x += cw
          w -= cw
        else # a row along the top
          rh = last ? h : sum / w
          ox = x
          (i...j).each do |k|
            kw = k == j - 1 ? x + w - ox : kids[k].size * scale / rh
            place(kids[k], ox, y, kw, rh)
            ox += kw
          end
          y += rh
          h -= rh
        end
        i = j
      end
    end

    def worst(sum, min, max, side)
      return Float::INFINITY if sum.zero? || side.zero?

      s2 = side * side
      [s2 * max / (sum * sum), sum * sum / (s2 * min)].max
    end

    # Draws the rest of a folder's space (its many small files) as the folder.
    def fill(node, x, y, w, h)
      cx, cy, cw, ch = cell_rect(x, y, w, h)
      cover(Box.new(node:, x: cx, y: cy, w: cw, h: ch, leaf: false, style: style(node, false))) if cw.positive? && ch.positive?
    end

    # Float layout space (height in ASPECT units) → whole cells, so neighbours share edges.
    def cell_rect(x, y, w, h)
      x0 = x.round.clamp(0, @width)
      x1 = (x + w).round.clamp(0, @width)
      y0 = (y / ASPECT).round.clamp(0, @height)
      y1 = ((y + h) / ASPECT).round.clamp(0, @height)
      [x0, y0, x1 - x0, y1 - y0]
    end

    def style(node, dark)
      r, g, b = node.dir? ? FOLDER : @colors.fetch(node.kind, OTHER)
      t = dark ? 0.78 : 1.0
      "48;2;#{(r * t).round};#{(g * t).round};#{(b * t).round}"
    end

    # Characters and foreground styles with every leaf's name written in.
    def render_base
      chars = Array.new(@height) { Array.new(@width, " ") }
      fg = Array.new(@height) { Array.new(@width) }
      @boxes.each { |b| label(b, chars, fg) if b.leaf }
      [chars, fg]
    end

    def label(box, chars, fg)
      return if box.w < 8 || box.h < 2

      # One char per cell: control characters (escape sequences) and wide or zero-width ones become "?".
      text = box.node.name.dup.force_encoding(Encoding::UTF_8).scrub("?").each_char.map do |c|
        cp = c.ord
        cp < 0x20 || (0x7f..0x9f).cover?(cp) || R2UI::Canvas.cell_width(cp) != 1 ? "?" : c
      end.join[0, box.w - 1]
      text.each_char.with_index do |c, i|
        chars[box.y][box.x + i] = c
        fg[box.y][box.x + i] = LABEL
      end
    end

    # A frame around the box (solid if it is a single cell wide or tall).
    def outline(box, chars, fg)
      x0, y0 = box.x, box.y
      x1, y1 = box.x + box.w - 1, box.y + box.h - 1
      mark = ->(x, y, c) { chars[y][x] = c; fg[y][x] = OUTLINE }
      if box.w < 2 || box.h < 2
        (y0..y1).each { |y| (x0..x1).each { |x| mark.(x, y, "█") } }
        return
      end

      (x0 + 1...x1).each { |x| mark.(x, y0, "━"); mark.(x, y1, "━") }
      (y0 + 1...y1).each { |y| mark.(x0, y, "┃"); mark.(x1, y, "┃") }
      mark.(x0, y0, "┏"); mark.(x1, y0, "┓"); mark.(x0, y1, "┗"); mark.(x1, y1, "┛")
    end
  end
end
