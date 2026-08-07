# frozen_string_literal: true

module Hatchbox
  module Commands
    module GitProviders
      module_function

      HELP = <<~HELP
        hatchbox git-providers <command>

          list   List connected git providers for the account
      HELP

      COLUMNS = [%w[id ID], %w[provider Provider], %w[name Name]].freeze

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "list" then list(ctx)
        else ctx.die("Unknown git-providers command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def list(ctx)
        account = ctx.resolve_account
        providers = Array(ctx.client.get("/accounts/#{account}/git_providers"))
        ctx.output.list(providers, columns: COLUMNS, empty: "No git providers found.")
      end
    end
  end
end
