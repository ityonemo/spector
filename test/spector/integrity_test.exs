defmodule SpectorTest.IntegrityTest do
  use ExUnit.Case, async: false

  alias Spector.Integrity

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SpectorTest.Repo)
  end

  describe "verify_savepoints/2" do
    test "returns :ok when savepoint matches replayed state" do
      {:ok, %{id: id}} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, %{id: ^id}} = Spector.update(Spector.get(SpectorTest.Savepointable, id), %{value: 10})
      {:ok, %{id: ^id}} = Spector.savepoint(SpectorTest.Savepointable, id)

      assert :ok = Integrity.verify_savepoints(SpectorTest.Savepointable, id)
    end

    test "returns :ok when all savepoints match" do
      {:ok, %{id: id}} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, %{id: ^id}} = Spector.savepoint(SpectorTest.Savepointable, id)
      {:ok, %{id: ^id}} = Spector.update(Spector.get(SpectorTest.Savepointable, id), %{value: 10})
      {:ok, %{id: ^id}} = Spector.savepoint(SpectorTest.Savepointable, id)

      assert :ok = Integrity.verify_savepoints(SpectorTest.Savepointable, id)
    end

    test "returns error when savepoint doesn't match replayed state" do
      {:ok, %{id: id}} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, %{id: ^id}} = Spector.savepoint(SpectorTest.Savepointable, id)

      # Manually corrupt the savepoint by updating the event payload directly
      [_, %{id: savepoint_event_id}] = Spector.all_events(SpectorTest.Savepointable, id)

      # Update the savepoint payload to have wrong data
      import Ecto.Query
      SpectorTest.Repo.update_all(
        from(e in SpectorTest.Event, where: e.id == ^savepoint_event_id),
        set: [payload: %{"name" => "Wrong", "value" => 999, "__version__" => 0}]
      )

      assert {:error, %Spector.Integrity.SavepointFailure{savepoint_id: ^id}} =
               Integrity.verify_savepoints(SpectorTest.Savepointable, id)
    end

    test "returns errors for each invalid savepoint" do
      {:ok, %{id: id}} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, %{id: ^id}} = Spector.savepoint(SpectorTest.Savepointable, id)
      {:ok, %{id: ^id}} = Spector.update(Spector.get(SpectorTest.Savepointable, id), %{value: 10})
      {:ok, %{id: ^id}} = Spector.savepoint(SpectorTest.Savepointable, id)

      # Corrupt the second savepoint only
      events = Spector.all_events(SpectorTest.Savepointable, id)
      %{id: second_savepoint_event_id} = events |> Enum.filter(&(&1.action == :savepoint)) |> List.last()

      import Ecto.Query
      SpectorTest.Repo.update_all(
        from(e in SpectorTest.Event, where: e.id == ^second_savepoint_event_id),
        set: [payload: %{"name" => "Wrong", "value" => 999, "__version__" => 0}]
      )

      assert {:error, %Spector.Integrity.SavepointFailure{savepoint_id: ^id}} =
               Integrity.verify_savepoints(SpectorTest.Savepointable, id)
    end

    test "raises when schema doesn't implement savepoint callback" do
      {:ok, %{id: id}} = Spector.insert(SpectorTest.Basic, %{name: "Test", value: 1})

      assert_raise RuntimeError, ~r/must implement savepoint\/2 callback/, fn ->
        Integrity.verify_savepoints(SpectorTest.Basic, id)
      end
    end

    test "returns :ok when no savepoints exist" do
      {:ok, %{id: id}} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})

      assert :ok = Integrity.verify_savepoints(SpectorTest.Savepointable, id)
    end

    test "detects buggy savepoint implementation that omits a field" do
      # Create record, then update the bugged field (which savepoint/2 intentionally omits)
      {:ok, %{id: id}} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, %{id: ^id}} = Spector.update(Spector.get(SpectorTest.Savepointable, id), %{bugged: "this will be lost"})
      {:ok, %{id: ^id}} = Spector.savepoint(SpectorTest.Savepointable, id)

      # Add another savepoint - this will reveal the bug because:
      # - Universe 0 (skips first savepoint): replays insert + update, has bugged="this will be lost"
      # - Universe 1 (uses first savepoint): starts from savepoint, bugged=nil
      # When we reach the second savepoint, these universes diverge
      {:ok, %{id: ^id}} = Spector.savepoint(SpectorTest.Savepointable, id)

      assert {:error, _failures} = Integrity.verify_savepoints(SpectorTest.Savepointable, id)
    end
  end

  describe "verify_hash_chain/1" do
    test "returns :ok for valid hash chain" do
      {:ok, %{id: id1}} = Spector.insert(SpectorTest.Hashed, %{name: "First", value: 1})
      {:ok, %{id: _id2}} = Spector.insert(SpectorTest.Hashed, %{name: "Second", value: 2})
      {:ok, %{id: ^id1}} = Spector.update(Spector.get(SpectorTest.Hashed, id1), %{value: 10})

      assert :ok = Integrity.verify_hash_chain(SpectorTest.HashedEvent)
    end

    test "returns :ok for empty table" do
      assert :ok = Integrity.verify_hash_chain(SpectorTest.HashedEvent)
    end

    test "returns error when hash chain is broken" do
      {:ok, %{id: _id1}} = Spector.insert(SpectorTest.Hashed, %{name: "First", value: 1})
      {:ok, %{id: _id2}} = Spector.insert(SpectorTest.Hashed, %{name: "Second", value: 2})

      # Get the second event and corrupt its hash
      import Ecto.Query
      [_, %{id: second_event_id}] =
        SpectorTest.Repo.all(from(e in SpectorTest.HashedEvent, order_by: [asc: e.inserted_at]))

      SpectorTest.Repo.update_all(
        from(e in SpectorTest.HashedEvent, where: e.id == ^second_event_id),
        set: [hash: :crypto.hash(:sha256, "corrupted")]
      )

      assert {:error, %Spector.Integrity.HashMismatch{event_id: ^second_event_id}} =
               Integrity.verify_hash_chain(SpectorTest.HashedEvent)
    end

    test "returns error when payload is tampered" do
      {:ok, %{id: _id}} = Spector.insert(SpectorTest.Hashed, %{name: "Test", value: 1})

      # Tamper with the payload without updating the hash
      [%{id: event_id}] = SpectorTest.Repo.all(SpectorTest.HashedEvent)

      import Ecto.Query
      SpectorTest.Repo.update_all(
        from(e in SpectorTest.HashedEvent, where: e.id == ^event_id),
        set: [payload: %{"name" => "Tampered", "value" => 999, "__version__" => 0}]
      )

      assert {:error, %Spector.Integrity.HashMismatch{event_id: ^event_id}} =
               Integrity.verify_hash_chain(SpectorTest.HashedEvent)
    end

    test "raises when events module is not hashed" do
      assert_raise RuntimeError, ~r/is not hashed/, fn ->
        Integrity.verify_hash_chain(SpectorTest.Event)
      end
    end
  end
end
