defmodule SpectorTest.BasicTest do
  use ExUnit.Case

  alias SpectorTest.Basic
  alias SpectorTest.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "Spector.insert/2" do
    test "inserts both the event and the object" do
      assert {:ok, object} = Spector.insert(Basic, %{name: "Bob", value: 99})

      # Object was inserted
      assert object.id != nil
      assert object.name == "Bob"
      assert object.value == 99
    end

    test "returns error when changeset is invalid" do
      assert {:error, changeset} = Spector.insert(Basic, %{value: 99})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
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
