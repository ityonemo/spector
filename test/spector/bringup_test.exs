defmodule SpectorTest.BringupTest do
  use ExUnit.Case

  alias SpectorTest.BringupSchema
  alias SpectorTest.Repo
  alias SpectorTest.Event

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "Spector.bringup/3 timestamp handling" do
    test "default bringup resets timestamps to now" do
      # Insert a record with old timestamps directly
      past = ~N[2020-01-01 00:00:00]

      {:ok, %{id: old_id}} =
        Repo.insert(%BringupSchema{
          id: Ecto.UUID.generate(),
          name: "Alice",
          value: 1,
          inserted_at: past,
          updated_at: past
        })

      # Default bringup resets timestamps
      {:ok, [new_record]} = Spector.bringup(BringupSchema)

      # Original was deleted
      refute Repo.get(BringupSchema, old_id)

      assert new_record.name == "Alice"
      # Timestamps should be recent (within last minute)
      assert NaiveDateTime.diff(NaiveDateTime.utc_now(), new_record.inserted_at, :second) < 60
      assert NaiveDateTime.diff(NaiveDateTime.utc_now(), new_record.updated_at, :second) < 60
    end

    test "bringup with :import action and attr_fn preserves timestamps" do
      # Insert a record with old timestamps directly
      past = ~N[2020-01-01 00:00:00]

      {:ok, %{id: old_id}} =
        Repo.insert(%BringupSchema{
          id: Ecto.UUID.generate(),
          name: "Bob",
          value: 2,
          inserted_at: past,
          updated_at: past
        })

      # Use :import action with attr_fn that includes timestamps
      attr_fn = fn record ->
        %{
          name: record.name,
          value: record.value,
          inserted_at: record.inserted_at,
          updated_at: record.updated_at
        }
      end

      {:ok, [new_record]} = Spector.bringup(BringupSchema, action: :import, attr_fn: attr_fn)

      # Original was deleted
      refute Repo.get(BringupSchema, old_id)

      # Name has "imported_" prefix from the :import changeset
      assert new_record.name == "imported_Bob"
      # Timestamps should be preserved
      assert new_record.inserted_at == past
      assert new_record.updated_at == past
    end
  end

  describe "Spector.bringup/3 with custom action" do
    test "uses a different changeset for :import action" do
      # Insert a record directly (simulating pre-Spector data)
      {:ok, %{id: old_id}} =
        Repo.insert(%BringupSchema{id: Ecto.UUID.generate(), name: "Alice", value: 1})

      # Bringup with :import action triggers the import changeset
      assert {:ok, [new_record]} = Spector.bringup(BringupSchema, action: :import)

      # Original was deleted
      refute Repo.get(BringupSchema, old_id)

      # New record has "imported_" prefix from the :import changeset
      assert new_record.name == "imported_Alice"
      assert new_record.value == 1

      # Event has the custom action
      [event] = Repo.all(Event)
      assert event.action == :import
      assert event.parent_id == new_record.id
    end
  end

  describe "Spector.bringup/3 with custom attr_fn" do
    test "transforms attributes before inserting" do
      # Insert a record directly
      {:ok, %{id: old_id}} =
        Repo.insert(%BringupSchema{id: Ecto.UUID.generate(), name: "alice", value: 10})

      # Custom attr_fn that uppercases name and doubles value
      attr_fn = fn record ->
        %{
          name: String.upcase(record.name),
          value: record.value * 2
        }
      end

      # Using :import action, so name gets "imported_" prefix after uppercase
      assert {:ok, [new_record]} =
               Spector.bringup(BringupSchema, action: :import, attr_fn: attr_fn)

      # Original was deleted
      refute Repo.get(BringupSchema, old_id)

      # New record has transformed attributes (uppercase then prefixed)
      assert new_record.name == "imported_ALICE"
      assert new_record.value == 20
    end

    test "can add additional attributes during bringup" do
      # Insert records without a value
      {:ok, _} = Repo.insert(%BringupSchema{id: Ecto.UUID.generate(), name: "Bob", value: nil})

      # Custom attr_fn that adds a default value
      attr_fn = fn record ->
        %{
          name: record.name,
          value: record.value || 99
        }
      end

      assert {:ok, [new_record]} =
               Spector.bringup(BringupSchema, action: :import, attr_fn: attr_fn)

      assert new_record.name == "imported_Bob"
      assert new_record.value == 99
    end
  end

  describe "Spector.bringup/2 with transfer function" do
    test "transfer function receives old and new records" do
      # Insert a record directly
      {:ok, old_record} =
        Repo.insert(%BringupSchema{id: Ecto.UUID.generate(), name: "Transfer", value: 42})

      test_pid = self()

      transfer_fn = fn old, new ->
        send(test_pid, {:transfer, old, new})
      end

      {:ok, [new_record]} = Spector.bringup(BringupSchema, transfer: transfer_fn)

      # Verify transfer function was called with correct parameters
      assert_receive {:transfer, received_old, received_new}
      assert received_old.id == old_record.id
      assert received_old.name == "Transfer"
      assert received_old.value == 42
      assert received_new.id == new_record.id
      assert received_new.name == "Transfer"
      assert received_new.value == 42
    end
  end
end
