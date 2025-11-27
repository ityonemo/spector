defmodule SpectorTest.ShardedTest do
  use ExUnit.Case

  alias SpectorTest.Sharded
  alias SpectorTest.ShardedEvent
  alias SpectorTest.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "sharded events" do
    test "events are routed to correct shard based on parent_id parity" do
      {:ok, %{id: id}} = Spector.insert(Sharded, %{name: "Alice", value: 1})

      # Determine which shard it should be in and verify
      shard_table = ShardedEvent.shard_for(id)
      other_table = if shard_table == "sharded_events_0", do: "sharded_events_1", else: "sharded_events_0"

      assert [%{parent_id: ^id}] = query_shard(shard_table)
      assert [] = query_shard(other_table)
    end

    test "list_by_parent_id queries the correct shard" do
      {:ok, %{id: id}} = Spector.insert(Sharded, %{name: "Alice", value: 1})

      shard_table = ShardedEvent.shard_for(id)
      other_table = if shard_table == "sharded_events_0", do: "sharded_events_1", else: "sharded_events_0"

      # list_by_parent_id should find the event in the correct shard
      assert [%{parent_id: ^id}] = ShardedEvent.list_by_parent_id(id, Sharded)
      assert [%{parent_id: ^id}] = query_shard(shard_table)
      assert [] = query_shard(other_table)
    end

    test "updates query and insert to the correct shard" do
      {:ok, %{id: id}} = Spector.insert(Sharded, %{name: "Alice", value: 1})
      object = Repo.get!(Sharded, id)

      {:ok, _} = Spector.update(object, %{value: 2})

      shard_table = ShardedEvent.shard_for(id)
      other_table = if shard_table == "sharded_events_0", do: "sharded_events_1", else: "sharded_events_0"

      # Both events should be in the same shard
      assert [%{action: :insert}, %{action: :update}] = query_shard(shard_table)
      assert [] = query_shard(other_table)
    end

    test "backtrace works with sharding" do
      {:ok, %{id: id}} = Spector.insert(Sharded, %{name: "Alice", value: 1})
      object = Repo.get!(Sharded, id)

      {:ok, _} = Spector.update(object, %{value: 2})
      {:ok, _} = Spector.update(object, %{value: 3})

      shard_table = ShardedEvent.shard_for(id)
      other_table = if shard_table == "sharded_events_0", do: "sharded_events_1", else: "sharded_events_0"

      [insert_event, update1, update2] = query_shard(shard_table)
      assert [] = query_shard(other_table)

      # Backtrace should work within the shard
      assert [^insert_event] = ShardedEvent.backtrace(insert_event)
      assert [^insert_event, ^update1] = ShardedEvent.backtrace(update1)
      assert [^insert_event, ^update1, ^update2] = ShardedEvent.backtrace(update2)
    end

    test "delete inserts to the correct shard" do
      {:ok, %{id: id}} = Spector.insert(Sharded, %{name: "Alice", value: 1})
      object = Repo.get!(Sharded, id)

      {:ok, _} = Spector.delete(object)

      shard_table = ShardedEvent.shard_for(id)
      other_table = if shard_table == "sharded_events_0", do: "sharded_events_1", else: "sharded_events_0"

      assert [%{action: :insert}, %{action: :delete}] = query_shard(shard_table)
      assert [] = query_shard(other_table)
    end
  end

  defp query_shard(table) do
    import Ecto.Query
    Repo.all(from(e in {table, ShardedEvent}, select: e))
  end
end
