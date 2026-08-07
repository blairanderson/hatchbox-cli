# frozen_string_literal: true

module Hatchbox
  module Commands
    module Domains
      module_function

      HELP = <<~HELP
        hatchbox domains <command>

          list <app_id>                       List domains
          get <app_id> <name>                 Show one domain
          add <app_id> <name>                 Add a domain
          update <app_id> <name> <new_name>   Rename a domain
          remove <app_id> <name>              Remove a domain
      HELP

      COLUMNS = [%w[id ID], %w[name Name], %w[created_at Created]].freeze

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "list" then list(ctx, args)
        when "get" then get(ctx, args)
        when "add" then add(ctx, args)
        when "update" then update(ctx, args)
        when "remove" then remove(ctx, args)
        else ctx.die("Unknown domains command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def list(ctx, args)
        app = ctx.resolve_app(args.shift)
        domains = Array(ctx.client.get("/apps/#{app}/domains"))
        ctx.output.list(domains, columns: COLUMNS, empty: "No domains found.")
      end

      def get(ctx, args)
        app = ctx.resolve_app(args.shift)
        name = args.shift or ctx.die("Usage: hatchbox domains get <app_id> <name>", code: 2)
        ctx.output.object(ctx.client.get("/apps/#{app}/domains/#{name}"))
      end

      def add(ctx, args)
        app = ctx.resolve_app(args.shift)
        name = args.shift or ctx.die("Usage: hatchbox domains add <app_id> <name>", code: 2)
        domain = ctx.client.post("/apps/#{app}/domains", { "domain" => { "name" => name } })
        ctx.output.info("Added domain #{name} to app #{app}.")
        ctx.output.object(domain) if ctx.json?
      end

      def update(ctx, args)
        app = ctx.resolve_app(args.shift)
        name = args.shift or ctx.die("Usage: hatchbox domains update <app_id> <name> <new_name>", code: 2)
        new_name = args.shift or ctx.die("Usage: hatchbox domains update <app_id> <name> <new_name>", code: 2)
        domain = ctx.client.patch("/apps/#{app}/domains/#{name}", { "domain" => { "name" => new_name } })
        ctx.output.info("Renamed domain #{name} to #{new_name}.")
        ctx.output.object(domain) if ctx.json?
      end

      def remove(ctx, args)
        app = ctx.resolve_app(args.shift)
        name = args.shift or ctx.die("Usage: hatchbox domains remove <app_id> <name>", code: 2)
        ctx.client.delete("/apps/#{app}/domains/#{name}")
        ctx.output.info("Removed domain #{name} from app #{app}.")
      end
    end
  end
end
