# frozen_string_literal: true

require_relative "../git"

module Hatchbox
  module Commands
    # Who am I, and which app does this directory belong to?
    module Whoami
      module_function

      HELP = <<~HELP
        hatchbox whoami

          Shows the current account and the app connected to this directory.

          The app is resolved from, in order:
            1. the repo pin        `git config hatchbox.app`
            2. the origin remote   matched against your apps' repo_path
            3. the saved default   `default_app` in #{Config.path}

          whoami never writes anything; it only reports.
      HELP

      def run(ctx, args, help: false)
        return puts(HELP) if help || args.first == "help"

        account_id = ctx.resolve_account
        account = Array(ctx.client.get("/accounts")).find { |a| a["id"].to_s == account_id }

        app_id, source = resolve_app_readonly(ctx)
        app = app_id ? fetch_app(ctx, app_id) : nil
        remote = Git.remote

        ctx.output.object({
          "account_id" => account_id,
          "account_name" => account ? account["name"] : "(unknown)",
          "app_id" => app_id || "(none)",
          "app_name" => app ? app["name"] : (app_id ? "(unknown)" : "(none)"),
          "app_source" => source || "(none — pass an <app_id> or `hatchbox apps use <id>`)",
          "repo" => remote ? Git.slug(remote) : "(not a git repo)"
        })
      end

      # Mirrors Context#resolve_app but never dies and never pins.
      # Returns [app_id, source_description] or [nil, reason].
      def resolve_app_readonly(ctx)
        id = Git.pinned_app
        return [id, "repo pin (git config #{Git::PIN_KEY})"] if id

        remote = Git.remote
        if remote
          matches = ctx.repo_app_matches(remote)
          return [matches.first["id"].to_s, "detected from origin #{Git.slug(remote)}"] if matches.length == 1

          if matches.length > 1
            ids = matches.map { |a| "#{a['id']} (#{a['name']})" }.join(", ")
            return [nil, "ambiguous — #{ids}; pin one with `git config #{Git::PIN_KEY} <id>`"]
          end
        end

        id = ctx.config["default_app"]
        return [id.to_s, "default_app (#{Config.path})"] if id && !id.to_s.empty?

        [nil, nil]
      end

      def fetch_app(ctx, id)
        ctx.client.get("/apps/#{id}")
      rescue APIError
        nil
      end
    end
  end
end
