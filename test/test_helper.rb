# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "stringio"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

module TestHelper
  # Run a block with a clean, isolated config dir and no ambient token env vars.
  def with_clean_env
    Dir.mktmpdir do |dir|
      saved = ENV.to_h.slice("XDG_CONFIG_HOME", "HATCHBOX_API_KEY", "HATCHBOX_TOKEN",
                             "HATCHBOX_API_TOKEN", "HATCHBOX_ACCOUNT_ID", "HATCHBOX_API_URL")
      ENV["XDG_CONFIG_HOME"] = dir
      %w[HATCHBOX_API_KEY HATCHBOX_TOKEN HATCHBOX_API_TOKEN HATCHBOX_ACCOUNT_ID].each { |k| ENV.delete(k) }
      yield dir
    ensure
      saved.each { |k, v| ENV[k] = v }
      %w[XDG_CONFIG_HOME HATCHBOX_API_KEY HATCHBOX_TOKEN HATCHBOX_API_TOKEN
         HATCHBOX_ACCOUNT_ID HATCHBOX_API_URL].each { |k| ENV.delete(k) unless saved.key?(k) }
    end
  end

  # Capture $stdout/$stderr produced by a block.
  def capture_io
    out = StringIO.new
    err = StringIO.new
    old_out = $stdout
    old_err = $stderr
    $stdout = out
    $stderr = err
    yield
    [out.string, err.string]
  ensure
    $stdout = old_out
    $stderr = old_err
  end
end
