# frozen_string_literal: true

require "optparse"

module Hatchbox
  module Commands
    module Databases
      module_function

      HELP = <<~HELP
        hatchbox databases <command>

          list <db_cluster_id>                 List databases in a cluster
          get <db_cluster_id> <db_id>          Show one database
          create <db_cluster_id> [--name <n>] [--path <p>]   Create a database
          update <db_cluster_id> <db_id> [--name <n>] [--path <p>]  Update (SQLite)
          app-list <app_id>                    List databases attached to an app
          attach <app_id> <db_id> [--env-var <NAME>]   Attach a database to an app
          detach <app_id> <db_id>              Detach a database from an app
          backup-latest <db_id>                Get a presigned URL for the latest backup
          backup-trigger <db_id>               Trigger a new backup
      HELP

      COLUMNS = [%w[id ID], %w[name Name], %w[engine Engine], %w[active Active]].freeze

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "list" then list(ctx, args)
        when "get" then get(ctx, args)
        when "create" then create(ctx, args)
        when "update" then update(ctx, args)
        when "app-list" then app_list(ctx, args)
        when "attach" then attach(ctx, args)
        when "detach" then detach(ctx, args)
        when "backup-latest" then backup_latest(ctx, args)
        when "backup-trigger" then backup_trigger(ctx, args)
        else ctx.die("Unknown databases command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def list(ctx, args)
        cluster = args.shift or ctx.die("Usage: hatchbox databases list <db_cluster_id>", code: 2)
        dbs = Array(ctx.client.get("/database_clusters/#{cluster}/databases"))
        ctx.output.list(dbs, columns: COLUMNS, empty: "No databases found.")
      end

      def get(ctx, args)
        cluster = args.shift or ctx.die("Usage: hatchbox databases get <db_cluster_id> <db_id>", code: 2)
        db = args.shift or ctx.die("Usage: hatchbox databases get <db_cluster_id> <db_id>", code: 2)
        ctx.output.object(ctx.client.get("/database_clusters/#{cluster}/databases/#{db}"))
      end

      def create(ctx, args)
        cluster = args.shift or ctx.die("Usage: hatchbox databases create <db_cluster_id> [--name --path]", code: 2)
        attrs = parse_db_attrs(args)
        db = ctx.client.post("/database_clusters/#{cluster}/databases", attrs)
        ctx.output.info("Created database #{db['id']} (#{db['name']}).")
        ctx.output.object(db)
      end

      def update(ctx, args)
        cluster = args.shift or ctx.die("Usage: hatchbox databases update <db_cluster_id> <db_id> [--name --path]", code: 2)
        db_id = args.shift or ctx.die("Usage: hatchbox databases update <db_cluster_id> <db_id> [--name --path]", code: 2)
        attrs = parse_db_attrs(args)
        ctx.die("update requires --name and/or --path", code: 2) if attrs.empty?
        db = ctx.client.patch("/database_clusters/#{cluster}/databases/#{db_id}", attrs)
        ctx.output.info("Updated database #{db_id}.")
        ctx.output.object(db) if ctx.json?
      end

      def app_list(ctx, args)
        app = ctx.resolve_app(args.shift)
        dbs = Array(ctx.client.get("/apps/#{app}/databases"))
        ctx.output.list(dbs, columns: COLUMNS, empty: "No databases attached to this app.")
      end

      def attach(ctx, args)
        env_var = nil
        rest = OptionParser.new { |o| o.on("--env-var NAME") { |v| env_var = v } }.parse(args)
        app = ctx.resolve_app(rest.shift)
        db_id = rest.shift or ctx.die("Usage: hatchbox databases attach <app_id> <db_id> [--env-var NAME]", code: 2)
        body = env_var ? { "env_var" => env_var } : nil
        db = ctx.client.post("/apps/#{app}/databases/#{db_id}/attachment", body)
        ctx.output.info("Attached database #{db_id} to app #{app}.")
        ctx.output.object(db) if ctx.json?
      end

      def detach(ctx, args)
        app = ctx.resolve_app(args.shift)
        db_id = args.shift or ctx.die("Usage: hatchbox databases detach <app_id> <db_id>", code: 2)
        ctx.client.delete("/apps/#{app}/databases/#{db_id}/attachment")
        ctx.output.info("Detached database #{db_id} from app #{app}.")
      end

      def backup_latest(ctx, args)
        db_id = args.shift or ctx.die("Usage: hatchbox databases backup-latest <db_id>", code: 2)
        result = ctx.client.get("/databases/#{db_id}/backups/latest")
        if ctx.json?
          ctx.output.object(result)
        else
          ctx.output.info("URL: #{result['url']}")
          ctx.output.info("Last backup at: #{result['last_backup_at']}")
        end
      end

      def backup_trigger(ctx, args)
        db_id = args.shift or ctx.die("Usage: hatchbox databases backup-trigger <db_id>", code: 2)
        result = ctx.client.post("/databases/#{db_id}/backups")
        ctx.output.action(result, message: "Backup triggered for database #{db_id}.")
      end

      def parse_db_attrs(args)
        attrs = {}
        OptionParser.new do |o|
          o.on("--name NAME") { |v| attrs["name"] = v }
          o.on("--path PATH") { |v| attrs["path"] = v }
        end.parse(args)
        attrs
      end
    end
  end
end
