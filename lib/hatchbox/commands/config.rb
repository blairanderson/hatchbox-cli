# frozen_string_literal: true

module Hatchbox
  module Commands
    # Named ConfigCmd to avoid clashing with Hatchbox::Config.
    module ConfigCmd
      module_function

      HELP = <<~HELP
        hatchbox config <command>

          path            Print the config file path
          show            Show the current config (token is masked)
      HELP

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "path" then puts(Hatchbox::Config.path)
        when "show" then show(ctx)
        else ctx.die("Unknown config command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def show(ctx)
        data = ctx.config.to_h
        data["token"] = mask(data["token"]) if data["token"]
        ctx.output.object(data)
      end

      def mask(token)
        return token if token.length <= 4

        "#{'*' * (token.length - 4)}#{token[-4..]}"
      end
    end
  end
end
