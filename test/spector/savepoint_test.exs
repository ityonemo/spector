defmodule SpectorTest.SavepointTest do
  use ExUnit.Case, async: false

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SpectorTest.Repo)
  end

  describe "savepoint/1" do
    test "returns error when schema doesn't implement savepoint callback" do
      {:ok, basic} = Spector.insert(SpectorTest.Basic, %{name: "Test", value: 1})

      assert {:error, :savepoint_not_implemented} = Spector.savepoint(basic)
    end

    test "creates a savepoint event when schema implements savepoint callback" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})

      assert {:ok, ^record} = Spector.savepoint(record)

      # Verify the savepoint event was created
      events = SpectorTest.Event.list_by_parent_id(record.id, SpectorTest.Savepointable)
      assert length(events) == 2
      assert Enum.at(events, 0).action == :insert
      assert Enum.at(events, 1).action == :savepoint

      # Verify the savepoint payload contains the full state
      savepoint_event = Enum.at(events, 1)
      assert savepoint_event.payload["name"] == "Test"
      assert savepoint_event.payload["value"] == 1
    end

    test "savepoint captures current state after updates" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, record} = Spector.update(record, %{value: 100})

      assert {:ok, ^record} = Spector.savepoint(record)

      events = SpectorTest.Event.list_by_parent_id(record.id, SpectorTest.Savepointable)
      savepoint_event = List.last(events)

      assert savepoint_event.action == :savepoint
      assert savepoint_event.payload["name"] == "Test"
      assert savepoint_event.payload["value"] == 100
    end
  end
end
