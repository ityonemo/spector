defmodule SpectorTest.LinksTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias SpectorTest.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "parent_id constraint" do
    test "rejects links between events with different parent_ids" do
      # Create two separate chats (different parent_ids)
      {:ok, chat1} = Spector.insert(SpectorTest.TreeChat, %{content: "Chat 1", role: :user})
      {:ok, chat2} = Spector.insert(SpectorTest.TreeChat, %{content: "Chat 2", role: :user})

      # Convert string UUIDs to binary for Postgrex
      {:ok, id1} = Ecto.UUID.dump(chat1.id)
      {:ok, id2} = Ecto.UUID.dump(chat2.id)

      # Try to create a link between events from different chats
      assert_raise Postgrex.Error, ~r/Link events must have the same parent_id/, fn ->
        SpectorTest.Repo.query!(
          "INSERT INTO tree_ancestors (event_id, ancestor_id) VALUES ($1, $2)",
          [id1, id2]
        )
      end
    end

    test "allows links between events with the same parent_id" do
      # Create a chat and append to it (same parent_id)
      {:ok, chat} = Spector.insert(SpectorTest.TreeChat, %{content: "Root", role: :user})

      {:ok, _child} =
        Spector.execute(chat, :append, %{content: "Child", role: :assistant, to: chat.id})

      # The link was created successfully via put_assoc in prepare_event
      # Verify by querying the ancestors table
      result =
        SpectorTest.Repo.query!("SELECT COUNT(*) FROM tree_ancestors WHERE event_id IS NOT NULL")

      assert [[count]] = result.rows
      assert count >= 1
    end
  end
end
