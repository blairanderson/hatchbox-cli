# frozen_string_literal: true

require "fileutils"
require_relative "test_helper"
require "hatchbox/auth"
require "hatchbox/cli"
require_relative "../eval/mock_state"
require_relative "../eval/mock_server"

class TestAuth < Minitest::Test
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

  def test_login_stores_user_and_sets_active
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      code, out, = run_cli_with_stdin(["auth", "login", "--with-token"], @state.token)
      assert_equal 0, code
      assert_match(/Logged in as acme-inc/, out)

      auth = Hatchbox::Auth.new
      assert_equal "acme-inc", auth.active_user
      assert_equal @state.token, auth.token
    end
  end

  def test_status_shows_all_users_with_active_marker
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "work"], @state.token)
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "personal"], @state.token)

      code, out, = run_cli(%w[auth status])
      assert_equal 0, code
      assert_match(/app\.hatchbox\.io/, out)
      assert_match(/Logged in as work/, out)
      assert_match(/Logged in as personal/, out)
      assert_match(/Active user: false/, out)
      assert_match(/Active user: true/, out)
    end
  end

  def test_switch_between_two_users
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "alpha"], @state.token)
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "beta"], @state.token)

      code, out, = run_cli(%w[auth switch])
      assert_equal 0, code
      assert_match(/Switched active user to alpha/, out)
      assert_equal "alpha", Hatchbox::Auth.new.active_user
    end
  end

  def test_switch_with_user_flag
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "alpha"], @state.token)
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "beta"], @state.token)
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "gamma"], @state.token)

      code, out, = run_cli(%w[auth switch --user alpha])
      assert_equal 0, code
      assert_match(/Switched active user to alpha/, out)
      assert_equal "alpha", Hatchbox::Auth.new.active_user
    end
  end

  def test_logout_removes_user
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "alpha"], @state.token)
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "beta"], @state.token)

      code, out, = run_cli(%w[auth logout --user beta])
      assert_equal 0, code
      assert_match(/Logged out beta/, out)

      auth = Hatchbox::Auth.new
      assert_equal "alpha", auth.active_user
      refute auth.users.key?("beta")
    end
  end

  def test_legacy_token_migrates_to_users
    with_clean_env do
      cfg = Hatchbox::Config.new
      cfg["token"] = "legacy-token"
      cfg["default_account"] = "1"
      cfg["default_app"] = "42"

      auth = Hatchbox::Auth.new
      assert_equal "default", auth.active_user
      assert_equal "legacy-token", auth.token
      assert_equal "1", auth.default_account
      assert_equal "42", auth.default_app
      assert_nil Hatchbox::Config.new["token"]
    end
  end

  def test_per_user_defaults
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "alpha"], @state.token)
      run_cli(%w[accounts use 1])

      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "beta"], @state.token)
      run_cli(%w[apps use 42])

      auth = Hatchbox::Auth.new
      auth.switch("alpha")
      assert_equal "1", auth.default_account
      assert_nil auth.default_app

      auth.switch("beta")
      assert_equal "42", auth.default_app
    end
  end

  def test_directory_pin_overrides_global_active_user
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "personal"], @state.token)
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "work"], @state.token)
      run_cli(%w[auth switch --user personal])

      Dir.mktmpdir do |dir|
        work_tree = File.join(dir, "work", "project")
        FileUtils.mkdir_p(work_tree)
        File.write(File.join(dir, "work", ".hatchbox-user"), "work\n")

        Dir.chdir(work_tree) do
          auth = Hatchbox::Auth.new
          assert_equal "personal", auth.active_user
          assert_equal "work", auth.resolved_user
        end
      end
    end
  end

  def test_repo_pin_overrides_directory_pin
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "personal"], @state.token)
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "work"], @state.token)

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".hatchbox-user"), "work\n")
        with_git_repo(remote: "git@github.com:acme/api.git") do |repo|
          system("git", "-C", repo, "config", "--local", "hatchbox.user", "personal", exception: true)
          Dir.chdir(repo) do
            auth = Hatchbox::Auth.new
            assert_equal "personal", auth.resolved_user
          end
        end
      end
    end
  end

  def test_auth_use_pins_repo
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "work"], @state.token)

      with_git_repo(remote: "git@github.com:acme/api.git") do |repo|
        code, out, = run_cli(%w[auth use work])
        assert_equal 0, code
        assert_match(/Pinned user work/, out)
        assert_equal "work", `git config --get hatchbox.user`.strip
      end
    end
  end

  def test_auth_use_pins_directory_when_not_in_repo
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "work"], @state.token)

      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          code, out, = run_cli(%w[auth use work])
          assert_equal 0, code
          assert_match(/\.hatchbox-user/, out)
          assert_equal "work", File.read(".hatchbox-user").strip
        end
      end
    end
  end

  def test_hatchbox_user_env_overrides_pins
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "personal"], @state.token)
      run_cli_with_stdin(["auth", "login", "--with-token", "--user", "work"], @state.token)

      with_git_repo(remote: "git@github.com:acme/api.git") do |repo|
        system("git", "-C", repo, "config", "--local", "hatchbox.user", "work", exception: true)
        Dir.chdir(repo) do
          ENV["HATCHBOX_USER"] = "personal"
          assert_equal "personal", Hatchbox::Auth.new.resolved_user
        end
      end
    end
  end

  def test_active_user_token_used_when_no_env
    with_clean_env do
      ENV["HATCHBOX_API_URL"] = @server.base_url
      run_cli_with_stdin(["auth", "login", "--with-token"], @state.token)

      code, out, = run_cli(%w[accounts list])
      assert_equal 0, code
      assert_match(/acme-inc/, out)
    end
  end

  def run_cli_with_stdin(argv, input)
    code = nil
    out, err = capture_io do
      $stdin = StringIO.new(input)
      code = Hatchbox::CLI.run(argv)
    end
    $stdin = STDIN
    [code, out, err]
  end
end
