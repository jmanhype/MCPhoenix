defmodule CloudflareDurable.ClientTest do
  @moduledoc """
  Tests for the CloudflareDurable.Client module.
  """
  use ExUnit.Case
  import Mock

  alias CloudflareDurable.Client

  describe "initialize/3" do
    test "calls the initialize endpoint and returns the response" do
      with_mock Finch, [request: fn _, _ -> {:ok, %Finch.Response{status: 200, body: ~s({"success": true})}} end] do
        assert {:ok, %{"success" => true}} = Client.initialize("test-id", %{value: 0})
      end
    end
  end

  describe "call_method/4" do
    test "calls the method endpoint and returns the response" do
      with_mock Finch, [request: fn _, _ -> {:ok, %Finch.Response{status: 200, body: ~s({"result": {"value": 1}})}} end] do
        assert {:ok, %{"result" => %{"value" => 1}}} = Client.call_method("test-id", "increment", %{increment: 1})
      end
    end
  end
end 