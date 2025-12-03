defmodule SpectorTest.TreeTest do
  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias SpectorTest.Repo
  alias SpectorTest.TreeChat
  alias SpectorTest.TreeEvent

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "tree chat with append" do
    test "insert creates an event with tree entry pointing to itself" do
      {:ok, %TreeChat{id: id, messages: [%{content: "Hello"}]}} =
        Spector.insert(TreeChat, %{content: "Hello", role: :user})

      assert [%{action: :insert} = event] =
               Spector.all_events(TreeChat, id)

      assert %{ancestors: []} = Repo.preload(event, :ancestors)
    end

    test "append creates tree entry linking new event to parent event" do
      {:ok, %TreeChat{id: id} = chat} =
        Spector.insert(TreeChat, %{content: "Hello", role: :user})

      [insert_event] = Spector.all_events(TreeChat, id)

      {:ok, %TreeChat{messages: [_, %{content: "Hi!"}]}} =
        Spector.execute(chat, :append, %{content: "Hi!", role: :assistant, to: insert_event.id})

      [_, appended] = Spector.all_events(TreeChat, id)
      assert %{ancestors: [^insert_event]} = Repo.preload(appended, :ancestors)
    end

    test "branching from an earlier event creates separate ancestor chain" do
      # Create a linear conversation: A -> B -> C
      {:ok, %TreeChat{id: id} = chat} =
        Spector.insert(TreeChat, %{content: "A", role: :user})

      [event_a] = Spector.all_events(TreeChat, id)

      {:ok, chat} =
        Spector.execute(chat, :append, %{content: "B", role: :assistant, to: event_a.id})

      [_, event_b] = Spector.all_events(TreeChat, id)

      {:ok, chat} =
        Spector.execute(chat, :append, %{content: "C", role: :user, to: event_b.id})

      [_, _, event_c] = Spector.all_events(TreeChat, id)

      # Now branch from B (not C) to create D
      {:ok, _chat} =
        Spector.execute(chat, :append, %{content: "D (branch)", role: :user, to: event_b.id})

      [_, _, _, event_d] = Spector.all_events(TreeChat, id)

      # D's ancestors should be [A, B], not [A, B, C]
      %{ancestors: d_ancestors} = Repo.preload(event_d, :ancestors)
      ancestor_ids = Enum.map(d_ancestors, & &1.id) |> Enum.sort()

      assert ancestor_ids == Enum.sort([event_a.id, event_b.id])
      refute event_c.id in ancestor_ids
    end

    test "multiple branches from the same event have the same ancestors" do
      # Create: A -> B, then branch twice from B to create C and D
      {:ok, %TreeChat{id: id} = chat} =
        Spector.insert(TreeChat, %{content: "A", role: :user})

      [event_a] = Spector.all_events(TreeChat, id)

      {:ok, chat} =
        Spector.execute(chat, :append, %{content: "B", role: :assistant, to: event_a.id})

      [_, event_b] = Spector.all_events(TreeChat, id)

      # First branch from B
      {:ok, chat} =
        Spector.execute(chat, :append, %{content: "C (branch 1)", role: :user, to: event_b.id})

      # Second branch from B
      {:ok, _chat} =
        Spector.execute(chat, :append, %{content: "D (branch 2)", role: :user, to: event_b.id})

      [_, _, event_c, event_d] = Spector.all_events(TreeChat, id)

      # Both C and D should have the same ancestors: [A, B]
      %{ancestors: c_ancestors} = Repo.preload(event_c, :ancestors)
      %{ancestors: d_ancestors} = Repo.preload(event_d, :ancestors)

      c_ancestor_ids = Enum.map(c_ancestors, & &1.id) |> Enum.sort()
      d_ancestor_ids = Enum.map(d_ancestors, & &1.id) |> Enum.sort()

      expected_ancestors = Enum.sort([event_a.id, event_b.id])

      assert c_ancestor_ids == expected_ancestors
      assert d_ancestor_ids == expected_ancestors
    end
  end
end
