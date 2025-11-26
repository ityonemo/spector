defmodule Spector do
  @moduledoc """
  CQRS-style event sourcing for Ecto schemas.
  """

  alias Ecto.Changeset

  def insert(schema, attrs) do
    events = schema.__spector__(:events)
    repo = events.__spector__(:repo)
    version = schema.__spector__(:version)
    attrs = Map.put(attrs, :version, version)

    changeset =
      schema
      |> struct!()
      |> Changeset.change()
      |> Map.replace!(:action, :insert)
      |> schema.changeset(attrs)

    if changeset.valid? do
      repo.transact(fn ->
        id = UUIDv7.generate()

        event_attrs = %{id: id, parent_id: id, schema: schema, action: :insert, payload: attrs}
        event_attrs = maybe_add_hash(events, event_attrs)
        object_changeset = Changeset.put_change(changeset, :id, id)

        with {:ok, _event} <- repo.insert(events.changeset(event_attrs)),
             {:ok, object} <- repo.insert(object_changeset) do
          {:ok, object}
        end
      end)
    else
      {:error, changeset}
    end
  end

  def update(object, attrs) do
    execute(object, :update, attrs)
  end

  def delete(object) do
    schema = object.__struct__
    events = schema.__spector__(:events)
    repo = events.__spector__(:repo)

    repo.transact(fn ->
      id = UUIDv7.generate()

      event_attrs = %{id: id, parent_id: object.id, schema: schema, action: :delete, payload: %{}}
      event_attrs = maybe_add_hash(events, event_attrs)

      with {:ok, _event} <- repo.insert(events.changeset(event_attrs)),
           {:ok, deleted} <- repo.delete(object) do
        {:ok, deleted}
      end
    end)
  end

  def execute(object, action, attrs) do
    schema = object.__struct__
    events = schema.__spector__(:events)
    repo = events.__spector__(:repo)
    parent_id = object.id
    version = schema.__spector__(:version)
    attrs = Map.put(attrs, :version, version)

    # Roll forward from events to get current state
    changeset = schema
      |> roll_forward(events, parent_id)
      |> Map.replace!(:action, action)
      |> schema.changeset(attrs)

    if changeset.valid? do
      repo.transact(fn ->
        id = UUIDv7.generate()

        event_attrs = %{id: id, parent_id: parent_id, schema: schema, action: action, payload: attrs}
        event_attrs = maybe_add_hash(events, event_attrs)
        # Reset action to :update for repo.update/2
        update_changeset = Map.replace!(changeset, :action, :update)

        with {:ok, _event} <- repo.insert(events.changeset(event_attrs)),
             {:ok, updated} <- repo.update(update_changeset) do
          {:ok, updated}
        end
      end)
    else
      {:error, changeset}
    end
  end

  defp maybe_add_hash(events, event_attrs) do
    if events.__spector__(:hashed) do
      prev_hash = get_last_hash(events)
      hash = compute_hash(prev_hash, event_attrs)
      Map.put(event_attrs, :hash, hash)
    else
      event_attrs
    end
  end

  defp get_last_hash(events) do
    import Ecto.Query
    repo = events.__spector__(:repo)

    case repo.one(from e in events, order_by: [desc: e.id], limit: 1, select: e.hash) do
      nil -> nil
      hash -> hash
    end
  end

  @json_library if Code.ensure_loaded?(Jason), do: Jason, else: JSON

  defp compute_hash(prev_hash, event_attrs) do
    prev_hash_hex = if prev_hash, do: "#{Base.encode16(prev_hash, case: :lower)}:", else: ""
    payload_json = @json_library.encode!(event_attrs.payload)
    data = "#{prev_hash_hex}#{event_attrs.schema}.#{event_attrs.action}#{payload_json}"
    :crypto.hash(:sha256, data)
  end

  defp roll_forward(schema, events, parent_id) do
    entries = events.list_by_parent_id(parent_id)

    schema
    |> struct!(id: parent_id)
    |> Changeset.change()
    |> then(&Enum.reduce(entries, &1, fn event, changeset ->
      changeset
      |> Map.replace!(:action, event.action)
      |> schema.changeset(event.payload)
    end))
  end
end
