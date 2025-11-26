defmodule Spector do
  @moduledoc """
  CQRS-style event sourcing for Ecto schemas.
  """

  alias Ecto.Changeset

  def insert(schema, attrs) do
    events = schema.__spector__(:events)
    repo = events.__spector__(:repo)

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

    changeset =
      object
      |> Changeset.change()
      |> Map.replace!(:action, :update)
      |> schema.changeset(attrs)

    if changeset.valid? do
      repo.transact(fn ->
        id = UUIDv7.generate()

        event_attrs = %{id: id, parent_id: object.id, schema: schema, action: :update, payload: attrs}

        with {:ok, _event} <- repo.insert(events.changeset(event_attrs)),
             {:ok, updated} <- repo.update(changeset) do
          {:ok, updated}
        end
      end)
    else
      {:error, changeset}
    end
  end
end
