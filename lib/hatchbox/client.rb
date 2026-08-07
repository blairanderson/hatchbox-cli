# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Hatchbox
  # Raised for any non-success API response. Carries the HTTP status so the CLI
  # can print a friendly message and exit non-zero.
  class APIError < StandardError
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      @status = status
      @body = body
      super(message)
    end
  end

  # Raised when no API token could be resolved from flag/env/config.
  class MissingTokenError < StandardError; end

  # Minimal Net::HTTP JSON client for the Hatchbox API.
  class Client
    DEFAULT_BASE_URL = "https://app.hatchbox.io/api/v1"

    def self.base_url
      url = ENV["HATCHBOX_API_URL"]
      url.nil? || url.empty? ? DEFAULT_BASE_URL : url.sub(%r{/+\z}, "")
    end

    def initialize(token:, base_url: self.class.base_url)
      raise MissingTokenError, "No API token provided" if token.nil? || token.empty?

      @token = token
      @base = URI.parse(base_url)
    end

    def get(path, query = nil)
      request(:get, path, query: query)
    end

    def post(path, body = nil)
      request(:post, path, body: body)
    end

    def put(path, body = nil)
      request(:put, path, body: body)
    end

    def patch(path, body = nil)
      request(:patch, path, body: body)
    end

    def delete(path, body = nil)
      request(:delete, path, body: body)
    end

    def request(method, path, body: nil, query: nil)
      uri = build_uri(path, query)
      req = build_request(method, uri, body)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 15
      http.read_timeout = 60

      res = http.request(req)
      handle(res)
    rescue SocketError, Errno::ECONNREFUSED => e
      raise APIError, "Could not reach Hatchbox API at #{@base}: #{e.message}"
    end

    private

    def build_uri(path, query)
      full = @base.path.sub(%r{/+\z}, "") + "/" + path.sub(%r{\A/+}, "")
      uri = @base.dup
      uri.path = full
      if query && !query.empty?
        uri.query = URI.encode_www_form(query)
      end
      uri
    end

    def build_request(method, uri, body)
      klass = {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post,
        put: Net::HTTP::Put,
        patch: Net::HTTP::Patch,
        delete: Net::HTTP::Delete
      }.fetch(method)

      req = klass.new(uri)
      req["Authorization"] = "Bearer #{@token}"
      req["Accept"] = "application/json"
      req["User-Agent"] = "hatchbox-cli/#{Hatchbox::VERSION}"
      if body
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end
      req
    end

    def handle(res)
      code = res.code.to_i
      parsed = parse_body(res.body)

      return parsed if code.between?(200, 299)

      raise APIError.new(error_message(code, parsed), status: code, body: parsed)
    end

    def parse_body(body)
      return nil if body.nil? || body.strip.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end

    def error_message(code, parsed)
      detail =
        if parsed.is_a?(Hash)
          parsed["error"] || (parsed["errors"] && Array(parsed["errors"]).join("; "))
        elsif parsed.is_a?(String) && !parsed.empty?
          parsed
        end

      case code
      when 401
        "Unauthorized (401): the API token is missing or invalid."
      when 402
        "Payment required (402): #{detail || 'an active subscription is required.'}"
      when 404
        "Not found (404): #{detail || 'resource not found or not accessible with this token.'}"
      when 409
        "Conflict (409): #{detail || 'the resource is busy or already exists.'}"
      when 422
        "Validation failed (422): #{detail || 'the request was rejected.'}"
      else
        "API error (#{code})#{detail ? ": #{detail}" : ''}"
      end
    end
  end
end
