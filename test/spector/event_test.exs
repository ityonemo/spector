defmodule Spector.EventTest do
  use ExUnit.Case

  alias Spector.Event

  describe "schema" do
    test "has expected fields" do
      event = %Event{}

      assert Map.has_key?(event, :id)
      assert Map.has_key?(event, :parent_id)
      assert Map.has_key?(event, :payload)
      assert Map.has_key?(event, :schema)
      assert Map.has_key?(event, :action)
    end
  end
end
