defmodule SpectorTest.PrepareMaterializationTest do
  @moduledoc false

  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias SpectorTest.Basic
  alias SpectorTest.Event
  alias SpectorTest.MiniTelemetry
  alias SpectorTest.PrepareMaterializationSchema
  alias SpectorTest.Repo

  @event_name [:spector_test, :prepare_materialization]

  setup do
    :ok = Sandbox.checkout(Repo)
    handler_id = "test-#{inspect(self())}"
    MiniTelemetry.attach(handler_id, @event_name)
    on_exit(fn -> MiniTelemetry.detach(handler_id) end)
    :ok
  end

  describe "prepare_materialization/1 callback" do
    test "insert/2 calls the callback before inserting" do
      {:ok, record} = Spector.insert(PrepareMaterializationSchema, %{name: "Bob", value: 99})

      # The callback should have been called and modified the name
      assert record.name == "PREPARED:Bob"
      assert_received {:telemetry_event, @event_name, %{}, %{changeset: _}}
    end

    test "execute/3 calls the callback before updating" do
      {:ok, record} = Spector.insert(PrepareMaterializationSchema, %{name: "Bob", value: 99})
      assert_received {:telemetry_event, @event_name, %{}, %{changeset: _}}

      {:ok, updated} = Spector.execute(record, :update, %{value: 100})

      # The callback should have been called
      # Note: Events store original attrs ("Bob"), so replay produces "Bob",
      # then callback adds "PREPARED:" prefix
      assert updated.name == "PREPARED:Bob"
      assert updated.value == 100
      assert_received {:telemetry_event, @event_name, %{}, %{changeset: _}}
    end

    test "materialize/2 calls the callback before inserting" do
      # Insert a record (which will have PREPARED: prefix from callback)
      {:ok, %{id: id}} = Spector.insert(PrepareMaterializationSchema, %{name: "Bob", value: 99})
      assert_received {:telemetry_event, @event_name, %{}, %{changeset: _}}

      # Delete the record from the database (but events remain)
      Repo.delete!(%PrepareMaterializationSchema{id: id})
      assert Repo.get(PrepareMaterializationSchema, id) == nil

      # Materialize should recreate the record and call prepare_materialization
      {:ok, materialized} = Spector.materialize(Event, id)

      # The callback should have been called and prepended PREPARED:
      # Note: The original event stored "Bob", so replay gives "Bob", then callback adds "PREPARED:"
      assert materialized.name == "PREPARED:Bob"
      assert_received {:telemetry_event, @event_name, %{}, %{changeset: _}}
    end

    test "schemas without prepare_materialization/1 callback work normally" do
      # Basic schema doesn't implement prepare_materialization/1
      {:ok, record} = Spector.insert(Basic, %{name: "Alice", value: 42})

      # The name should not be modified
      assert record.name == "Alice"
      refute_received {:telemetry_event, @event_name, _, _}
    end
  end
end
