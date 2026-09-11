# frozen_string_literal: true

require_relative "test_helper"
require "hatchbox/git"

class TestGit < Minitest::Test
  include TestHelper

  G = Hatchbox::Git

  def test_repo_match_accepts_ssh_https_and_plain_paths
    assert G.repo_match?("git@github.com:acme/api.git", "acme/api")
    assert G.repo_match?("https://github.com/acme/api.git", "acme/api")
    assert G.repo_match?("https://github.com/Acme/API", "acme/api")
    assert G.repo_match?("git@gitlab.com:acme/team/api.git", "acme/team/api")
  end

  def test_repo_match_rejects_other_repos
    refute G.repo_match?("git@github.com:acme/api.git", "acme/web")
    refute G.repo_match?("git@github.com:other/api.git", "acme/api")
    refute G.repo_match?("git@github.com:acme/api.git", "")
  end

  def test_reads_remote_branch_and_pin
    with_git_repo(remote: "git@github.com:acme/api.git", branch: "main") do
      assert_equal "git@github.com:acme/api.git", G.remote
      assert_equal "main", G.current_branch
      assert_nil G.pinned_app
      assert G.pin_app(42)
      assert_equal "42", G.pinned_app
    end
  end

  def test_pins_user_to_repo
    with_git_repo do
      assert_nil G.pinned_user
      assert G.pin_user("work")
      assert_equal "work", G.pinned_user
      assert G.unpin_user
      assert_nil G.pinned_user
    end
  end

  def test_returns_nil_outside_a_git_repo
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        assert_nil G.root
        assert_nil G.remote
        assert_nil G.pinned_app
        refute G.pin_app(42)
      end
    end
  end
end
