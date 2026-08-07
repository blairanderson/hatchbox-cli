# frozen_string_literal: true

require_relative "test_helper"
require "hatchbox/version"
require "hatchbox/client"
require_relative "../eval/mock_state"
require_relative "../eval/mock_server"

class TestClient < Minitest::Test
  include TestHelper

  def setup
    data = JSON.parse(File.read(File.expand_path("../eval/scenario.json", __dir__)))
    @state = Eval::MockState.new(data)
    @server = Eval::MockServer.new(@state, port: 0).start_async
    @base = @server.base_url
    @token = @state.token
  end

  def teardown
    @server.stop
  end

  def test_get_accounts_with_valid_token
    client = Hatchbox::Client.new(token: @token, base_url: @base)
    accounts = client.get("/accounts")
    assert_equal 1, accounts.length
    assert_equal "acme-inc", accounts.first["name"]
  end

  def test_invalid_token_raises_401
    client = Hatchbox::Client.new(token: "nope", base_url: @base)
    err = assert_raises(Hatchbox::APIError) { client.get("/accounts") }
    assert_equal 401, err.status
  end

  def test_missing_token_raises_before_request
    assert_raises(Hatchbox::MissingTokenError) { Hatchbox::Client.new(token: "", base_url: @base) }
  end

  def test_404_maps_to_error
    client = Hatchbox::Client.new(token: @token, base_url: @base)
    err = assert_raises(Hatchbox::APIError) { client.get("/accounts/999/apps") }
    assert_equal 404, err.status
  end

  def test_post_control_and_reflect_status
    client = Hatchbox::Client.new(token: @token, base_url: @base)
    @state.all_down!
    procs = client.get("/apps/42/processes")
    assert(procs.all? { |p| p["active"] == false })
  end
end
