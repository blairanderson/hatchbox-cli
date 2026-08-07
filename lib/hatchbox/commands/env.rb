# frozen_string_literal: true

module Hatchbox
  module Commands
    module Env
      module_function

      HELP = <<~HELP
        hatchbox env <command>

          list <app_id>                    List env var names (values are never returned by the API)
          set <app_id> KEY=VALUE [KEY=VALUE ...]   Add or update env vars
          unset <app_id> KEY [KEY ...]     Remove env vars
      HELP

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "list" then list(ctx, args)
        when "set" then set(ctx, args)
        when "unset" then unset(ctx, args)
        else ctx.die("Unknown env command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def list(ctx, args)
        id = ctx.resolve_app(args.shift)
        vars = Array(ctx.client.get("/apps/#{id}/env_vars"))
        ctx.output.list(vars, columns: [%w[id ID], %w[name Name]], empty: "No env vars found.")
      end

      def set(ctx, args)
        id = ctx.resolve_app(args.shift)
        pairs = args.map do |kv|
          key, value = kv.split("=", 2)
          ctx.die("Invalid KEY=VALUE pair: #{kv}", code: 2) if key.nil? || key.empty? || value.nil?
          { "name" => key, "value" => value }
        end
        ctx.die("Provide at least one KEY=VALUE pair.", code: 2) if pairs.empty?
        ctx.client.put("/apps/#{id}/env_vars", { "env_vars" => pairs })
        ctx.output.info("Set #{pairs.length} env var(s) on app #{id}: #{pairs.map { |p| p['name'] }.join(', ')}.")
      end

      def unset(ctx, args)
        id = ctx.resolve_app(args.shift)
        names = args
        ctx.die("Provide at least one KEY to remove.", code: 2) if names.empty?
        ctx.client.delete("/apps/#{id}/env_vars", { "env_vars" => names })
        ctx.output.info("Removed #{names.length} env var(s) from app #{id}: #{names.join(', ')}.")
      end
    end
  end
end
