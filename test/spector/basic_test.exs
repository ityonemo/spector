defmodule SpectorTest.BasicTest do
  use ExUnit.Case

  alias SpectorTest.Basic
  alias SpectorTest.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  alias SpectorTest.Event

  describe "Spector.insert/2" do
    test "inserts both the event and the object" do
      assert {:ok, %{id: id, name: "Bob", value: 99}} =
               Spector.insert(Basic, %{name: "Bob", value: 99})

      # Event was inserted with matching id
      assert %{
               id: ^id,
               parent_id: ^id,
               schema: Basic,
               action: :insert,
               payload: %{"name" => "Bob", "value" => 99}
             } = Repo.get!(Event, id)
    end

    test "returns error when changeset is invalid" do
      assert {:error, changeset} = Spector.insert(Basic, %{value: 99})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "Spector.update/2" do
    test "updates the object and creates an event" do
      {:ok, %{id: id}} = Spector.insert(Basic, %{name: "Bob", value: 99})
      object = Repo.get!(Basic, id)

      assert {:ok, %{id: ^id, name: "Bob", value: 100}} = Spector.update(object, %{value: 100})

      # New event was created with parent_id pointing to insert event
      events = Repo.all(Event)
      assert length(events) == 2

      assert %{
               parent_id: ^id,
               schema: Basic,
               action: :update,
               payload: %{"value" => 100}
             } = Enum.find(events, &(&1.action == :update))
    end

    test "returns error when changeset is invalid" do
      {:ok, %{id: id}} = Spector.insert(Basic, %{name: "Bob", value: 99})
      object = Repo.get!(Basic, id)

      assert {:error, changeset} = Spector.update(object, %{name: nil})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "Spector.delete/1" do
    test "deletes the object and creates an event" do
      {:ok, %{id: id}} = Spector.insert(Basic, %{name: "Bob", value: 99})
      object = Repo.get!(Basic, id)

      assert {:ok, %{id: ^id, name: "Bob", value: 99}} = Spector.delete(object)

      # Object was deleted
      assert Repo.get(Basic, id) == nil

      # Delete event was created
      events = Repo.all(Event)
      assert length(events) == 2

      assert %{
               parent_id: ^id,
               schema: Basic,
               action: :delete,
               payload: %{}
             } = Enum.find(events, &(&1.action == :delete))
    end
  end

  describe "Event.backtrace/1" do
    test "returns all events up to and including the given entry" do
      {:ok, %{id: id}} = Spector.insert(Basic, %{name: "Bob", value: 99})
      object = Repo.get!(Basic, id)
      {:ok, _} = Spector.update(object, %{value: 100})
      {:ok, _} = Spector.update(object, %{value: 200})

      events = Repo.all(Event)
      assert length(events) == 3

      [insert_event, update1, update2] = Enum.sort_by(events, & &1.id)

      # Backtrace from first event returns only itself
      assert [^insert_event] = Event.backtrace(insert_event)

      # Backtrace from second event returns first two
      assert [^insert_event, ^update1] = Event.backtrace(update1)

      # Backtrace from third event returns all three
      assert [^insert_event, ^update1, ^update2] = Event.backtrace(update2)
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
