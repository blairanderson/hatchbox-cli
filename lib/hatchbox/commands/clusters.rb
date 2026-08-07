# frozen_string_literal: true

module Hatchbox
  module Commands
    module Clusters
      module_function

      HELP = <<~HELP
        hatchbox clusters <command>

          list              List clusters in the account
          get <cluster_id>  Show one cluster (includes servers)
      HELP

      COLUMNS = [
        %w[id ID], %w[name Name], %w[provider Provider],
        %w[region Region], %w[servers_count Servers]
      ].freeze

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "list" then list(ctx)
        when "get" then get(ctx, args)
        else ctx.die("Unknown clusters command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def list(ctx)
        account = ctx.resolve_account
        clusters = Array(ctx.client.get("/accounts/#{account}/clusters"))
        ctx.output.list(clusters, columns: COLUMNS, empty: "No clusters found.")
      end

      def get(ctx, args)
        id = args.shift or ctx.die("Usage: hatchbox clusters get <cluster_id>", code: 2)
        cluster = ctx.client.get("/clusters/#{id}")
        ctx.output.object(cluster)
      end
    end
  end
end
