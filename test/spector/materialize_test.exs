defmodule SpectorTest.MaterializeTest do
  @moduledoc false

  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias SpectorTest.Basic
  alias SpectorTest.Event
  alias SpectorTest.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "Spector.materialize/2" do
    test "materializes a record from events into the database" do
      # Insert a record normally (creates record + event)
      {:ok, %{id: id, name: "Bob", value: 99}} = Spector.insert(Basic, %{name: "Bob", value: 99})

      # Delete the record from the database (but events remain)
      Repo.delete!(%Basic{id: id})
      assert Repo.get(Basic, id) == nil

      # Materialize should recreate the record from events
      assert {:ok, %{id: ^id, name: "Bob", value: 99}} = Spector.materialize(Event, id)

      # Record now exists in the database
      assert %{id: ^id, name: "Bob", value: 99} = Repo.get!(Basic, id)
    end

    test "materializes record with full event history including updates" do
      # Insert and update a record
      {:ok, %{id: id}} = Spector.insert(Basic, %{name: "Bob", value: 99})
      record = Repo.get!(Basic, id)
      {:ok, _} = Spector.update(record, %{value: 100})
      record = Repo.get!(Basic, id)
      {:ok, _} = Spector.update(record, %{name: "Robert"})

      # Delete the record from the database
      Repo.delete!(%Basic{id: id})
      assert Repo.get(Basic, id) == nil

      # Materialize should recreate with all updates applied
      assert {:ok, %{id: ^id, name: "Robert", value: 100}} = Spector.materialize(Event, id)
    end

    test "returns error when insert fails (record already exists)" do
      {:ok, %{id: id}} = Spector.insert(Basic, %{name: "Bob", value: 99})

      # Try to materialize when record already exists
      assert {:error, changeset} = Spector.materialize(Event, id)
      assert %Ecto.Changeset{} = changeset
    end

    test "returns {:error, :deleted} when event history ends with delete" do
      {:ok, %{id: id}} = Spector.insert(Basic, %{name: "Bob", value: 99})
      record = Repo.get!(Basic, id)
      {:ok, _} = Spector.delete(record)

      # Try to materialize a deleted record
      assert {:error, :deleted} = Spector.materialize(Event, id)
    end

    test "returns {:error, :invalid} when no events exist for parent_id" do
      nonexistent_id = UUIDv7.generate()

      assert {:error, :invalid} = Spector.materialize(Event, nonexistent_id)
    end
  end
end
