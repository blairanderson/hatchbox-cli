# frozen_string_literal: true

require "socket"
require "json"
require_relative "mock_state"

module Eval
  # A tiny, dependency-free HTTP mock of the Hatchbox API, backed by MockState.
  #
  #   Real API routes (require `Authorization: Bearer <token>`):
  #     GET  /api/v1/accounts
  #     GET  /api/v1/accounts/:id/apps
  #     GET  /api/v1/apps/:id
  #     GET  /api/v1/apps/:id/processes
  #     GET  /api/v1/apps/:id/processes/:pid
  #     POST /api/v1/apps/:id/processes/:pid/restart
  #
  #   Test-only control plane (no auth — local only):
  #     POST /__control/processes/down   -> mark every process inactive
  #     POST /__control/processes/up     -> mark every process active
  #     GET  /__control/state            -> dump world state
  class MockServer
    attr_reader :port, :state

    def initialize(state, port: 0, host: "127.0.0.1")
      @state = state
      @host = host
      @server = TCPServer.new(host, port)
      @port = @server.addr[1]
      @running = false
    end

    def base_url
      "http://#{@host}:#{@port}/api/v1"
    end

    # Run in a background thread (used by tests). Returns the thread.
    def start_async
      @running = true
      @thread = Thread.new { accept_loop }
      self
    end

    # Run in the foreground (used when launched as a script).
    def start
      @running = true
      accept_loop
    end

    def stop
      @running = false
      @server.close unless @server.closed?
      @thread&.kill
    end

    private

    def accept_loop
      loop do
        break unless @running

        client = @server.accept
        Thread.new(client) { |c| handle_client(c) }
      end
    rescue IOError, Errno::EBADF
      # server closed
    end

    def handle_client(client)
      req = parse_request(client)
      return client.close if req.nil?

      status, body = route(req)
      write_response(client, status, body)
    rescue StandardError => e
      write_response(client, 500, { "error" => e.message })
    ensure
      client.close unless client.closed?
    end

    def parse_request(client)
      request_line = client.gets
      return nil if request_line.nil?

      method, path, = request_line.split(" ")
      headers = {}
      while (line = client.gets)
        line = line.strip
        break if line.empty?

        key, value = line.split(":", 2)
        headers[key.downcase.strip] = value.to_s.strip
      end

      body = nil
      if (len = headers["content-length"]&.to_i) && len.positive?
        body = client.read(len)
      end

      { method: method, path: path.split("?").first, headers: headers, body: body }
    end

    def route(req)
      path = req[:path]
      method = req[:method]

      # Control plane (no auth).
      return control(method, path) if path.start_with?("/__control")

      # Everything else needs a valid bearer token.
      return [401, ""] unless authorized?(req)

      case [method, path]
      in ["GET", "/api/v1/accounts"]
        [200, @state.accounts]
      else
        dynamic_route(method, path)
      end
    end

    def dynamic_route(method, path)
      case path
      when %r{\A/api/v1/accounts/([^/]+)/apps\z}
        acct = @state.account(Regexp.last_match(1))
        return not_found("Account") unless acct

        [200, @state.apps_for_account(acct["id"])]
      when %r{\A/api/v1/apps/([^/]+)/processes\z}
        return not_found("App") unless @state.app(Regexp.last_match(1))

        [200, @state.processes]
      when %r{\A/api/v1/apps/([^/]+)/processes/([^/]+)/restart\z}
        return [405, { "error" => "method not allowed" }] unless method == "POST"

        proc_obj = @state.process(Regexp.last_match(2))
        return not_found("Process") unless proc_obj

        [200, { "id" => proc_obj["id"], "restarting" => true }]
      when %r{\A/api/v1/apps/([^/]+)/processes/([^/]+)\z}
        proc_obj = @state.process(Regexp.last_match(2))
        return not_found("Process") unless proc_obj

        [200, proc_obj]
      when %r{\A/api/v1/apps/([^/]+)\z}
        app = @state.app(Regexp.last_match(1))
        return not_found("App") unless app

        [200, app]
      else
        not_found("Route")
      end
    end

    def control(method, path)
      case [method, path]
      in ["POST", "/__control/processes/down"]
        @state.all_down!
        [200, { "ok" => true, "all_down" => @state.all_down? }]
      in ["POST", "/__control/processes/up"]
        @state.all_up!
        [200, { "ok" => true, "all_up" => @state.all_up? }]
      in ["GET", "/__control/state"]
        [200, { "processes" => @state.processes, "all_down" => @state.all_down?, "all_up" => @state.all_up? }]
      else
        [404, { "error" => "unknown control route" }]
      end
    end

    def authorized?(req)
      auth = req[:headers]["authorization"].to_s
      return false unless auth.start_with?("Bearer ")

      @state.valid_token?(auth.sub("Bearer ", ""))
    end

    def not_found(resource)
      [404, { "error" => "#{resource} not found" }]
    end

    def write_response(client, status, body)
      payload =
        if body.nil? || body == ""
          ""
        else
          JSON.generate(body)
        end

      client.write("HTTP/1.1 #{status} #{status_text(status)}\r\n")
      client.write("Content-Type: application/json\r\n")
      client.write("Content-Length: #{payload.bytesize}\r\n")
      client.write("Connection: close\r\n")
      client.write("\r\n")
      client.write(payload)
    end

    def status_text(status)
      {
        200 => "OK", 201 => "Created", 204 => "No Content",
        401 => "Unauthorized", 402 => "Payment Required", 404 => "Not Found",
        405 => "Method Not Allowed", 409 => "Conflict", 422 => "Unprocessable Entity",
        500 => "Internal Server Error"
      }[status] || "OK"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  scenario = ARGV[0] || File.join(__dir__, "scenario.json")
  port = (ENV["PORT"] || "4567").to_i
  state = Eval::MockState.from_file(scenario)
  server = Eval::MockServer.new(state, port: port)
  puts "Mock Hatchbox API listening on #{server.base_url}"
  puts "  token: #{state.token}"
  puts "  control: POST /__control/processes/{down,up}   GET /__control/state"
  puts "Point the CLI at it:  export HATCHBOX_API_URL=#{server.base_url}"
  trap("INT") do
    puts "\nStopping."
    server.stop
    exit 0
  end
  server.start
end
