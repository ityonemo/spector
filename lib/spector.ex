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
    schema = object.__struct__
    events = schema.__spector__(:events)
    repo = events.__spector__(:repo)
    parent_id = object.id
    version = schema.__spector__(:version)
    attrs = Map.put(attrs, :version, version)

    # Roll forward from events to get current state
    changeset = schema
      |> roll_forward(events, parent_id)
      |> Map.replace!(:action, :update)
      |> schema.changeset(attrs)

    if changeset.valid? do
      repo.transact(fn ->
        id = UUIDv7.generate()

        event_attrs = %{id: id, parent_id: parent_id, schema: schema, action: :update, payload: attrs}

        with {:ok, _event} <- repo.insert(events.changeset(event_attrs)),
             {:ok, updated} <- repo.update(changeset) do
          {:ok, updated}
        end
      end)
    else
      {:error, changeset}
    end
  end

  def delete(object) do
    schema = object.__struct__
    events = schema.__spector__(:events)
    repo = events.__spector__(:repo)

    repo.transact(fn ->
      id = UUIDv7.generate()

      event_attrs = %{id: id, parent_id: object.id, schema: schema, action: :delete, payload: %{}}

      with {:ok, _event} <- repo.insert(events.changeset(event_attrs)),
           {:ok, deleted} <- repo.delete(object) do
        {:ok, deleted}
      end
    end)
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
