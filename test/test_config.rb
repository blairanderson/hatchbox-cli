# frozen_string_literal: true

require_relative "test_helper"
require "hatchbox/config"

class TestConfig < Minitest::Test
  include TestHelper

  def test_path_respects_xdg
    with_clean_env do |dir|
      assert_equal File.join(dir, "hatchboxcli", "config.yml"), Hatchbox::Config.path
    end
  end

  def test_round_trip
    with_clean_env do
      cfg = Hatchbox::Config.new
      cfg["default_account"] = "1"
      cfg["default_app"] = "42"

      reloaded = Hatchbox::Config.new
      assert_equal "1", reloaded["default_account"]
      assert_equal "42", reloaded["default_app"]
    end
  end

  def test_nil_deletes_key
    with_clean_env do
      cfg = Hatchbox::Config.new
      cfg["default_app"] = "42"
      cfg["default_app"] = nil
      assert_nil Hatchbox::Config.new["default_app"]
    end
  end

  def test_file_is_private
    with_clean_env do
      cfg = Hatchbox::Config.new
      cfg["token"] = "secret"
      mode = File.stat(Hatchbox::Config.path).mode & 0o777
      assert_equal 0o600, mode
    end
  end

  def test_missing_file_is_empty
    with_clean_env do
      assert_equal({}, Hatchbox::Config.new.to_h)
    end
  end
end
