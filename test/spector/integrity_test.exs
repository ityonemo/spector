defmodule SpectorTest.IntegrityTest do
  use ExUnit.Case, async: false

  alias Spector.Integrity

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SpectorTest.Repo)
  end

  describe "verify_savepoints/2" do
    test "returns :ok when savepoint matches replayed state" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, record} = Spector.update(record, %{value: 10})
      {:ok, _record} = Spector.savepoint(record)

      assert :ok = Integrity.verify_savepoints(SpectorTest.Savepointable, record.id)
    end

    test "returns :ok when all savepoints match" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, record} = Spector.savepoint(record)
      {:ok, record} = Spector.update(record, %{value: 10})
      {:ok, _record} = Spector.savepoint(record)

      assert :ok = Integrity.verify_savepoints(SpectorTest.Savepointable, record.id)
    end

    test "returns error when savepoint doesn't match replayed state" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, _record} = Spector.savepoint(record)

      # Manually corrupt the savepoint by updating the event payload directly
      events = SpectorTest.Event.list_by_parent_id(record.id, SpectorTest.Savepointable)
      savepoint_event = List.last(events)

      # Update the savepoint payload to have wrong data
      import Ecto.Query
      SpectorTest.Repo.update_all(
        from(e in SpectorTest.Event, where: e.id == ^savepoint_event.id),
        set: [payload: %{"name" => "Wrong", "value" => 999, "__version__" => 0}]
      )

      assert {:error, failures} = Integrity.verify_savepoints(SpectorTest.Savepointable, record.id)
      assert length(failures) == 1
      assert [{_event_id, {:savepoint_mismatch, mismatches}}] = failures
      assert :name in Keyword.keys(mismatches)
      assert :value in Keyword.keys(mismatches)
    end

    test "returns errors for each invalid savepoint" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, record} = Spector.savepoint(record)
      {:ok, record} = Spector.update(record, %{value: 10})
      {:ok, _record} = Spector.savepoint(record)

      # Corrupt the second savepoint only
      events = SpectorTest.Event.list_by_parent_id(record.id, SpectorTest.Savepointable)
      second_savepoint = events |> Enum.filter(&(&1.action == :savepoint)) |> List.last()

      import Ecto.Query
      SpectorTest.Repo.update_all(
        from(e in SpectorTest.Event, where: e.id == ^second_savepoint.id),
        set: [payload: %{"name" => "Wrong", "value" => 999, "__version__" => 0}]
      )

      assert {:error, failures} = Integrity.verify_savepoints(SpectorTest.Savepointable, record.id)
      assert length(failures) == 1
      assert [{_event_id, {:savepoint_mismatch, _}}] = failures
    end

    test "returns error when schema doesn't implement savepoint callback" do
      {:ok, basic} = Spector.insert(SpectorTest.Basic, %{name: "Test", value: 1})

      assert {:error, :savepoint_not_implemented} = Integrity.verify_savepoints(SpectorTest.Basic, basic.id)
    end

    test "returns :ok when no savepoints exist" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})

      assert :ok = Integrity.verify_savepoints(SpectorTest.Savepointable, record.id)
    end
  end
end
