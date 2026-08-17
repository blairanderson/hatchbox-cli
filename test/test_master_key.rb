# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "hatchbox/cli"
require "hatchbox/commands/master_key"
require_relative "../eval/mock_state"
require_relative "../eval/mock_server"

class TestMasterKey < Minitest::Test
  include TestHelper

  MK = Hatchbox::Commands::MasterKey
  KEY = "0123456789abcdef0123456789abcdef"

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

  # Build a throwaway git repo whose origin points at `remote`, with a key file.
  def with_repo(remote: "git@github.com:acme/api.git", key_path: "config/master.key", key: KEY)
    Dir.mktmpdir do |dir|
      real = File.realpath(dir)
      system("git", "init", "-q", real, exception: true)
      system("git", "-C", real, "remote", "add", "origin", remote, exception: true)
      if key_path
        FileUtils.mkdir_p(File.join(real, File.dirname(key_path)))
        File.write(File.join(real, key_path), "#{key}\n")
      end
      Dir.chdir(real) { yield real }
    end
  end

  # --- repo matching -----------------------------------------------------

  def test_repo_match_accepts_ssh_https_and_plain_paths
    assert MK.repo_match?("git@github.com:acme/api.git", "acme/api")
    assert MK.repo_match?("https://github.com/acme/api.git", "acme/api")
    assert MK.repo_match?("https://github.com/Acme/API", "acme/api")
    assert MK.repo_match?("git@gitlab.com:acme/team/api.git", "acme/team/api")
  end

  def test_repo_match_rejects_other_repos
    refute MK.repo_match?("git@github.com:acme/api.git", "acme/web")
    refute MK.repo_match?("git@github.com:other/api.git", "acme/api")
    refute MK.repo_match?("git@github.com:acme/api.git", "")
  end

  # --- key file discovery ------------------------------------------------

  def test_prefers_production_key_over_master_key
    with_repo(key_path: "config/master.key", key: "aaa") do |root|
      FileUtils.mkdir_p(File.join(root, "config/credentials"))
      File.write(File.join(root, "config/credentials/production.key"), "bbb\n")
      file, key = MK.read_key(root)
      assert_equal "config/credentials/production.key", file
      assert_equal "bbb", key
    end
  end

  def test_read_key_returns_nil_when_absent
    with_repo(key_path: nil) do |root|
      assert_equal [nil, nil], MK.read_key(root)
    end
  end

  # --- end to end --------------------------------------------------------

  def test_sets_rails_master_key_when_repo_matches
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      with_repo do
        code, out, = run_cli(%w[master-key 42 --yes])
        assert_equal 0, code
        assert_match(/Set RAILS_MASTER_KEY on app 42/, out)
        assert_match(/hatchbox apps restart 42/, out)
      end
      stored = @state.env_vars.find { |v| v["name"] == "RAILS_MASTER_KEY" }
      assert_equal KEY, stored["value"]
    end
  end

  def test_finds_the_app_from_the_git_remote_with_no_app_id
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      with_repo do
        code, out, = run_cli(%w[master-key --yes])
        assert_equal 0, code
        assert_match(/Matched app 42 \(production-api\) — acme\/api/, out)
        assert_match(/Set RAILS_MASTER_KEY on app 42/, out)
      end
      assert_equal KEY, @state.env_vars.find { |v| v["name"] == "RAILS_MASTER_KEY" }["value"]
    end
  end

  def test_no_matching_app_lists_the_account_apps
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      with_repo(remote: "git@github.com:acme/unknown.git") do
        code, _out, err = run_cli(%w[master-key --yes])
        assert_equal 1, code
        assert_match(/No app in account 1 deploys acme\/unknown/, err)
        assert_match(/42  production-api  acme\/api/, err)
      end
      assert_nil @state.env_vars.find { |v| v["name"] == "RAILS_MASTER_KEY" }
    end
  end

  def test_two_apps_on_one_repo_asks_which
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      @state.apps << { "id" => 43, "name" => "staging-api", "repo_path" => "acme/api",
                       "branch" => "main", "account_id" => 1 }
      with_repo do
        code, _out, err = run_cli(%w[master-key --yes])
        assert_equal 1, code
        assert_match(/2 apps deploy acme\/api/, err)
        assert_match(/hatchbox master-key 43   # staging-api/, err)
      end
      assert_nil @state.env_vars.find { |v| v["name"] == "RAILS_MASTER_KEY" }
    end
  end

  def test_refuses_when_repo_does_not_match
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      with_repo(remote: "git@github.com:acme/some-other-app.git") do
        code, _out, err = run_cli(%w[master-key 42 --yes])
        assert_equal 1, code
        assert_match(/Repo mismatch/, err)
      end
      assert_nil @state.env_vars.find { |v| v["name"] == "RAILS_MASTER_KEY" }
    end
  end

  def test_errors_when_no_key_file
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      with_repo(key_path: nil) do
        code, _out, err = run_cli(%w[master-key 42 --yes])
        assert_equal 1, code
        assert_match(/No key file found/, err)
      end
    end
  end

  def test_errors_when_key_file_is_empty
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      ENV["HATCHBOX_API_KEY"] = @state.token
      with_repo(key: "") do
        code, _out, err = run_cli(%w[master-key 42 --yes])
        assert_equal 1, code
        assert_match(/is empty/, err)
      end
    end
  end
end
