# frozen_string_literal: true

require "yaml"
require "fileutils"

module Hatchbox
  # Persists long-lived defaults (token, default_account, default_app) to
  # ~/.config/hatchboxcli/config.yml (respecting XDG_CONFIG_HOME).
  class Config
    FILENAME = "config.yml"

    def self.dir
      base = ENV["XDG_CONFIG_HOME"]
      base = File.join(Dir.home, ".config") if base.nil? || base.empty?
      File.join(base, "hatchboxcli")
    end

    def self.path
      File.join(dir, FILENAME)
    end

    def initialize(path = self.class.path)
      @path = path
      @data = load
    end

    attr_reader :path

    def load
      return {} unless File.exist?(@path)

      parsed = YAML.safe_load(File.read(@path)) || {}
      parsed.is_a?(Hash) ? parsed : {}
    rescue StandardError
      {}
    end

    def [](key)
      @data[key.to_s]
    end

    def []=(key, value)
      if value.nil?
        @data.delete(key.to_s)
      else
        @data[key.to_s] = value
      end
      save
      value
    end

    def to_h
      @data.dup
    end

    def save
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, YAML.dump(@data))
      # config may hold a token; keep it private
      File.chmod(0o600, @path)
      @data
    end
  end
end
