# frozen_string_literal: true

module Hatchbox
  # Zero-dependency ASCII table renderer in the classic terminal-table style:
  #
  #   +------+---------------+
  #   | ID   | Name          |
  #   +------+---------------+
  #   | 1    | production    |
  #   +------+---------------+
  #
  module Table
    module_function

    # headings: array of column titles
    # rows:     array of arrays (cells); cells are stringified
    def render(headings, rows)
      headings = headings.map(&:to_s)
      rows = rows.map { |r| r.map { |c| cell_to_s(c) } }

      widths = column_widths(headings, rows)
      border = border_line(widths)

      out = []
      out << border
      out << row_line(headings, widths)
      out << border
      unless rows.empty?
        rows.each { |r| out << row_line(r, widths) }
        out << border
      end
      out.join("\n")
    end

    # Two-column key/value table for a single object.
    def key_value(hash)
      rows = hash.map { |k, v| [humanize(k), cell_to_s(v)] }
      render(%w[Field Value], rows)
    end

    def column_widths(headings, rows)
      count = headings.length
      Array.new(count) do |i|
        max = headings[i].length
        rows.each do |r|
          len = (r[i] || "").length
          max = len if len > max
        end
        max
      end
    end

    def border_line(widths)
      "+" + widths.map { |w| "-" * (w + 2) }.join("+") + "+"
    end

    def row_line(cells, widths)
      padded = widths.each_index.map do |i|
        cell = (cells[i] || "").to_s
        " " + cell.ljust(widths[i]) + " "
      end
      "|" + padded.join("|") + "|"
    end

    def cell_to_s(value)
      case value
      when nil then ""
      when true then "true"
      when false then "false"
      when Array then value.join(", ")
      when Hash then value.map { |k, v| "#{k}=#{v}" }.join(", ")
      else value.to_s
      end
    end

    def humanize(key)
      key.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
    end
  end
end
