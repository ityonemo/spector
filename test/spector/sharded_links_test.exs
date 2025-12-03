defmodule SpectorTest.ShardedLinksTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias SpectorTest.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "sharding + links migration" do
    test "creates link tables for each shard" do
      # Verify the migration created the expected tables
      # The migration in test uses shards: ["sharded_links_events_0", "sharded_links_events_1"]
      # with links: [{"ancestors", :ancestor_id}]
      # This should create: sharded_links_events_0_ancestors, sharded_links_events_1_ancestors

      # Query to check if tables exist
      result =
        SpectorTest.Repo.query!("""
          SELECT table_name FROM information_schema.tables
          WHERE table_schema = 'public'
          AND table_name LIKE 'sharded_links_events_%'
          ORDER BY table_name
        """)

      table_names = Enum.map(result.rows, &hd/1)

      assert "sharded_links_events_0" in table_names
      assert "sharded_links_events_1" in table_names
      assert "sharded_links_events_0_ancestors" in table_names
      assert "sharded_links_events_1_ancestors" in table_names
    end
  end

  describe "link_table_for/2" do
    test "returns prefixed link table name for sharded events" do
      # UUID ending in even hex goes to shard 0
      even_uuid = "00000000-0000-0000-0000-000000000000"

      assert SpectorTest.ShardedEvent.link_table_for(even_uuid, "ancestors") ==
               "sharded_events_0_ancestors"

      # UUID ending in odd hex goes to shard 1
      odd_uuid = "00000000-0000-0000-0000-000000000001"

      assert SpectorTest.ShardedEvent.link_table_for(odd_uuid, "ancestors") ==
               "sharded_events_1_ancestors"
    end

    test "returns unchanged link table name for non-sharded events" do
      any_uuid = "00000000-0000-0000-0000-000000000000"
      assert SpectorTest.Event.link_table_for(any_uuid, "ancestors") == "ancestors"
    end
  end
end
