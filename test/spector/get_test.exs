defmodule SpectorTest.GetTest do
  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias SpectorTest.Basic
  alias SpectorTest.Chat
  alias SpectorTest.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "Spector.get/2" do
    test "returns nil for non-existent id" do
      non_existent_id = Ecto.UUID.generate()

      assert nil == Spector.get(Basic, non_existent_id)
    end

    test "returns nil for mismatched schema/id" do
      {:ok, %Chat{id: chat_id}} = Spector.insert(Chat, %{content: "Hello", role: :user})

      # Chat id should not work with Basic schema
      assert nil == Spector.get(Basic, chat_id)
    end
  end
end
