# frozen_string_literal: true

require_relative "config"
require_relative "client"
require_relative "git"

module Hatchbox
  # Raised when a directory/repo pin names a user that is not logged in.
  class UnknownUserError < StandardError; end

  # Manages multiple authenticated Hatchbox users with a single global active
  # user, plus optional directory/repo overrides (like `gh auth` + local pins).
  #
  # Config shape:
  #   user: personal             # global default (from `hatchbox auth switch`)
  #   users:
  #     personal:
  #       token: "..."
  #       default_account: "1"
  #     work:
  #       token: "..."
  #
  # Local overrides (checked in order, first wins):
  #   1. HATCHBOX_USER env var
  #   2. git config --local hatchbox.user   (repo pin)
  #   3. .hatchbox-user file                (walk up from cwd)
  #   4. global user above
  class Auth
    DIRECTORY_PIN_FILE = ".hatchbox-user"
    USER_ENV_VAR = "HATCHBOX_USER"

    def initialize(config = Config.new)
      @config = config
      migrate_legacy!
    end

    attr_reader :config

    def users
      data = @config["users"]
      data.is_a?(Hash) ? data : {}
    end

    # Global default user (`hatchbox auth switch`).
    def active_user
      @config["user"]
    end

    def active?
      active_user && users.key?(active_user)
    end

    # User in effect for the current directory.
    def resolved_user(start: Dir.pwd)
      resolve_context(start: start)[:user]
    end

    # User + how it was chosen (for whoami / auth status).
    def resolve_context(start: Dir.pwd)
      env = ENV[USER_ENV_VAR]
      if env && !env.empty?
        user = normalize_user(env)
        return context(user, "environment variable #{USER_ENV_VAR}")
      end

      git_user = Git.pinned_user
      if git_user && !git_user.empty?
        user = normalize_user(git_user)
        return context(user, "repo pin (git config #{Git::USER_KEY})")
      end

      dir_hit = directory_pin(start)
      if dir_hit
        user = normalize_user(dir_hit[:user])
        return context(user, "directory pin (#{DIRECTORY_PIN_FILE} in #{dir_hit[:dir]})")
      end

      user = active_user
      context(user, user ? "global default (#{Config.path})" : nil)
    end

    def token
      user = resolved_user
      data = user ? users[user] : nil
      tok = data.is_a?(Hash) ? data["token"] : nil
      return tok if tok && !tok.empty?

      nil
    end

    def default_account
      user_data_get(resolved_user, "default_account") || @config["default_account"]
    end

    def default_account=(id)
      user_set("default_account", id)
    end

    def default_app
      user_data_get(resolved_user, "default_app") || @config["default_app"]
    end

    def default_app=(id)
      user_set("default_app", id)
    end

    def login(user, token)
      user = normalize_user(user)
      validate_token!(token)

      merged = (users[user] || {}).merge("token" => token)
      @config["users"] = users.merge(user => merged)
      @config["user"] = user
      clear_legacy_keys!
      @config.save
      user
    end

    def switch(user)
      user = normalize_user(user)
      raise ArgumentError, "not logged in as #{user}" unless users.key?(user)

      @config["user"] = user
      @config.save
      user
    end

    def switch_to_other
      keys = users.keys
      raise ArgumentError, "only one user is logged in" if keys.length < 2

      other = keys.find { |k| k != active_user }
      switch(other)
    end

    def logout(user = nil)
      user = normalize_user(user || active_user)
      raise ArgumentError, "not logged in as #{user}" unless users.key?(user)

      remaining = users.dup
      remaining.delete(user)
      @config["users"] = remaining
      @config["user"] = remaining.keys.first if active_user == user
      @config.save
    end

    def pin_directory_user(user, dir = Dir.pwd)
      user = normalize_user(user)
      raise ArgumentError, "not logged in as #{user}" unless users.key?(user)

      path = File.join(File.expand_path(dir), DIRECTORY_PIN_FILE)
      File.write(path, "#{user}\n")
      File.chmod(0o600, path)
      user
    end

    def unpin_directory(dir = Dir.pwd)
      path = File.join(File.expand_path(dir), DIRECTORY_PIN_FILE)
      return false unless File.file?(path)

      File.delete(path)
      true
    end

    def normalize_user_key(name)
      normalize_user(name)
    end

    def derive_user_name(accounts)
      names = Array(accounts).map { |a| a["name"] }.compact
      raise ArgumentError, "token has no accessible accounts" if names.empty?

      base = slugify(names.first)
      return base unless users.key?(base)

      suffix = 2
      suffix += 1 while users.key?("#{base}-#{suffix}")
      "#{base}-#{suffix}"
    end

    def status_entries
      users.map do |name, data|
        {
          "user" => name,
          "active" => name == active_user,
          "token" => data["token"],
          "default_account" => data["default_account"],
          "default_app" => data["default_app"]
        }
      end
    end

    private

    def context(user, source)
      if user && !users.key?(user)
        raise UnknownUserError, unknown_user_help(user, source)
      end

      { user: user, source: source }
    end

    def unknown_user_help(user, source)
      <<~MSG.strip
        Hatchbox user "#{user}" is not logged in (#{source}).

        Log in with `hatchbox auth login --user #{user}`, or update the pin:
          git config --unset #{Git::USER_KEY}
          rm .hatchbox-user
      MSG
    end

    def directory_pin(start)
      dir = File.expand_path(start)
      loop do
        pin_file = File.join(dir, DIRECTORY_PIN_FILE)
        if File.file?(pin_file)
          user = File.read(pin_file).strip
          return { user: user, dir: dir } unless user.empty?
        end
        parent = File.dirname(dir)
        break if parent == dir

        dir = parent
      end
      nil
    end

    def user_data_get(user, key)
      return nil unless user

      data = users[user]
      data.is_a?(Hash) ? data[key] : nil
    end

    def user_set(key, value)
      user = resolved_user
      if user && users.key?(user)
        entry = users[user].dup
        if value.nil?
          entry.delete(key)
        else
          entry[key] = value
        end
        @config["users"] = users.merge(user => entry)
      else
        @config[key] = value
      end
    end

    def migrate_legacy!
      return if users.any?

      legacy_token = @config["token"]
      return if legacy_token.nil? || legacy_token.empty?

      user = "default"
      @config["users"] = {
        user => {
          "token" => legacy_token,
          "default_account" => @config["default_account"],
          "default_app" => @config["default_app"]
        }.compact
      }
      @config["user"] = user
      clear_legacy_keys!
      @config.save
    end

    def clear_legacy_keys!
      @config["token"] = nil
      @config["default_account"] = nil
      @config["default_app"] = nil
    end

    def validate_token!(token)
      Client.new(token: token).get("/accounts")
    end

    def normalize_user(name)
      slugify(name)
    end

    def slugify(name)
      name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    end
  end
end
