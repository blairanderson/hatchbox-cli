# frozen_string_literal: true

require "optparse"

module Hatchbox
  module Commands
    module AuthCmd
      module_function

      HOST = "app.hatchbox.io"

      HELP = <<~HELP
        hatchbox auth <command>

          login           Store an API token and log in as a user
          status          Show all logged-in users and the active one
          switch          Switch the global default user
          logout          Remove a logged-in user
          use <user>      Pin a user to this repo or directory
          unuse           Remove the user pin from this repo or directory

        User resolution for each command (first match wins):
          1. HATCHBOX_USER env var
          2. git config --local hatchbox.user   (repo pin)
          3. .hatchbox-user file              (walk up from cwd)
          4. global default                   (`hatchbox auth switch`)

        Global --token and env token vars still override stored credentials.
      HELP

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "login" then login(ctx, args)
        when "status" then status(ctx, args)
        when "switch" then switch(ctx, args)
        when "logout" then logout(ctx, args)
        when "use" then use_pin(ctx, args)
        when "unuse" then unuse_pin(ctx, args)
        else ctx.die("Unknown auth command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def login(ctx, args)
        with_token = false
        user = nil
        parser = OptionParser.new do |o|
          o.on("--with-token") { with_token = true }
          o.on("-u", "--user USER") { |v| user = v }
        end
        parser.parse!(args)

        token = read_token(with_token)
        ctx.die("No token provided.", code: 2) if token.nil? || token.empty?

        accounts = Client.new(token: token).get("/accounts")
        user ||= ctx.auth.derive_user_name(accounts)
        stored = ctx.auth.login(user, token)

        account = Array(accounts).first
        label = account ? "#{account['name']} (account #{account['id']})" : stored
        ctx.output.info("Logged in as #{stored} — #{label}.")
        ctx.output.info("Credentials stored in #{Config.path}.")
        ctx.output.object({ "user" => stored, "active" => true }) if ctx.json?
      rescue APIError => e
        ctx.die(e.message)
      rescue ArgumentError => e
        ctx.die(e.message)
      end

      def status(ctx, args)
        show_token = false
        active_only = false
        parser = OptionParser.new do |o|
          o.on("-t", "--show-token") { show_token = true }
          o.on("-a", "--active") { active_only = true }
        end
        parser.parse!(args)

        entries = ctx.auth.status_entries
        entries = entries.select { |e| e["active"] } if active_only

        resolved = ctx.auth.resolve_context

        if ctx.json?
          payload = entries.map { |e| entry_for_json(e, show_token: show_token) }
          ctx.output.object({
            "host" => HOST,
            "users" => payload,
            "resolved_user" => resolved[:user],
            "resolved_source" => resolved[:source]
          })
          return
        end

        if entries.empty?
          puts "No Hatchbox credentials stored."
          puts "Log in with `hatchbox auth login`."
          return
        end

        puts HOST
        entries.each { |e| print_entry(e, show_token: show_token) }
        print_resolution(resolved)
      end

      def switch(ctx, args)
        user = nil
        parser = OptionParser.new do |o|
          o.on("-u", "--user USER") { |v| user = v }
        end
        parser.parse!(args)

        if user
          switched = ctx.auth.switch(user)
        elsif ctx.auth.users.length == 2
          switched = ctx.auth.switch_to_other
        elsif ctx.auth.users.length > 2
          ctx.die("Multiple users are logged in. Pass --user <name>.\n\n#{user_list(ctx)}", code: 2)
        else
          ctx.die("Only one user is logged in.", code: 2)
        end

        ctx.output.info("Switched active user to #{switched}.")
        ctx.output.object({ "user" => switched, "active" => true }) if ctx.json?
      rescue ArgumentError => e
        ctx.die(e.message)
      end

      def logout(ctx, args)
        user = nil
        parser = OptionParser.new do |o|
          o.on("-u", "--user USER") { |v| user = v }
        end
        parser.parse!(args)

        target = user || ctx.auth.active_user
        ctx.die("No user is logged in.", code: 2) if target.nil? || target.empty?

        ctx.auth.logout(target)
        ctx.output.info("Logged out #{target}.")
        ctx.output.object({ "user" => target, "logged_out" => true }) if ctx.json?
      rescue ArgumentError => e
        ctx.die(e.message)
      end

      def use_pin(ctx, args)
        raw = args.shift or ctx.die("Usage: hatchbox auth use <user>", code: 2)
        user = ctx.auth.normalize_user_key(raw)
        ctx.die("Not logged in as #{user}. Run `hatchbox auth login --user #{user}`.", code: 2) unless ctx.auth.users.key?(user)

        if Git.root
          Git.pin_user(user) or ctx.die("Could not write `git config #{Git::USER_KEY}` in this repo.", code: 2)
          ctx.output.info("Pinned user #{user} to this repo (git config #{Git::USER_KEY}).")
          ctx.output.object({ "user" => user, "pin" => "repo" }) if ctx.json?
        else
          ctx.auth.pin_directory_user(user)
          ctx.output.info("Pinned user #{user} to this directory (.hatchbox-user).")
          ctx.output.object({ "user" => user, "pin" => "directory" }) if ctx.json?
        end
      rescue ArgumentError => e
        ctx.die(e.message)
      end

      def unuse_pin(ctx, args)
        ctx.die("Usage: hatchbox auth unuse", code: 2) unless args.empty?

        if Git.root && Git.pinned_user
          Git.unpin_user
          ctx.output.info("Removed repo user pin (git config #{Git::USER_KEY}).")
          ctx.output.object({ "unpinned" => "repo" }) if ctx.json?
        elsif ctx.auth.unpin_directory
          ctx.output.info("Removed directory user pin (.hatchbox-user).")
          ctx.output.object({ "unpinned" => "directory" }) if ctx.json?
        else
          ctx.die("No user pin in this directory or repo.", code: 2)
        end
      end

      def read_token(with_token)
        if with_token
          $stdin.read.to_s.strip
        else
          $stderr.print "Paste your Hatchbox API token: "
          $stdin.gets.to_s.strip
        end
      end

      def print_entry(entry, show_token:)
        active = entry["active"]
        mark = active ? "✓" : " "
        puts "  #{mark} Logged in as #{entry['user']}"
        puts "  - Active user: #{active}"
        puts "  - Token: #{mask_token(entry['token'], show_token: show_token)}"
        puts "  - Default account: #{entry['default_account'] || '(not set)'}"
        puts
      end

      def entry_for_json(entry, show_token:)
        {
          "user" => entry["user"],
          "active" => entry["active"],
          "token" => show_token ? entry["token"] : mask_token(entry["token"]),
          "default_account" => entry["default_account"],
          "default_app" => entry["default_app"]
        }
      end

      def mask_token(token, show_token: false)
        return "(none)" if token.nil? || token.empty?
        return token if show_token
        return token if token.length <= 4

        "#{'*' * (token.length - 4)}#{token[-4..]}"
      end

      def user_list(ctx)
        ctx.auth.users.keys.map { |u| "  #{u}" }.join("\n")
      end

      def print_resolution(resolved)
        user = resolved[:user]
        source = resolved[:source]
        return if user.nil?

        puts "Current directory resolves to: #{user}"
        puts "  (#{source})"
      end
    end
  end
end
