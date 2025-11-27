defmodule SpectorTest.EmbeddedTest do
  use ExUnit.Case

  alias SpectorTest.Chat
  alias SpectorTest.Event
  alias SpectorTest.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "embedded schema with Spector.Evented" do
    test "insert creates an event and returns the embedded struct with one message" do
      {:ok, %Chat{id: id, messages: [%{content: "Hello", role: :user}]}} =
        Spector.insert(Chat, %{content: "Hello", role: :user})

      # Event should be stored
      assert [%{action: :insert}] = Event.list_by_parent_id(id, Chat)
    end

    test "update appends a message to the list" do
      {:ok, chat} = Spector.insert(Chat, %{content: "Hello", role: :user})

      {:ok, %Chat{messages: [%{content: "Hello"}, %{content: "Hi there!"}]}} =
        Spector.update(chat, %{content: "Hi there!", role: :assistant})
    end

    test "get reconstructs the chat from events" do
      {:ok, %Chat{id: id} = chat} = Spector.insert(Chat, %{content: "Hello", role: :user})
      {:ok, _} = Spector.update(chat, %{content: "Hi!", role: :assistant})
      {:ok, _} = Spector.update(chat, %{content: "How are you?", role: :user})

      # Get from events
      assert %Chat{
               id: ^id,
               messages: [%{content: "Hello"}, %{content: "Hi!"}, %{content: "How are you?"}]
             } = Spector.get(Chat, id)
    end
  end
end
