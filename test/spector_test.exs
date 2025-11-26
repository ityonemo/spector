defmodule SpectorTest do
  use ExUnit.Case

  alias SpectorTest.Event

  describe "Event schema" do
    test "has expected fields" do
      event = %Event{}

      assert Map.has_key?(event, :id)
      assert Map.has_key?(event, :parent_id)
      assert Map.has_key?(event, :payload)
      assert Map.has_key?(event, :schema)
      assert Map.has_key?(event, :action)
    end

    test "schema field is an enum" do
      {:parameterized, {Ecto.Enum, _}} = Event.__schema__(:type, :schema)
    end

    test "action field is an enum" do
      {:parameterized, {Ecto.Enum, _}} = Event.__schema__(:type, :action)
    end
  end
end
