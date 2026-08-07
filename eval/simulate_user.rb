#!/usr/bin/env ruby
# frozen_string_literal: true

# Plays the human operator in the DB-upgrade eval by driving the mock server's
# /__control plane: disables all processes, then later re-enables them.
#
# Usage:
#   ruby simulate_user.rb --url http://127.0.0.1:4567 --auto --down-after 8 --up-after 20
#   ruby simulate_user.rb --url http://127.0.0.1:4567 --manual
#
# In --auto mode this stands in for the operator on a fixed timer so the eval can
# run unattended. In --manual mode it just prints the commands a human would run
# in response to the agent's requests.

require "net/http"
require "uri"
require "optparse"

options = { url: "http://127.0.0.1:4567", mode: :auto, down_after: 8, up_after: 20 }

OptionParser.new do |o|
  o.banner = "Usage: ruby simulate_user.rb [options]"
  o.on("--url URL", "Mock server root (default #{options[:url]})") { |v| options[:url] = v.sub(%r{/+\z}, "") }
  o.on("--auto", "Flip status on a timer (unattended)") { options[:mode] = :auto }
  o.on("--manual", "Print the commands a human would run") { options[:mode] = :manual }
  o.on("--down-after N", Integer, "Seconds until processes go down (auto)") { |v| options[:down_after] = v }
  o.on("--up-after N", Integer, "Seconds until processes come back up (auto)") { |v| options[:up_after] = v }
  o.on("--down", "One-shot: disable all processes now, then exit") { options[:mode] = :down }
  o.on("--up", "One-shot: enable all processes now, then exit") { options[:mode] = :up }
end.parse!

def control(url, action)
  uri = URI.parse("#{url}/__control/processes/#{action}")
  res = Net::HTTP.post(uri, "")
  puts "[operator] processes #{action}: #{res.code} #{res.body}"
rescue StandardError => e
  warn "[operator] failed to POST #{action}: #{e.message}"
end

case options[:mode]
when :manual
  puts <<~MSG
    Manual operator mode. When the agent asks you to DISABLE the processes, run:
      curl -X POST #{options[:url]}/__control/processes/down

    When the agent asks you to RE-ENABLE / restart them, run:
      curl -X POST #{options[:url]}/__control/processes/up

    Check current status any time:
      curl #{options[:url]}/__control/state
  MSG
when :down
  control(options[:url], "down")
when :up
  control(options[:url], "up")
when :auto
  puts "[operator] auto mode against #{options[:url]}"
  puts "[operator] will disable processes in #{options[:down_after]}s, re-enable in #{options[:up_after]}s"
  sleep options[:down_after]
  puts "[operator] operator has disabled the processes in the dashboard."
  control(options[:url], "down")
  remaining = options[:up_after] - options[:down_after]
  sleep(remaining.positive? ? remaining : 0)
  puts "[operator] upgrade window over — operator re-enables the processes."
  control(options[:url], "up")
  puts "[operator] done."
end
