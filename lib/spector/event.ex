defmodule Spector.Event do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "spector_events" do
    field :parent_id, :binary_id
    field :payload, :map
    field :schema, :string
    field :action, :string

    timestamps(type: :utc_datetime_usec)
  end
end
