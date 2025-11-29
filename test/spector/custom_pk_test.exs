defmodule SpectorTest.CustomPKTest do
  use ExUnit.Case

  alias SpectorTest.CustomPK
  alias SpectorTest.Event
  alias SpectorTest.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "schema with custom primary key name" do
    test "insert creates an event and returns the struct" do
      {:ok, %CustomPK{uuid: uuid, name: "Bob", value: 42}} =
        Spector.insert(CustomPK, %{name: "Bob", value: 42})

      assert uuid != nil
      assert [%{action: :insert}] = Event.list_by_parent_id(uuid, CustomPK)
    end

    test "get reconstructs the struct from events" do
      {:ok, %CustomPK{uuid: uuid}} = Spector.insert(CustomPK, %{name: "Alice", value: 1})

      assert %CustomPK{uuid: ^uuid, name: "Alice", value: 1} = Spector.get(CustomPK, uuid)
    end

    test "event_log association works with custom primary key" do
      {:ok, %CustomPK{uuid: uuid}} = Spector.insert(CustomPK, %{name: "Alice", value: 1})
      record = Repo.get!(CustomPK, uuid)
      {:ok, _} = Spector.update(record, %{value: 2})

      record = Repo.get!(CustomPK, uuid) |> Repo.preload(:log)

      assert length(record.log) == 2
      assert [%{action: :insert}, %{action: :update}] = record.log
    end

    test "bringup works with custom primary key" do
      # Insert a record directly (simulating pre-Spector data)
      {:ok, %{uuid: old_uuid}} =
        Repo.insert(%CustomPK{uuid: Ecto.UUID.generate(), name: "Bob", value: 10})

      # Bringup should migrate to Spector management
      assert {:ok, [new_record]} = Spector.bringup(CustomPK)

      # Original was deleted
      refute Repo.get(CustomPK, old_uuid)

      # New record exists with different UUID
      assert new_record.name == "Bob"
      assert new_record.value == 10
      refute new_record.uuid == old_uuid

      # Event was created
      assert [%{action: :insert}] = Event.list_by_parent_id(new_record.uuid, CustomPK)
    end
  end
end
