# frozen_string_literal: true

require "json"
require_relative "table"

module Hatchbox
  # Formats API results either as JSON (--json) or as terminal-table style tables.
  class Output
    def initialize(json: false)
      @json = json
    end

    def json?
      @json
    end

    # Render an array of hashes as a table (or the raw JSON array).
    # columns: array of keys to show, in order. When nil, use the keys of the
    # first row. Titles are humanized unless a [key, title] pair is given.
    def list(rows, columns: nil, empty: "No records found.")
      rows = Array(rows)
      if @json
        puts JSON.pretty_generate(rows)
        return
      end

      if rows.empty?
        puts empty
        return
      end

      specs = column_specs(columns, rows.first)
      headings = specs.map { |_, title| title }
      body = rows.map { |row| specs.map { |key, _| row[key.to_s] } }
      puts Table.render(headings, body)
    end

    # Render a single object as a key/value table (or raw JSON).
    def object(hash, only: nil)
      if @json
        puts JSON.pretty_generate(hash)
        return
      end

      data = hash || {}
      data = data.select { |k, _| Array(only).map(&:to_s).include?(k.to_s) } if only
      puts Table.key_value(data)
    end

    # For actions that return a small confirmation (e.g. {"id" => 123}) or nothing.
    def action(result, message: nil)
      if @json
        puts JSON.pretty_generate(result.nil? ? {} : result)
        return
      end

      puts message if message
      if result.is_a?(Hash) && result["id"]
        puts "Log ID: #{result['id']}  (track with: hatchbox logs watch #{result['id']})"
      end
    end

    def info(message)
      puts message unless @json
    end

    private

    def column_specs(columns, sample)
      cols = columns || sample.keys
      cols.map do |c|
        if c.is_a?(Array)
          [c[0].to_s, c[1].to_s]
        else
          [c.to_s, Table.humanize(c)]
        end
      end
    end
  end
end
