defmodule SpectorTest.BasicTest do
  use ExUnit.Case

  alias SpectorTest.Event

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SpectorTest.Repo)
  end

  describe "inserting events" do
    test "can be inserted into the database" do
      event = %Event{
        schema: SpectorTest.Basic,
        action: :insert,
        payload: %{"name" => "Alice", "value" => 42}
      }

      assert {:ok, inserted} = SpectorTest.Repo.insert(event)
      assert inserted.id != nil
      assert inserted.schema == SpectorTest.Basic
      assert inserted.action == :insert
      assert inserted.payload == %{"name" => "Alice", "value" => 42}
    end
  end
end
