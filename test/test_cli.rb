# frozen_string_literal: true

require_relative "test_helper"
require "hatchbox/cli"
require_relative "../eval/mock_state"
require_relative "../eval/mock_server"

class TestCLI < Minitest::Test
  include TestHelper

  def setup
    data = JSON.parse(File.read(File.expand_path("../eval/scenario.json", __dir__)))
    @state = Eval::MockState.new(data)
    @server = Eval::MockServer.new(@state, port: 0).start_async
  end

  def teardown
    @server.stop
  end

  def run_cli(argv)
    code = nil
    out, err = capture_io { code = Hatchbox::CLI.run(argv) }
    [code, out, err]
  end

  def test_missing_token_exits_nonzero_with_help
    with_clean_env do
      code, _out, err = run_cli(%w[accounts list])
      assert_equal 1, code
      assert_match(/No Hatchbox API token found/, err)
      assert_match(/HATCHBOX_API_KEY/, err)
    end
  end

  def test_token_flag_precedence_and_account_autocache
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      code, out, = run_cli(["--token", @state.token, "accounts", "list"])
      assert_equal 0, code
      assert_match(/acme-inc/, out)
      # single account was cached as default
      assert_equal "1", Hatchbox::Config.new["default_account"]
    end
  end

  def test_apps_list_uses_cached_account
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      run_cli(%w[accounts list]) # caches default account
      code, out, = run_cli(%w[apps list])
      assert_equal 0, code
      assert_match(/production-api/, out)
    end
  end

  def test_processes_list_json
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      code, out, = run_cli(%w[--json processes list production-api])
      assert_equal 0, code
      parsed = JSON.parse(out)
      assert_equal 3, parsed.length
      assert(parsed.all? { |p| p["active"] })
    end
  end

  def test_processes_reflect_control_down
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      @state.all_down!
      code, out, = run_cli(%w[--json processes list production-api])
      assert_equal 0, code
      assert(JSON.parse(out).none? { |p| p["active"] })
    end
  end

  def test_apps_use_sets_default
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      run_cli(%w[apps use 42])
      assert_equal "42", Hatchbox::Config.new["default_app"]
      # now processes list works with no positional arg
      code, out, = run_cli(%w[processes list])
      assert_equal 0, code
      assert_match(/worker/, out)
    end
  end

  def test_unknown_group_exits_2
    with_clean_env do
      code, _out, err = run_cli(%w[bogus list])
      assert_equal 2, code
      assert_match(/Unknown command group/, err)
    end
  end
end
