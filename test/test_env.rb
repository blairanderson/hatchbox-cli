# frozen_string_literal: true

require_relative "test_helper"
require "hatchbox/cli"
require "hatchbox/commands/env"
require_relative "../eval/mock_state"
require_relative "../eval/mock_server"

class TestEnv < Minitest::Test
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

  def with_api
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      yield
    end
  end

  # The Hatchbox API has no GET for env vars. Asking for one used to reach the
  # network and surface a bare "API error (301)".
  def test_list_explains_that_env_vars_are_write_only
    with_api do
      code, _out, err = run_cli(%w[env list 42])

      refute_equal 0, code
      assert_match(/write-only/i, err)
      assert_match(/web UI/i, err)
      refute_match(/301/, err)
    end
  end

  def test_help_does_not_advertise_list
    _code, out, = run_cli(%w[env --help])

    refute_match(/^\s*list\s/, out)
    assert_match(/set <app_id>/, out)
    assert_match(/unset <app_id>/, out)
  end

  def test_set_rejects_a_pair_without_a_value
    with_api do
      code, _out, err = run_cli(%w[env set 42 BROKEN])

      refute_equal 0, code
      assert_match(/Invalid KEY=VALUE/, err)
    end
  end

  def test_set_writes_the_pairs
    with_api do
      code, out, = run_cli(%w[env set 42 ALPHA=one BETA=two])

      assert_equal 0, code
      assert_match(/Set 2 env var\(s\) on app 42/, out)
      assert_match(/ALPHA, BETA/, out)
    end
  end
end
