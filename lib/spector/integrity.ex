defmodule Spector.Integrity do
  @moduledoc """
  Integrity verification for Spector event logs.

  This module provides functions to verify the integrity of event logs,
  including savepoint validation and hash chain verification.
  """

  alias Ecto.Changeset
  alias Spector.Integrity.HashMismatch
  alias Spector.Integrity.SavepointFailure
  alias Spector.Query

  @doc """
  Verify all savepoints for a record match the expected state at that point.

  Replays events from the beginning up to each savepoint and verifies that
  all replay paths (skipping different combinations of savepoints) converge
  to the same state. This catches bugs in `savepoint/2` implementations that
  omit fields.

  Returns `:ok` if all savepoints are valid, or `{:error, exception}` where
  exception is a `Spector.Integrity.SavepointFailure`.

  Raises if the schema doesn't implement the `savepoint/2` callback.

  ## Examples

      # Verify all savepoints for a record
      :ok = Spector.Integrity.verify_savepoints(MyApp.User, user_id)

      # Handle verification failures
      case Spector.Integrity.verify_savepoints(MyApp.User, user_id) do
        :ok -> :verified
        {:error, %Spector.Integrity.SavepointFailure{} = failure} ->
          Logger.error(Exception.message(failure))
      end
  """
  @spec verify_savepoints(module(), String.t()) ::
          :ok | {:error, Spector.Integrity.SavepointFailure.t()}
  def verify_savepoints(schema, parent_id) do
    if !function_exported?(schema, :savepoint, 2),
      do: raise("Schema #{inspect(schema)} must implement savepoint/2 callback")

    events = Spector.all_events(schema, parent_id)

    [pk_field] = schema.__schema__(:primary_key)

    initial_changeset =
      schema
      |> struct!([{pk_field, parent_id}])
      |> Changeset.change()

    # Start with one universe containing just the initial state.  If it makes it through the
    # whole thing, we are ok.
    _universes = Enum.reduce(events, [initial_changeset], &apply_to_universes(&2, &1, schema, []))
    :ok
  catch
    {:error, failure} -> {:error, failure}
  end

  # savepoint case:  We're going to accumulate {changeset, applied state} tuples
  # and verify convergence while reversing the list.
  defp apply_to_universes([last], %{action: :savepoint} = event, schema, so_far) do
    # if we're at a savepoint, we should preserve the last universe (this is the one that has skipped no savepoints)
    # and seed the new universes list, after verifying all universes have converged.
    last_changeset = Spector._roll_one(event, last, schema)
    all_applied_to_check = Changeset.apply_action!(last_changeset, :savepoint)
    skipped_to_check = Changeset.apply_action!(last, :savepoint)

    verify_integrity([{last, skipped_to_check} | so_far], all_applied_to_check, [last_changeset])
  end

  defp apply_to_universes([head | rest], %{action: :savepoint} = event, schema, so_far) do
    head_changeset = Spector._roll_one(event, head, schema)
    head_to_check = Changeset.apply_action!(head_changeset, :savepoint)
    apply_to_universes(rest, event, schema, [{head_changeset, head_to_check} | so_far])
  end

  # non savepoint case: just roll forward all universes and reverse when done.

  defp apply_to_universes([head | rest], event, schema, so_far) do
    apply_to_universes(rest, event, schema, [Spector._roll_one(event, head, schema) | so_far])
  end

  defp apply_to_universes([], _event, _, so_far), do: Enum.reverse(so_far)

  defp verify_integrity([], _expected, so_far), do: so_far

  defp verify_integrity([{head_changeset, head_check} | rest], expected, so_far) do
    if expected == head_check do
      verify_integrity(rest, expected, [head_changeset | so_far])
    else
      throw(
        {:error,
         SavepointFailure.exception(
           expected: expected,
           actual: head_check
         )}
      )
    end
  end

  @doc """
  Verify the hash chain integrity of an entire events table.

  Iterates through all events in the table ordered by id and verifies
  that each event's hash correctly chains from the previous event.

  Returns `:ok` if the hash chain is valid, or `{:error, exception}` where
  exception is a `Spector.Integrity.HashMismatch`.

  Raises if the events module doesn't have hash chain integrity enabled.

  ## Examples

      # Verify the hash chain for an events table
      :ok = Spector.Integrity.verify_hash_chain(MyApp.Events)

      # Handle verification failures
      case Spector.Integrity.verify_hash_chain(MyApp.Events) do
        :ok -> :verified
        {:error, %Spector.Integrity.HashMismatch{} = failure} ->
          Logger.error(Exception.message(failure))
      end
  """
  @spec verify_hash_chain(module()) ::
          :ok | {:error, Spector.Integrity.HashMismatch.t()}
  def verify_hash_chain(events_module) do
    if !events_module.__spector__(:hashed),
      do: raise("Events module #{inspect(events_module)} is not hashed")

    repo = events_module.__spector__(:repo)

    events = repo.all(Query.all_ordered(events_module))

    verify_chain(events, nil)
  end

  defp verify_chain([], _prev_hash), do: :ok

  defp verify_chain([event | rest], prev_hash) do
    expected_hash = compute_hash(prev_hash, event)

    if expected_hash == event.hash do
      verify_chain(rest, event.hash)
    else
      {:error,
       HashMismatch.exception(
         event_id: event.id,
         expected_hash: expected_hash,
         actual_hash: event.hash
       )}
    end
  end

  defp compute_hash(prev_hash, event) do
    prev_hash_hex = if prev_hash, do: "#{Base.encode16(prev_hash, case: :lower)}:", else: ""
    # Normalize payload to atom keys to match the original encoding order
    normalized_payload = normalize_payload_keys(event.payload)
    payload_json = Spector._json_encode!(normalized_payload)
    data = "#{prev_hash_hex}#{event.schema}.#{event.action}#{payload_json}"
    :crypto.hash(:sha256, data)
  end

  # Convert string keys to atoms to match the original encoding order
  defp normalize_payload_keys(payload) do
    Map.new(payload, fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k
      {key, v}
    end)
  end
end
