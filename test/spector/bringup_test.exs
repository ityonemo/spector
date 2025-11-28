defmodule SpectorTest.BringupTest do
  use ExUnit.Case

  alias SpectorTest.BringupSchema
  alias SpectorTest.Repo
  alias SpectorTest.Event

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "Spector.bringup/3 with custom action" do
    test "uses a different changeset for :import action" do
      # Insert a record directly (simulating pre-Spector data)
      {:ok, %{id: old_id}} = Repo.insert(%BringupSchema{id: Ecto.UUID.generate(), name: "Alice", value: 1})

      # Bringup with :import action triggers the import changeset
      assert {:ok, [new_record]} = Spector.bringup(BringupSchema, :import)

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
      {:ok, %{id: old_id}} = Repo.insert(%BringupSchema{id: Ecto.UUID.generate(), name: "alice", value: 10})

      # Custom attr_fn that uppercases name and doubles value
      attr_fn = fn record ->
        %{
          name: String.upcase(record.name),
          value: record.value * 2
        }
      end

      # Using :import action, so name gets "imported_" prefix after uppercase
      assert {:ok, [new_record]} = Spector.bringup(BringupSchema, :import, attr_fn)

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

      assert {:ok, [new_record]} = Spector.bringup(BringupSchema, :import, attr_fn)

      assert new_record.name == "imported_Bob"
      assert new_record.value == 99
    end
  end
end
