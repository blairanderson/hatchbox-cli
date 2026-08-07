# frozen_string_literal: true

module Hatchbox
  module Commands
    module DbClusters
      module_function

      HELP = <<~HELP
        hatchbox db-clusters <command>

          list   List database clusters for the account
      HELP

      COLUMNS = [
        %w[id ID], %w[name Name], %w[engine Engine], %w[version Version],
        %w[region Region], %w[databases_count Databases]
      ].freeze

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "list" then list(ctx)
        else ctx.die("Unknown db-clusters command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def list(ctx)
        account = ctx.resolve_account
        clusters = Array(ctx.client.get("/accounts/#{account}/database_clusters"))
        ctx.output.list(clusters, columns: COLUMNS, empty: "No database clusters found.")
      end
    end
  end
end
