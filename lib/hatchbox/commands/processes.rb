# frozen_string_literal: true

module Hatchbox
  module Commands
    module Processes
      module_function

      HELP = <<~HELP
        hatchbox processes <command>

          list <app_id>                 List processes and their status
          get <app_id> <process_id>     Show one process
          restart <app_id> <process_id> Restart a process
      HELP

      COLUMNS = [
        %w[id ID], %w[name Name], ["active", "Active"],
        %w[start_command Command], %w[server_id Server], %w[roles Roles]
      ].freeze

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "list" then list(ctx, args)
        when "get" then get(ctx, args)
        when "restart" then restart(ctx, args)
        else ctx.die("Unknown processes command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def list(ctx, args)
        app = ctx.resolve_app(args.shift)
        procs = Array(ctx.client.get("/apps/#{app}/processes"))
        ctx.output.list(procs, columns: COLUMNS, empty: "No processes found.")
      end

      def get(ctx, args)
        app = ctx.resolve_app(args.shift)
        pid = args.shift or ctx.die("Usage: hatchbox processes get <app_id> <process_id>", code: 2)
        proc_obj = ctx.client.get("/apps/#{app}/processes/#{pid}")
        ctx.output.object(proc_obj)
      end

      def restart(ctx, args)
        app = ctx.resolve_app(args.shift)
        pid = args.shift or ctx.die("Usage: hatchbox processes restart <app_id> <process_id>", code: 2)
        ctx.client.post("/apps/#{app}/processes/#{pid}/restart")
        ctx.output.info("Restart queued for process #{pid} on app #{app}.")
      end
    end
  end
end
