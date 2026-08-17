# frozen_string_literal: true

require "optparse"

require_relative "../git"

module Hatchbox
  module Commands
    module Apps
      module_function

      HELP = <<~HELP
        hatchbox apps <command>

          list                          List apps in the account
          get <app_id>                  Show one app
          create --cluster-id <id> --name <name> [options]
          update <app_id> [options]
          deploy <app_id> [--sha <sha>] Trigger a deploy
          restart <app_id>              Restart the app
          auto-deploy enable <app_id>   Enable auto-deploy
          auto-deploy disable <app_id>  Disable auto-deploy
          use <app_id>                  Save <app_id> as the default app
          use                           Detect the app from this repo's origin
                                        remote and pin it (git config hatchbox.app)

        create/update options:
          --name, --branch, --repo-path, --connected-account-id,
          --caddyfile, --health-check-uri   (create also needs --cluster-id)
      HELP

      COLUMNS = [%w[id ID], %w[name Name], %w[repo_path Repo], %w[branch Branch]].freeze

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "list" then list(ctx)
        when "get" then get(ctx, args)
        when "create" then create(ctx, args)
        when "update" then update(ctx, args)
        when "deploy" then deploy(ctx, args)
        when "restart" then restart(ctx, args)
        when "auto-deploy" then auto_deploy(ctx, args)
        when "use" then use(ctx, args)
        else ctx.die("Unknown apps command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def list(ctx)
        account = ctx.resolve_account
        apps = Array(ctx.client.get("/accounts/#{account}/apps"))
        ctx.output.list(apps, columns: COLUMNS, empty: "No apps found.")
      end

      def get(ctx, args)
        id = ctx.resolve_app(args.shift)
        app = ctx.client.get("/apps/#{id}")
        ctx.output.object(app)
      end

      def create(ctx, args)
        attrs = parse_attrs(args)
        ctx.die("create requires --cluster-id and --name", code: 2) unless attrs["cluster_id"] && attrs["name"]
        app = ctx.client.post("/apps", attrs)
        ctx.output.info("Created app #{app['id']} (#{app['name']}).")
        ctx.output.object(app)
      end

      def update(ctx, args)
        id = ctx.resolve_app(args.shift)
        attrs = parse_attrs(args)
        ctx.die("update requires at least one attribute to change", code: 2) if attrs.empty?
        app = ctx.client.patch("/apps/#{id}", attrs)
        ctx.output.info("Updated app #{id}.")
        ctx.output.object(app)
      end

      def deploy(ctx, args)
        sha = nil
        parser = OptionParser.new { |o| o.on("--sha SHA") { |v| sha = v } }
        rest = parser.parse(args)
        id = ctx.resolve_app(rest.shift)
        body = sha ? { "sha" => sha } : nil
        result = ctx.client.post("/apps/#{id}/deploy", body)
        ctx.output.action(result, message: "Deploy queued for app #{id}.")
      end

      def restart(ctx, args)
        id = ctx.resolve_app(args.shift)
        result = ctx.client.post("/apps/#{id}/restart")
        ctx.output.action(result, message: "Restart queued for app #{id}.")
      end

      def auto_deploy(ctx, args)
        action = args.shift
        id = ctx.resolve_app(args.shift)
        case action
        when "enable"
          app = ctx.client.post("/apps/#{id}/auto_deploy")
          ctx.output.info("Auto-deploy enabled for app #{id}.")
          ctx.output.object(app) if ctx.json?
        when "disable"
          ctx.client.delete("/apps/#{id}/auto_deploy")
          ctx.output.info("Auto-deploy disabled for app #{id}.")
        else
          ctx.die("Usage: hatchbox apps auto-deploy enable|disable <app_id>", code: 2)
        end
      end

      def use(ctx, args)
        id = args.shift
        return pin_from_repo(ctx) if id.nil?

        ctx.config["default_app"] = id.to_s
        ctx.output.info("Default app set to #{id}.")
        ctx.output.object({ "default_app" => id.to_s }) if ctx.json?
      end

      # `apps use` with no id: match origin against the account's apps, pin it.
      def pin_from_repo(ctx)
        remote = Git.remote or
          ctx.die("Usage: hatchbox apps use <app_id>\n(no id given and no `origin` remote here to detect from)", code: 2)

        matches = ctx.repo_app_matches(remote)
        case matches.length
        when 1
          app = matches.first
          id = app["id"].to_s
          Git.pin_app(id) or ctx.die("Could not write `git config #{Git::PIN_KEY}` in this repo.")
          ctx.output.info("Pinned app #{id} (#{app['name']}) to this repo (git config #{Git::PIN_KEY}).")
          ctx.output.object({ "app_id" => id, "pinned" => true }) if ctx.json?
        when 0
          ctx.die("No app deploys #{Git.slug(remote)}. Pass an id: hatchbox apps use <app_id>")
        else
          list = matches.map { |a| "  git config #{Git::PIN_KEY} #{a['id']}   # #{a['name']} (#{a['branch']})" }
          ctx.die("#{matches.length} apps deploy #{Git.slug(remote)}. Pin one for this repo:\n#{list.join("\n")}")
        end
      end

      # Shared create/update flag parsing.
      def parse_attrs(args)
        attrs = {}
        OptionParser.new do |o|
          o.on("--cluster-id ID") { |v| attrs["cluster_id"] = v }
          o.on("--name NAME") { |v| attrs["name"] = v }
          o.on("--branch BRANCH") { |v| attrs["branch"] = v }
          o.on("--repo-path PATH") { |v| attrs["repo_path"] = v }
          o.on("--connected-account-id ID") { |v| attrs["connected_account_id"] = v }
          o.on("--caddyfile FILE") { |v| attrs["caddyfile"] = v }
          o.on("--health-check-uri URI") { |v| attrs["health_check_uri"] = v }
        end.parse(args)
        attrs
      end
    end
  end
end
