defmodule SpectorTest.CustomPK do
  @moduledoc false
  use Spector.Evented, events: SpectorTest.Event
  use Ecto.Schema
  alias Ecto.Changeset

  @primary_key {:uuid, UUIDv7, autogenerate: false}
  schema "custom_pk" do
    field(:name, :string)
    field(:value, :integer)
    event_log(:log)
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:name, :value])
    |> Changeset.validate_required([:name])
  end
end
