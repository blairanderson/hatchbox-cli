# frozen_string_literal: true

require "json"

module Eval
  # In-memory world state for the mock Hatchbox API. Deterministic tests mutate
  # this directly; the live eval mutates it through the /__control HTTP routes.
  class MockState
    attr_reader :token, :accounts, :apps, :processes, :env_vars

    def self.from_file(path)
      new(JSON.parse(File.read(path)))
    end

    def initialize(data)
      @token = data["token"]
      @accounts = data["accounts"] || []
      @apps = data["apps"] || []
      # deep-copy processes so tests can flip flags without touching the fixture
      @processes = (data["processes"] || []).map { |p| p.dup }
      @env_vars = (data["env_vars"] || []).map { |v| v.dup }
    end

    # The real API never returns values, only names.
    def env_var_names
      @env_vars.map { |v| { "id" => v["id"], "name" => v["name"] } }
    end

    # Mirrors the real API: values go in write-only, names come back out.
    def set_env_vars(pairs)
      Array(pairs).each do |pair|
        existing = @env_vars.find { |v| v["name"] == pair["name"] }
        if existing
          existing["value"] = pair["value"]
        else
          @env_vars << { "id" => @env_vars.length + 1, "name" => pair["name"], "value" => pair["value"] }
        end
      end
      env_var_names
    end

    def valid_token?(presented)
      presented == @token
    end

    def account(id)
      @accounts.find { |a| a["id"].to_s == id.to_s }
    end

    def app(id)
      @apps.find { |a| a["id"].to_s == id.to_s || a["name"].to_s == id.to_s }
    end

    def apps_for_account(account_id)
      @apps.select { |a| a["account_id"].to_s == account_id.to_s }
    end

    def process(id)
      @processes.find { |p| p["id"].to_s == id.to_s }
    end

    # Simulate the user disabling every process.
    def all_down!
      @processes.each { |p| p["active"] = false }
    end

    # Simulate the user re-enabling every process.
    def all_up!
      @processes.each { |p| p["active"] = true }
    end

    def all_down?
      @processes.all? { |p| p["active"] == false }
    end

    def all_up?
      @processes.all? { |p| p["active"] == true }
    end
  end
end
