defmodule SpectorTest.QueryTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spector.Query
  alias SpectorTest.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "all_events/2" do
    test "returns all events for a record" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, record} = Spector.update(record, %{value: 10})
      {:ok, _record} = Spector.update(record, %{value: 20})

      events = SpectorTest.Repo.all(Query.all_events(SpectorTest.Savepointable, record.id))

      assert length(events) == 3
      assert [%{action: :insert}, %{action: :update}, %{action: :update}] = events
    end

    test "returns empty list when no events exist" do
      fake_id = UUIDv7.generate()

      events = SpectorTest.Repo.all(Query.all_events(SpectorTest.Savepointable, fake_id))

      assert events == []
    end

    test "returns events in insertion order" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, record} = Spector.update(record, %{value: 10})
      {:ok, _record} = Spector.update(record, %{value: 20})

      events = SpectorTest.Repo.all(Query.all_events(SpectorTest.Savepointable, record.id))

      # Verify ordering by checking inserted_at is ascending
      inserted_ats = Enum.map(events, & &1.inserted_at)
      assert inserted_ats == Enum.sort(inserted_ats, DateTime)
    end
  end

  describe "recent_events/2" do
    test "returns all events when no savepoint exists" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, record} = Spector.update(record, %{value: 10})
      {:ok, _record} = Spector.update(record, %{value: 20})

      events = SpectorTest.Repo.all(Query.recent_events(SpectorTest.Savepointable, record.id))

      assert length(events) == 3
      assert [%{action: :insert}, %{action: :update}, %{action: :update}] = events
    end

    test "returns events from most recent savepoint" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, record} = Spector.update(record, %{value: 10})
      {:ok, record} = Spector.savepoint(SpectorTest.Savepointable, record.id)
      {:ok, _record} = Spector.update(record, %{value: 20})

      events = SpectorTest.Repo.all(Query.recent_events(SpectorTest.Savepointable, record.id))

      # Should return savepoint + update after it
      assert length(events) == 2
      assert [%{action: :savepoint}, %{action: :update}] = events
    end

    test "returns events from most recent savepoint when multiple savepoints exist" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, record} = Spector.savepoint(SpectorTest.Savepointable, record.id)
      {:ok, record} = Spector.update(record, %{value: 10})
      {:ok, record} = Spector.savepoint(SpectorTest.Savepointable, record.id)
      {:ok, _record} = Spector.update(record, %{value: 20})

      events = SpectorTest.Repo.all(Query.recent_events(SpectorTest.Savepointable, record.id))

      # Should return only the second savepoint + update after it
      assert length(events) == 2
      assert [%{action: :savepoint}, %{action: :update}] = events
    end

    test "returns only savepoint when it is the most recent event" do
      {:ok, record} = Spector.insert(SpectorTest.Savepointable, %{name: "Test", value: 1})
      {:ok, record} = Spector.update(record, %{value: 10})
      {:ok, _record} = Spector.savepoint(SpectorTest.Savepointable, record.id)

      events = SpectorTest.Repo.all(Query.recent_events(SpectorTest.Savepointable, record.id))

      assert length(events) == 1
      assert [%{action: :savepoint}] = events
    end

    test "returns empty list when no events exist" do
      fake_id = UUIDv7.generate()

      events = SpectorTest.Repo.all(Query.recent_events(SpectorTest.Savepointable, fake_id))

      assert events == []
    end
  end
end
