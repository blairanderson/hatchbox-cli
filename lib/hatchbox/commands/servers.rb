# frozen_string_literal: true

module Hatchbox
  module Commands
    module Servers
      module_function

      HELP = <<~HELP
        hatchbox servers <command>

          list <cluster_id>              List servers in a cluster
          get <cluster_id> <server_id>   Show one server
      HELP

      COLUMNS = [
        %w[id ID], %w[name Name], %w[state State],
        %w[public_ip Public\ IP], %w[private_ip Private\ IP], %w[roles Roles]
      ].freeze

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "list" then list(ctx, args)
        when "get" then get(ctx, args)
        else ctx.die("Unknown servers command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def list(ctx, args)
        cluster = args.shift or ctx.die("Usage: hatchbox servers list <cluster_id>", code: 2)
        servers = Array(ctx.client.get("/clusters/#{cluster}/servers"))
        ctx.output.list(servers, columns: COLUMNS, empty: "No servers found.")
      end

      def get(ctx, args)
        cluster = args.shift or ctx.die("Usage: hatchbox servers get <cluster_id> <server_id>", code: 2)
        server = args.shift or ctx.die("Usage: hatchbox servers get <cluster_id> <server_id>", code: 2)
        obj = ctx.client.get("/clusters/#{cluster}/servers/#{server}")
        ctx.output.object(obj)
      end
    end
  end
end
