defmodule SpectorTest.CustomTest do
  use ExUnit.Case

  alias SpectorTest.Custom
  alias SpectorTest.Repo
  alias SpectorTest.Event

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "custom actions" do
    test "archive action sets archived_at" do
      {:ok, %{id: id}} = Spector.insert(Custom, %{name: "Item", value: 10})
      object = Repo.get!(Custom, id)

      now = DateTime.utc_now()
      assert {:ok, %{id: ^id, archived_at: archived_at}} = Spector.execute(object, :archive, %{archived_at: now})

      assert archived_at == DateTime.truncate(now, :microsecond)

      # Archive event was created
      events = Repo.all(Event)
      assert length(events) == 2

      assert %{
               parent_id: ^id,
               schema: Custom,
               action: :archive,
               payload: %{"archived_at" => _}
             } = Enum.find(events, &(&1.action == :archive))
    end
  end
end
