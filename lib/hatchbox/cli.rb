# frozen_string_literal: true

require_relative "version"
require_relative "config"
require_relative "auth"
require_relative "client"
require_relative "output"
require_relative "git"

module Hatchbox
  # Signals a clean exit with a specific code (used instead of `exit` so tests
  # and the eval harness can drive the CLI in-process).
  class ExitError < StandardError
    attr_reader :code

    def initialize(message = nil, code: 1)
      @code = code
      super(message)
    end
  end

  TOKEN_ENV_VARS = %w[HATCHBOX_API_KEY HATCHBOX_TOKEN HATCHBOX_API_TOKEN].freeze

  GROUPS = {
    "whoami" => "Whoami",
    "accounts" => "Accounts",
    "apps" => "Apps",
    "env" => "Env",
    "master-key" => "MasterKey",
    "processes" => "Processes",
    "clusters" => "Clusters",
    "servers" => "Servers",
    "domains" => "Domains",
    "git-providers" => "GitProviders",
    "db-clusters" => "DbClusters",
    "databases" => "Databases",
    "logs" => "Logs",
    "config" => "ConfigCmd",
    "auth" => "AuthCmd"
  }.freeze

  # Shared state + helpers handed to every command module.
  class Context
    attr_reader :options, :config, :auth, :output

    def initialize(options)
      @options = options
      @config = Config.new
      @auth = Auth.new(@config)
      @output = Output.new(json: options[:json])
      @client = nil
    end

    def json?
      @options[:json]
    end

    # Resolve the API token: --token flag, then env vars, then active user.
    def token
      return @options[:token] if @options[:token] && !@options[:token].empty?

      TOKEN_ENV_VARS.each do |var|
        val = ENV[var]
        return val if val && !val.empty?
      end

      cfg = @auth.token
      return cfg if cfg && !cfg.empty?

      raise MissingTokenError, token_help
    end

    def client
      @client ||= Client.new(token: token)
    end

    # Resolve the account id: explicit arg, --account flag, env, config default,
    # or (when the account list has exactly one entry) auto-select and cache it.
    def resolve_account(explicit = nil)
      id = explicit || @options[:account] || env_account || @auth.default_account
      return id.to_s if id && !id.to_s.empty?

      accounts = client.get("/accounts")
      accounts = Array(accounts)
      case accounts.length
      when 0
        die("No accounts are available for this token.")
      when 1
        chosen = accounts.first["id"].to_s
        @auth.default_account = chosen
        @output.info("Using account #{account_label(accounts.first)} (saved as default).")
        chosen
      else
        list = accounts.map { |a| "  #{a['id']}  #{a['name']}" }.join("\n")
        die("Multiple accounts found. Choose one with `hatchbox accounts use <id>` " \
            "or pass --account <id>:\n#{list}")
      end
    end

    # Resolve an app id, in order:
    #   1. explicit arg
    #   2. app pinned to this repo (`git config hatchbox.app`)
    #   3. the account app whose repo_path matches this repo's origin remote
    #      (auto-pinned on first match)
    #   4. the saved default_app
    def resolve_app(explicit = nil)
      id = explicit || Git.pinned_app
      return id.to_s if id && !id.to_s.empty?

      id = detect_app_from_repo
      return id if id

      id = @auth.default_app
      return id.to_s if id && !id.to_s.empty?

      die("No app specified. Pass an <app_id>, run from a repo Hatchbox deploys, " \
          "or set a default with `hatchbox apps use <id>`.")
    end

    # Account apps whose repo_path matches the origin remote. When several
    # match (staging + production), the current git branch breaks the tie.
    def repo_app_matches(remote)
      apps = Array(client.get("/accounts/#{resolve_account}/apps"))
      matches = apps.select { |a| Git.repo_match?(remote, a["repo_path"]) }
      if matches.length > 1
        branch = Git.current_branch
        on_branch = matches.select { |a| a["branch"].to_s == branch }
        matches = on_branch if on_branch.length == 1
      end
      matches
    end

    def detect_app_from_repo
      remote = Git.remote
      return nil unless remote

      matches = repo_app_matches(remote)
      case matches.length
      when 0 then nil
      when 1
        app = matches.first
        id = app["id"].to_s
        pinned = Git.pin_app(id)
        note = pinned ? " (pinned via `git config #{Git::PIN_KEY}`)" : ""
        @output.info("Detected app #{id} (#{app['name']}) from origin #{Git.slug(remote)}#{note}.")
        id
      else
        list = matches.map { |a| "  git config #{Git::PIN_KEY} #{a['id']}   # #{a['name']} (#{a['branch']})" }
        die("#{matches.length} apps deploy #{Git.slug(remote)}. Pin one for this repo:\n#{list.join("\n")}")
      end
    end

    def die(message, code: 1)
      raise ExitError.new(message, code: code)
    end

    private

    def env_account
      val = ENV["HATCHBOX_ACCOUNT_ID"]
      val && !val.empty? ? val : nil
    end

    def account_label(acct)
      "#{acct['id']} (#{acct['name']})"
    end

    def token_help
      <<~MSG.strip
        No Hatchbox API token found.

        Provide one of the following (checked in this order):
          1. --token <TOKEN>
          2. export HATCHBOX_API_KEY=<TOKEN>
          3. export HATCHBOX_TOKEN=<TOKEN>
          4. export HATCHBOX_API_TOKEN=<TOKEN>
          5. the active user in #{Config.path} (`hatchbox auth login`)

        Create a token in Hatchbox under your account's API Tokens page.
      MSG
    end
  end

  module CLI
    module_function

    # Entry point. Returns an exit code (0 = success).
    def run(argv)
      opts, rest = extract_global_options(argv.dup)

      if opts[:version]
        puts "hatchbox #{Hatchbox::VERSION}"
        return 0
      end

      group = rest.shift
      if group.nil? || (opts[:help] && group.nil?)
        puts usage
        return group.nil? && !opts[:help] ? 1 : 0
      end

      const = GROUPS[group]
      unless const
        warn "Unknown command group: #{group}\n\n#{usage}"
        return 2
      end

      require_relative "commands/#{command_file(group)}"
      ctx = Context.new(opts)
      klass = Commands.const_get(const)
      klass.run(ctx, rest, help: opts[:help])
      0
    rescue MissingTokenError => e
      warn e.message
      1
    rescue UnknownUserError => e
      warn e.message
      1
    rescue APIError => e
      warn e.message
      1
    rescue ExitError => e
      warn e.message if e.message && !e.message.empty?
      e.code
    rescue Interrupt
      warn "\nAborted."
      130
    end

    def command_file(group)
      group.tr("-", "_")
    end

    # Pull recognized global flags from anywhere in argv; leave the rest intact
    # so command modules can parse their own options.
    def extract_global_options(argv)
      opts = { json: false, token: nil, account: nil, no_color: false, help: false, version: false }
      rest = []

      while (arg = argv.shift)
        case arg
        when "--json" then opts[:json] = true
        when "--no-color" then opts[:no_color] = true
        when "--help", "-h" then opts[:help] = true
        when "--version", "-v" then opts[:version] = true
        when "--token" then opts[:token] = argv.shift
        when /\A--token=(.*)\z/m then opts[:token] = Regexp.last_match(1)
        when "--account", "-a" then opts[:account] = argv.shift
        when /\A--account=(.*)\z/m then opts[:account] = Regexp.last_match(1)
        else rest << arg
        end
      end

      opts[:no_color] = true unless $stdout.tty?
      [opts, rest]
    end

    def usage
      <<~USAGE
        hatchbox #{Hatchbox::VERSION} — CLI for the Hatchbox.io API

        Usage:
          hatchbox <group> <command> [args] [options]

        Groups:
          whoami         show current account + the app for this directory
          accounts       list / use / current
          apps           list / get / create / update / deploy / restart / auto-deploy / use
          env            set / unset (write-only; no read endpoint)
          master-key     set RAILS_MASTER_KEY from this repo's Rails master key
          processes      list / get / restart
          clusters       list / get
          servers        list / get
          domains        list / get / add / update / remove
          git-providers  list
          db-clusters    list
          databases      list / get / create / update / attach / detach / backup-latest / backup-trigger
          logs           get / watch
          config         path / show
          auth           login / status / switch / logout / use / unuse

        Global options:
          --json             Output raw JSON instead of a table
          --token <TOKEN>    API token (else env vars / active user from `hatchbox auth login`)
          --account, -a <id> Account id (else HATCHBOX_ACCOUNT_ID / saved default / auto when single)
          --no-color         Plain output
          --help, -h         Show help
          --version, -v      Show version

        Most commands that take <app_id> resolve it automatically: a repo pin
        (`git config hatchbox.app`), then this repo's origin remote matched
        against your apps, then the saved default (`hatchbox apps use <id>`).

        Examples:
          hatchbox whoami
          hatchbox accounts list
          hatchbox apps list
          hatchbox processes list 1234
          hatchbox apps deploy 1234 --sha abc123
          hatchbox env set 1234 RAILS_ENV=production SECRET=xyz
          hatchbox master-key                     # inside your Rails repo
          hatchbox logs watch 99
      USAGE
    end
  end

  module Commands; end
end
