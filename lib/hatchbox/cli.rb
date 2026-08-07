# frozen_string_literal: true

require_relative "version"
require_relative "config"
require_relative "client"
require_relative "output"

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
    "accounts" => "Accounts",
    "apps" => "Apps",
    "env" => "Env",
    "processes" => "Processes",
    "clusters" => "Clusters",
    "servers" => "Servers",
    "domains" => "Domains",
    "git-providers" => "GitProviders",
    "db-clusters" => "DbClusters",
    "databases" => "Databases",
    "logs" => "Logs",
    "config" => "ConfigCmd"
  }.freeze

  # Shared state + helpers handed to every command module.
  class Context
    attr_reader :options, :config, :output

    def initialize(options)
      @options = options
      @config = Config.new
      @output = Output.new(json: options[:json])
      @client = nil
    end

    def json?
      @options[:json]
    end

    # Resolve the API token: --token flag, then env vars, then config file.
    def token
      return @options[:token] if @options[:token] && !@options[:token].empty?

      TOKEN_ENV_VARS.each do |var|
        val = ENV[var]
        return val if val && !val.empty?
      end

      cfg = @config["token"]
      return cfg if cfg && !cfg.empty?

      raise MissingTokenError, token_help
    end

    def client
      @client ||= Client.new(token: token)
    end

    # Resolve the account id: explicit arg, --account flag, env, config default,
    # or (when the account list has exactly one entry) auto-select and cache it.
    def resolve_account(explicit = nil)
      id = explicit || @options[:account] || env_account || @config["default_account"]
      return id.to_s if id && !id.to_s.empty?

      accounts = client.get("/accounts")
      accounts = Array(accounts)
      case accounts.length
      when 0
        die("No accounts are available for this token.")
      when 1
        chosen = accounts.first["id"].to_s
        @config["default_account"] = chosen
        @output.info("Using account #{account_label(accounts.first)} (saved as default).")
        chosen
      else
        list = accounts.map { |a| "  #{a['id']}  #{a['name']}" }.join("\n")
        die("Multiple accounts found. Choose one with `hatchbox accounts use <id>` " \
            "or pass --account <id>:\n#{list}")
      end
    end

    # Resolve an app id: explicit arg or the saved default_app.
    def resolve_app(explicit = nil)
      id = explicit || @config["default_app"]
      return id.to_s if id && !id.to_s.empty?

      die("No app specified. Pass an <app_id> or set one with `hatchbox apps use <id>`.")
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
          5. `token:` in #{Config.path}

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
          accounts       list / use / current
          apps           list / get / create / update / deploy / restart / auto-deploy / use
          env            list / set / unset
          processes      list / get / restart
          clusters       list / get
          servers        list / get
          domains        list / get / add / update / remove
          git-providers  list
          db-clusters    list
          databases      list / get / create / update / attach / detach / backup-latest / backup-trigger
          logs           get / watch
          config         path / show

        Global options:
          --json             Output raw JSON instead of a table
          --token <TOKEN>    API token (else HATCHBOX_API_KEY / HATCHBOX_TOKEN / HATCHBOX_API_TOKEN / config)
          --account, -a <id> Account id (else HATCHBOX_ACCOUNT_ID / saved default / auto when single)
          --no-color         Plain output
          --help, -h         Show help
          --version, -v      Show version

        Most commands that take <app_id> fall back to your saved default app
        (set with `hatchbox apps use <id>`).

        Examples:
          hatchbox accounts list
          hatchbox apps list
          hatchbox processes list 1234
          hatchbox apps deploy 1234 --sha abc123
          hatchbox env set 1234 RAILS_ENV=production SECRET=xyz
          hatchbox logs watch 99
      USAGE
    end
  end

  module Commands; end
end
