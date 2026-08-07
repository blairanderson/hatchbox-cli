# frozen_string_literal: true

module Hatchbox
  module Commands
    module Accounts
      module_function

      HELP = <<~HELP
        hatchbox accounts <command>

          list            List your accounts
          use <id>        Save <id> as the default account
          current         Show the current default account
      HELP

      def run(ctx, args, help: false)
        sub = args.shift
        return puts(HELP) if help || sub.nil?

        case sub
        when "list" then list(ctx)
        when "use" then use(ctx, args)
        when "current" then current(ctx)
        else ctx.die("Unknown accounts command: #{sub}\n\n#{HELP}", code: 2)
        end
      end

      def list(ctx)
        accounts = Array(ctx.client.get("/accounts"))
        # Auto-cache when there is exactly one account.
        if ctx.config["default_account"].nil? && accounts.length == 1
          ctx.config["default_account"] = accounts.first["id"].to_s
        end
        default = ctx.config["default_account"].to_s
        rows = accounts.map do |a|
          a.merge("default" => (a["id"].to_s == default ? "*" : ""))
        end
        ctx.output.list(rows, columns: [%w[id ID], %w[name Name], %w[default Default]],
                              empty: "No accounts found.")
      end

      def use(ctx, args)
        id = args.shift or ctx.die("Usage: hatchbox accounts use <id>", code: 2)
        ctx.config["default_account"] = id.to_s
        ctx.output.info("Default account set to #{id}.")
        ctx.output.object({ "default_account" => id.to_s }) if ctx.json?
      end

      def current(ctx)
        id = ctx.config["default_account"]
        ctx.die("No default account set. Run `hatchbox accounts use <id>`.") if id.nil?
        ctx.output.object({ "default_account" => id.to_s })
      end
    end
  end
end
