defmodule SpectorTest.VersionedTest do
  use ExUnit.Case

  alias SpectorTest.Versioned
  alias SpectorTest.Repo
  alias SpectorTest.Event

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "versioned events" do
    test "can roll forward from version 0 events" do
      # Manually insert a version 0 event with old schema (title instead of name)
      id = UUIDv7.generate()

      Repo.insert!(%Event{
        id: id,
        parent_id: id,
        schema: Versioned,
        action: :insert,
        payload: %{title: "Old Title", value: 42, __version__: 0}
      })

      # Also insert the object directly (as if it was created with v0)
      Repo.insert!(%Versioned{id: id, name: nil, value: 42})

      object = Repo.get!(Versioned, id)

      # Update should roll forward from v0 event and apply new changes
      assert {:ok, %{id: ^id, value: 100}} = Spector.update(object, %{value: 100})

      # Check the update event has version 1
      events = Repo.all(Event)
      assert length(events) == 2

      assert %{
               parent_id: ^id,
               action: :update,
               payload: %{"value" => 100, "__version__" => 1}
             } = Enum.find(events, &(&1.action == :update))
    end
  end
end
