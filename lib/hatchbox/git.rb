# frozen_string_literal: true

module Hatchbox
  # Git helpers for repo-aware app detection. Readers return nil when the
  # current directory is not inside a git repo.
  module Git
    module_function

    # Repo-local pins (local git config only — never committed).
    PIN_KEY = "hatchbox.app"
    USER_KEY = "hatchbox.user"

    def root
      out = `git rev-parse --show-toplevel 2>/dev/null`.strip
      out.empty? ? nil : out
    end

    def remote
      out = `git remote get-url origin 2>/dev/null`.strip
      out.empty? ? nil : out
    end

    # Works on unborn branches (fresh `git init`); nil on detached HEAD.
    def current_branch
      out = `git symbolic-ref --short -q HEAD 2>/dev/null`.strip
      out.empty? ? nil : out
    end

    def pinned_app
      out = `git config --get #{PIN_KEY} 2>/dev/null`.strip
      out.empty? ? nil : out
    end

    def pin_app(id)
      system("git", "config", "--local", PIN_KEY, id.to_s, err: File::NULL)
    end

    def pinned_user
      out = `git config --local --get #{USER_KEY} 2>/dev/null`.strip
      out.empty? ? nil : out
    end

    def pin_user(name)
      system("git", "config", "--local", USER_KEY, name.to_s, err: File::NULL)
    end

    def unpin_user
      system("git", "config", "--local", "--unset", USER_KEY, err: File::NULL)
    end

    # True when the app's repo_path is a tail of the remote URL's segments,
    # so "git@github.com:acme/api.git" matches "acme/api" (and nested groups).
    def repo_match?(remote, repo_path)
      want = segments(repo_path)
      return false if want.length < 2

      segments(remote).last(want.length) == want
    end

    def segments(str)
      str.to_s.strip.downcase.sub(/\.git\z/, "").split(%r{[:/]}).reject(&:empty?)
    end

    # "git@github.com:acme/api.git" -> "acme/api", for messages.
    def slug(remote)
      segments(remote).last(2).join("/")
    end
  end
end
