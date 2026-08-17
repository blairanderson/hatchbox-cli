# frozen_string_literal: true

require "optparse"

require_relative "../git"

module Hatchbox
  module Commands
    # Push a Rails master key to an app as RAILS_MASTER_KEY.
    #
    # Guards against pushing the wrong app's key: the local git remote must match
    # the app's repo_path on Hatchbox, and the overwrite is confirmed first.
    module MasterKey
      module_function

      ENV_NAME = "RAILS_MASTER_KEY"
      KEY_FILES = ["config/credentials/production.key", "config/master.key"].freeze

      HELP = <<~HELP
        hatchbox master-key [app_id] [--yes]

          Sets #{ENV_NAME} on your app from this repo's Rails master key.
          Run it from the repo — no app id needed.

          1. reads `git remote get-url origin`
          2. finds the app in your account with that repo_path
          3. reads the key file (first one found):
               #{KEY_FILES.join("\n       ")}
          4. asks you to confirm, then sets #{ENV_NAME}

          Pass an app_id to skip the search; the repo_path is still checked
          and the command stops if it does not match this repo.

        Options:
          --yes, -y    Skip the confirmation prompt
      HELP

      def run(ctx, args, help: false)
        return puts(HELP) if help

        assume_yes = false
        parser = OptionParser.new { |o| o.on("--yes", "-y") { assume_yes = true } }
        rest = parser.parse(args)

        root = Git.root or ctx.die("Not a git repository. Run this from your Rails app.")
        remote = Git.remote or ctx.die("No `origin` git remote found in #{root}.")

        app = find_app(ctx, rest.shift, remote)
        id = app["id"]
        repo_path = app["repo_path"].to_s

        file, key = read_key(root)
        ctx.die("No key file found. Looked for:\n  #{KEY_FILES.join("\n  ")}") if file.nil?
        ctx.die("#{file} is empty.") if key.empty?

        unless assume_yes
          confirm!(ctx, id: id, app: app, repo_path: repo_path, file: file)
        end

        ctx.client.put("/apps/#{id}/env_vars", { "env_vars" => [{ "name" => ENV_NAME, "value" => key }] })
        ctx.output.info("Set #{ENV_NAME} on app #{id} (#{app['name']}) from #{file}.")
        ctx.output.info("Run `hatchbox apps restart #{id}` (or deploy) to apply it.")
        ctx.output.object({ "app_id" => id.to_s, "name" => app["name"], "key_file" => file, "set" => ENV_NAME }) if ctx.json?
      end

      # --- app lookup --------------------------------------------------------

      # With an explicit id, fetch that app and check it against this repo.
      # Without one, find the app in the account whose repo_path is this repo.
      def find_app(ctx, explicit, remote)
        return verify_app(ctx, explicit, remote) if explicit && !explicit.empty?

        account = ctx.resolve_account
        apps = Array(ctx.client.get("/accounts/#{account}/apps"))
        matches = apps.select { |a| Git.repo_match?(remote, a["repo_path"]) }

        case matches.length
        when 1
          app = matches.first
          ctx.output.info("Matched app #{app['id']} (#{app['name']}) — #{app['repo_path']}")
          app
        when 0
          ctx.die(<<~MSG.strip)
            No app in account #{account} deploys #{Git.slug(remote)} (origin: #{remote}).

            Apps in this account:
            #{apps.map { |a| "  #{a['id']}  #{a['name']}  #{a['repo_path']}" }.join("\n")}
          MSG
        else
          ctx.die(<<~MSG.strip)
            #{matches.length} apps deploy #{Git.slug(remote)}. Say which one:

            #{matches.map { |a| "  hatchbox master-key #{a['id']}   # #{a['name']}" }.join("\n")}
          MSG
        end
      end

      def verify_app(ctx, id, remote)
        app = ctx.client.get("/apps/#{id}")
        return app if Git.repo_match?(remote, app["repo_path"])

        ctx.die(<<~MSG.strip)
          Repo mismatch — refusing to overwrite #{ENV_NAME}.

            App #{id} (#{app['name']}) deploys  #{app['repo_path']}
            This repo's origin is             #{remote}

          Check the app id, or set the value directly with `hatchbox env set`.
        MSG
      end

      # --- helpers -----------------------------------------------------------

      def confirm!(ctx, id:, app:, repo_path:, file:)
        unless $stdin.tty?
          ctx.die("Not a terminal — pass --yes to confirm overwriting #{ENV_NAME} on app #{id}.")
        end

        puts "App #{id} (#{app['name']})"
        puts "  repo      #{repo_path}"
        puts "  key file  #{file}"
        puts
        print "Overwrite #{ENV_NAME} on app #{id}? [y/N] "
        answer = $stdin.gets.to_s.strip.downcase
        ctx.die("Aborted.", code: 1) unless %w[y yes].include?(answer)
      end

      # Returns [relative_path, key] for the first key file present, else [nil, nil].
      def read_key(root)
        KEY_FILES.each do |rel|
          path = File.join(root, rel)
          return [rel, File.read(path).strip] if File.file?(path)
        end
        [nil, nil]
      end

    end
  end
end
