# frozen_string_literal: true

require_relative "test_helper"
require "hatchbox/cli"
require_relative "../eval/mock_state"
require_relative "../eval/mock_server"

class TestRepoDetection < Minitest::Test
  include TestHelper

  REMOTE = "git@github.com:acme/api.git"

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

  def with_api_env
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      yield
    end
  end

  def add_staging_app(branch: "develop")
    @state.apps << { "id" => 43, "name" => "staging-api", "repo_path" => "acme/api",
                     "branch" => branch, "account_id" => 1 }
  end

  # --- resolve_app via git detection --------------------------------------

  def test_detects_app_from_origin_and_pins_it
    with_api_env do
      with_git_repo(remote: REMOTE) do
        code, out, = run_cli(%w[processes list])
        assert_equal 0, code
        assert_match(/Detected app 42 \(production-api\) from origin acme\/api/, out)
        assert_match(/worker/, out)
        assert_equal "42", `git config --get hatchbox.app`.strip
      end
    end
  end

  def test_pin_wins_without_detection_chatter
    with_api_env do
      with_git_repo(remote: REMOTE) do
        system("git", "config", "--local", "hatchbox.app", "42", exception: true)
        code, out, = run_cli(%w[processes list])
        assert_equal 0, code
        refute_match(/Detected app/, out)
        assert_match(/worker/, out)
      end
    end
  end

  def test_branch_breaks_tie_between_apps_on_one_repo
    with_api_env do
      add_staging_app(branch: "develop")
      with_git_repo(remote: REMOTE, branch: "develop") do
        code, out, = run_cli(%w[processes list])
        assert_equal 0, code
        assert_match(/Detected app 43 \(staging-api\)/, out)
        assert_equal "43", `git config --get hatchbox.app`.strip
      end
    end
  end

  def test_ambiguous_repo_dies_with_pin_instructions
    with_api_env do
      add_staging_app(branch: "main") # same branch as production-api
      with_git_repo(remote: REMOTE, branch: "main") do
        code, _out, err = run_cli(%w[processes list])
        assert_equal 1, code
        assert_match(/2 apps deploy acme\/api/, err)
        assert_match(/git config hatchbox.app 43/, err)
      end
    end
  end

  def test_falls_back_to_default_app_when_repo_matches_nothing
    with_api_env do
      run_cli(%w[apps use 42])
      with_git_repo(remote: "git@github.com:acme/unrelated.git") do
        code, out, = run_cli(%w[processes list])
        assert_equal 0, code
        assert_match(/worker/, out)
        assert_equal "", `git config --get hatchbox.app`.strip
      end
    end
  end

  # --- apps use (no id) ----------------------------------------------------

  def test_apps_use_without_id_detects_and_pins
    with_api_env do
      with_git_repo(remote: REMOTE) do
        code, out, = run_cli(%w[apps use])
        assert_equal 0, code
        assert_match(/Pinned app 42 \(production-api\)/, out)
        assert_equal "42", `git config --get hatchbox.app`.strip
        assert_nil Hatchbox::Config.new["default_app"]
      end
    end
  end

  def test_apps_use_without_id_outside_repo_shows_usage
    with_api_env do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          code, _out, err = run_cli(%w[apps use])
          assert_equal 2, code
          assert_match(/Usage: hatchbox apps use <app_id>/, err)
        end
      end
    end
  end

  # --- whoami ---------------------------------------------------------------

  def test_whoami_reports_detected_app
    with_api_env do
      with_git_repo(remote: REMOTE) do
        code, out, = run_cli(%w[--json whoami])
        assert_equal 0, code
        parsed = JSON.parse(out)
        assert_equal "1", parsed["account_id"]
        assert_equal "acme-inc", parsed["account_name"]
        assert_equal "42", parsed["app_id"]
        assert_equal "production-api", parsed["app_name"]
        assert_match(/detected from origin acme\/api/, parsed["app_source"])
        assert_equal "acme/api", parsed["repo"]
        # whoami never writes the pin
        assert_equal "", `git config --get hatchbox.app`.strip
      end
    end
  end

  def test_whoami_reports_pin_and_default_sources
    with_api_env do
      with_git_repo(remote: REMOTE) do
        system("git", "config", "--local", "hatchbox.app", "42", exception: true)
        _code, out, = run_cli(%w[--json whoami])
        assert_match(/repo pin/, JSON.parse(out)["app_source"])
      end

      run_cli(%w[apps use 42])
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          _code, out, = run_cli(%w[--json whoami])
          parsed = JSON.parse(out)
          assert_match(/default_app/, parsed["app_source"])
          assert_equal "(not a git repo)", parsed["repo"]
        end
      end
    end
  end

  def test_whoami_with_nothing_resolvable
    with_api_env do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          code, out, = run_cli(%w[--json whoami])
          assert_equal 0, code
          parsed = JSON.parse(out)
          assert_equal "(none)", parsed["app_id"]
          assert_equal "(none)", parsed["app_name"]
        end
      end
    end
  end
end
