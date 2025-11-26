defmodule SpectorTest.HashedTest do
  use ExUnit.Case

  alias SpectorTest.Hashed
  alias SpectorTest.HashedEvent
  alias SpectorTest.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "hashed events" do
    test "events have hash field populated" do
      {:ok, %{id: id}} = Spector.insert(Hashed, %{name: "Bob", value: 99})

      event = Repo.get!(HashedEvent, id)
      assert event.hash != nil
      assert is_binary(event.hash)
      assert byte_size(event.hash) == 32  # SHA-256
    end

    test "hash chain links events together" do
      {:ok, %{id: id}} = Spector.insert(Hashed, %{name: "Bob", value: 99})
      object = Repo.get!(Hashed, id)
      {:ok, _} = Spector.update(object, %{value: 100})

      events = Repo.all(HashedEvent)
      assert length(events) == 2

      [first, second] = Enum.sort_by(events, & &1.id)

      # Both have hashes
      assert first.hash != nil
      assert second.hash != nil

      # Hashes are different
      assert first.hash != second.hash
    end
  end
end
