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

  describe "verify_hash_chain/1" do
    test "returns :ok for valid hash chain" do
      {:ok, record1} = Spector.insert(SpectorTest.Hashed, %{name: "First", value: 1})
      {:ok, _record2} = Spector.insert(SpectorTest.Hashed, %{name: "Second", value: 2})
      {:ok, _record1} = Spector.update(record1, %{value: 10})

      assert :ok = Integrity.verify_hash_chain(SpectorTest.HashedEvent)
    end

    test "returns :ok for empty table" do
      assert :ok = Integrity.verify_hash_chain(SpectorTest.HashedEvent)
    end

    test "returns error when hash chain is broken" do
      {:ok, _record1} = Spector.insert(SpectorTest.Hashed, %{name: "First", value: 1})
      {:ok, _record2} = Spector.insert(SpectorTest.Hashed, %{name: "Second", value: 2})

      # Get the second event and corrupt its hash
      import Ecto.Query
      events = SpectorTest.Repo.all(from(e in SpectorTest.HashedEvent, order_by: [asc: e.id]))
      second_event = Enum.at(events, 1)

      SpectorTest.Repo.update_all(
        from(e in SpectorTest.HashedEvent, where: e.id == ^second_event.id),
        set: [hash: :crypto.hash(:sha256, "corrupted")]
      )

      assert {:error, {:hash_mismatch, event_id, _expected, _actual}} =
               Integrity.verify_hash_chain(SpectorTest.HashedEvent)

      assert event_id == second_event.id
    end

    test "returns error when payload is tampered" do
      {:ok, _record} = Spector.insert(SpectorTest.Hashed, %{name: "Test", value: 1})

      # Tamper with the payload without updating the hash
      events = SpectorTest.Repo.all(SpectorTest.HashedEvent)
      event = List.first(events)

      import Ecto.Query
      SpectorTest.Repo.update_all(
        from(e in SpectorTest.HashedEvent, where: e.id == ^event.id),
        set: [payload: %{"name" => "Tampered", "value" => 999, "__version__" => 0}]
      )

      assert {:error, {:hash_mismatch, event_id, _, _}} =
               Integrity.verify_hash_chain(SpectorTest.HashedEvent)

      assert event_id == event.id
    end

    test "returns error when events module is not hashed" do
      assert {:error, :not_hashed} = Integrity.verify_hash_chain(SpectorTest.Event)
    end
  end
end
