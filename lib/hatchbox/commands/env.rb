# frozen_string_literal: true

module Hatchbox
  module Commands
    module Env
      module_function

      HELP = <<~HELP
        hatchbox env <command>

          set <app_id> KEY=VALUE [KEY=VALUE ...]   Add or update env vars
          unset <app_id> KEY [KEY ...]     Remove env vars

        Env vars are write-only. The API exposes no read endpoint, so there is
        no `env list` — read them in the Hatchbox web UI instead.
      HELP

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "list" then unsupported_list(ctx)
        when "set" then set(ctx, args)
        when "unset" then unset(ctx, args)
        else ctx.die("Unknown env command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      # The Hatchbox API has no GET for env vars — /apps/:id/env_vars answers a
      # redirect, which used to surface here as a bare "API error (301)". Say
      # what is actually going on instead.
      def unsupported_list(ctx)
        ctx.die("Env vars are write-only: the Hatchbox API has no endpoint that " \
                "returns them. Use `hatchbox env set` / `env unset` to change them, " \
                "and the Hatchbox web UI to read them.", code: 2)
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
