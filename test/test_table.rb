# frozen_string_literal: true

require_relative "test_helper"
require "hatchbox/table"

class TestTable < Minitest::Test
  def test_render_exact_ascii
    output = Hatchbox::Table.render(%w[ID Name], [[1, "web"], [2, "worker"]])
    expected = <<~TXT.chomp
      +----+--------+
      | ID | Name   |
      +----+--------+
      | 1  | web    |
      | 2  | worker |
      +----+--------+
    TXT
    assert_equal expected, output
  end

  def test_widens_to_longest_cell
    output = Hatchbox::Table.render(%w[A], [["short"], ["a-much-longer-value"]])
    assert_includes output, "| a-much-longer-value |"
    assert_includes output, "| short               |"
  end

  def test_empty_rows_keeps_frame
    output = Hatchbox::Table.render(%w[ID Name], [])
    lines = output.split("\n")
    assert_equal 3, lines.length # border, header, border
    assert_match(/\A\+/, lines.first)
  end

  def test_cell_formatting
    assert_equal "true", Hatchbox::Table.cell_to_s(true)
    assert_equal "false", Hatchbox::Table.cell_to_s(false)
    assert_equal "", Hatchbox::Table.cell_to_s(nil)
    assert_equal "a, b", Hatchbox::Table.cell_to_s(%w[a b])
  end

  def test_key_value
    output = Hatchbox::Table.key_value("public_ip" => "1.2.3.4")
    assert_includes output, "| Public Ip"
    assert_includes output, "| 1.2.3.4"
  end
end
