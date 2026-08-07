# frozen_string_literal: true

require "json"

module Eval
  # In-memory world state for the mock Hatchbox API. Deterministic tests mutate
  # this directly; the live eval mutates it through the /__control HTTP routes.
  class MockState
    attr_reader :token, :accounts, :apps, :processes

    def self.from_file(path)
      new(JSON.parse(File.read(path)))
    end

    def initialize(data)
      @token = data["token"]
      @accounts = data["accounts"] || []
      @apps = data["apps"] || []
      # deep-copy processes so tests can flip flags without touching the fixture
      @processes = (data["processes"] || []).map { |p| p.dup }
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
