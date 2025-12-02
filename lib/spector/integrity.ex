defmodule Spector.Integrity do
  @moduledoc """
  Integrity verification for Spector event logs.

  This module provides functions to verify the integrity of event logs,
  including savepoint validation and (future) hash chain verification.
  """

  alias Ecto.Changeset

  @doc """
  Verify all savepoints for a record match the expected state at that point.

  Replays events from the beginning up to each savepoint and compares
  the computed state against the savepoint's stored payload.

  Returns `:ok` if all savepoints are valid, or `{:error, failures}` where
  failures is a list of `{event_id, {:savepoint_mismatch, mismatches}}` tuples.

  Returns `{:error, :savepoint_not_implemented}` if the schema doesn't
  implement the `savepoint/1` callback.

  ## Examples

      # Verify all savepoints for a record
      :ok = Spector.Integrity.verify_savepoints(MyApp.User, user_id)

      # Handle verification failures
      case Spector.Integrity.verify_savepoints(MyApp.User, user_id) do
        :ok -> :verified
        {:error, :savepoint_not_implemented} -> :no_savepoint_support
        {:error, failures} -> handle_failures(failures)
      end
  """
  @spec verify_savepoints(module(), String.t()) ::
          :ok | {:error, :savepoint_not_implemented} | {:error, [{String.t(), term()}]}
  def verify_savepoints(schema, parent_id) do
    unless function_exported?(schema, :savepoint, 1) do
      {:error, :savepoint_not_implemented}
    else
      events_module = schema.__spector__(:events)
      events = events_module.list_by_parent_id(parent_id, schema)

      failures =
        events
        |> Enum.with_index()
        |> Enum.filter(fn {event, _idx} -> event.action == :savepoint end)
        |> Enum.map(fn {savepoint_event, idx} ->
          # Replay events up to (but not including) this savepoint
          events_before = Enum.take(events, idx)
          replayed_state = replay_events(schema, parent_id, events_before)

          # Get expected state from savepoint callback
          expected_attrs = schema.savepoint(replayed_state)

          # Compare with stored savepoint payload
          case compare_savepoint(savepoint_event.payload, expected_attrs) do
            :ok -> nil
            {:error, mismatches} -> {savepoint_event.id, {:savepoint_mismatch, mismatches}}
          end
        end)
        |> Enum.reject(&is_nil/1)

      case failures do
        [] -> :ok
        _ -> {:error, failures}
      end
    end
  end

  # Replay events to get the state at a specific point
  defp replay_events(schema, parent_id, events) do
    [pk_field] = schema.__schema__(:primary_key)

    initial_changeset =
      schema
      |> struct!([{pk_field, parent_id}])
      |> Changeset.change()

    changeset =
      Enum.reduce(events, initial_changeset, fn event, changeset ->
        changeset
        |> Map.replace!(:action, event.action)
        |> schema.changeset(Map.put(event.payload, "__event_id__", event.id))
      end)

    Changeset.apply_changes(changeset)
  end

  # Compare savepoint payload with expected attrs from savepoint callback
  defp compare_savepoint(payload, expected_attrs) do
    # Filter out metadata fields from payload
    payload_data =
      payload
      |> Map.drop(["__version__", "__event_id__"])
      |> normalize_keys()

    expected_data = normalize_keys(expected_attrs)

    mismatches =
      expected_data
      |> Enum.filter(fn {key, expected_value} ->
        actual_value = Map.get(payload_data, key)
        actual_value != expected_value
      end)
      |> Enum.map(fn {key, expected_value} ->
        actual_value = Map.get(payload_data, key)
        {key, {expected_value, actual_value}}
      end)

    case mismatches do
      [] -> :ok
      _ -> {:error, mismatches}
    end
  end

  # Normalize map keys to atoms for comparison
  defp normalize_keys(map) do
    Map.new(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k
      {key, v}
    end)
  end
end
