defmodule SpectorTest.SavepointTest do
  use ExUnit.Case, async: false

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SpectorTest.Repo)
  end

  describe "savepoint/1" do
    test "creates savepoint from record" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})

      assert {:ok, returned} = Spector.savepoint(record)
      assert returned.id == record.id
      assert returned.name == record.name
      assert returned.value == record.value

      events = Spector.all_events(SpectorTest.Savepointable, record.id)
      assert length(events) == 2
      assert List.last(events).action == :savepoint
    end

    test "raises when record state doesn't match replayed state" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})

      # Create a stale record by updating but using old reference
      stale_record = record
      {:ok, _updated} = Spector.update(record, %{value: 100})

      assert_raise RuntimeError, ~r/does not match reference record/, fn ->
        Spector.savepoint(stale_record)
      end
    end

    test "raises when schema doesn't implement savepoint callback" do
      {:ok, basic} = Spector.insert(SpectorTest.Basic, %{name: "Test", value: 1})

      assert_raise RuntimeError, ~r/must implement savepoint\/2 callback/, fn ->
        Spector.savepoint(basic)
      end
    end
  end

  describe "savepoint/2" do
    test "raises when schema doesn't implement savepoint callback" do
      {:ok, basic} = Spector.insert(SpectorTest.Basic, %{name: "Test", value: 1})

      assert_raise RuntimeError, ~r/must implement savepoint\/2 callback/, fn ->
        Spector.savepoint(SpectorTest.Basic, basic.id)
      end
    end

    test "creates a savepoint event when schema implements savepoint callback" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})

      assert {:ok, returned} = Spector.savepoint(SpectorTest.Savepointable, record.id)
      assert returned.id == record.id
      assert returned.name == record.name
      assert returned.value == record.value

      # Verify the savepoint event was created
      events = Spector.all_events(SpectorTest.Savepointable, record.id)
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

      assert {:ok, returned} = Spector.savepoint(SpectorTest.Savepointable, record.id)
      assert returned.id == record.id

      events = Spector.all_events(SpectorTest.Savepointable, record.id)
      savepoint_event = List.last(events)

      assert savepoint_event.action == :savepoint
      assert savepoint_event.payload["name"] == "Test"
      assert savepoint_event.payload["value"] == 100
    end

    test "replay starts from most recent savepoint" do
      # Create record and make some updates
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Initial", value: 1})
      {:ok, record} = Spector.update(record, %{value: 10})
      {:ok, record} = Spector.update(record, %{name: "Changed"})

      # Create savepoint at current state (name: "Changed", value: 10)
      {:ok, _record} = Spector.savepoint(SpectorTest.Savepointable, record.id)

      # Make more updates after savepoint
      {:ok, record} = Spector.update(record, %{value: 100})
      {:ok, record} = Spector.update(record, %{name: "Final"})

      # Verify final state
      assert record.name == "Final"
      assert record.value == 100

      # Verify get produces the same result (this uses roll_forward which should start from savepoint)
      brought_up = Spector.get(SpectorTest.Savepointable, record.id)
      assert brought_up.name == "Final"
      assert brought_up.value == 100
    end

    test "replay correctly uses savepoint state as base" do
      # Create a record and update it many times
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Start", value: 0})

      # Make 5 updates before savepoint
      {:ok, record} = Spector.update(record, %{value: 1})
      {:ok, record} = Spector.update(record, %{value: 2})
      {:ok, record} = Spector.update(record, %{value: 3})
      {:ok, record} = Spector.update(record, %{value: 4})
      {:ok, record} = Spector.update(record, %{value: 5})

      # Savepoint at value: 5
      {:ok, _record} = Spector.savepoint(SpectorTest.Savepointable, record.id)

      # Make more updates after savepoint
      {:ok, record} = Spector.update(record, %{value: 50})
      {:ok, record} = Spector.update(record, %{name: "End"})

      # Verify get works correctly (uses roll_forward which should start from savepoint)
      brought_up = Spector.get(SpectorTest.Savepointable, record.id)
      assert brought_up.name == "End"
      assert brought_up.value == 50

      # Verify events count - should have insert + 5 updates + savepoint + 2 updates = 9
      events = Spector.all_events(SpectorTest.Savepointable, record.id)
      assert length(events) == 9
    end
  end
end
