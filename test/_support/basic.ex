defmodule SpectorTest.Basic do
  @moduledoc false
  use Spector.Evented, events: SpectorTest.Event
  use Ecto.Schema
  alias Ecto.Changeset

  schema "basic" do
    field(:name, :string)
    field(:value, :integer)
    timestamps()
    event_log(:log)
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:name, :value, :inserted_at, :updated_at])
    |> Changeset.validate_required([:name])
  end
end
