# frozen_string_literal: true

module Hatchbox
  module Commands
    module Logs
      module_function

      HELP = <<~HELP
        hatchbox logs <command>

          get <log_id>     Show a log (deploy/restart/backup)
          watch <log_id>   Poll the log until it finishes
      HELP

      TERMINAL_STATES = %w[completed failed aborted].freeze

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "get" then get(ctx, args)
        when "watch" then watch(ctx, args)
        else ctx.die("Unknown logs command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def get(ctx, args)
        id = args.shift or ctx.die("Usage: hatchbox logs get <log_id>", code: 2)
        log = ctx.client.get("/logs/#{id}")
        ctx.output.object(log, only: %w[id name description state commit_sha username
                                        created_at started_at completed_at body])
      end

      def watch(ctx, args)
        id = args.shift or ctx.die("Usage: hatchbox logs watch <log_id>", code: 2)
        interval = (ENV["HATCHBOX_POLL_INTERVAL"] || "2").to_f
        last_state = nil
        loop do
          log = ctx.client.get("/logs/#{id}")
          state = log["state"].to_s
          if state != last_state
            ctx.output.info("log #{id}: #{state}")
            last_state = state
          end
          if TERMINAL_STATES.include?(state)
            ctx.output.object(log, only: %w[id name state started_at completed_at body]) if ctx.json?
            return ctx.die("Log #{id} #{state}.", code: 1) if state != "completed"

            ctx.output.info("Log #{id} completed.")
            return
          end
          sleep(interval)
        end
      end
    end
  end
end
