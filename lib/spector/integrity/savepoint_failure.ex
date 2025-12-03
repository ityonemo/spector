defmodule Spector.Integrity.SavepointFailure do
  @moduledoc """
  Exception raised when savepoint verification fails.

  This indicates that replaying events through different paths (skipping vs applying
  savepoints) produces divergent states, which means the `savepoint/2` callback
  is not correctly capturing all relevant state.
  """

  defexception [:savepoint_id, :expected, :actual, :message]

  @impl true
  def exception(opts) do
    expected = Keyword.fetch!(opts, :expected)
    actual = Keyword.fetch!(opts, :actual)
    [pk_field] = expected.__struct__.__schema__(:primary_key)
    savepoint_id = Map.fetch!(expected, pk_field)

    differences = find_differences(expected, actual)

    message = """
    Savepoint verification failed for event #{savepoint_id}.

    States diverged on the following fields:
    #{format_differences(differences)}

    This typically means the savepoint/2 callback is missing one or more fields.
    """

    %__MODULE__{
      savepoint_id: savepoint_id,
      expected: expected,
      actual: actual,
      message: message
    }
  end

  defp find_differences(expected, actual) do
    expected_map = Map.from_struct(expected)
    actual_map = Map.from_struct(actual)

    all_keys = MapSet.union(MapSet.new(Map.keys(expected_map)), MapSet.new(Map.keys(actual_map)))

    all_keys
    |> Enum.filter(fn key ->
      Map.get(expected_map, key) != Map.get(actual_map, key)
    end)
    |> Enum.map(fn key ->
      {key, Map.get(expected_map, key), Map.get(actual_map, key)}
    end)
  end

  defp format_differences(differences) do
    Enum.map_join(differences, "\n", fn {field, expected, actual} ->
      "  #{field}: expected #{inspect(expected)}, got #{inspect(actual)}"
    end)
  end
end
