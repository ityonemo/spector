defmodule SpectorTest.Custom do
  @moduledoc false
  use Spector.Evented, events: SpectorTest.Event, actions: [:archive]
  use Ecto.Schema
  alias Ecto.Changeset

  schema "custom" do
    field(:name, :string)
    field(:value, :integer)
    field(:archived_at, :utc_datetime_usec)
  end

  def changeset(changeset, attrs) when changeset.action == :archive do
    changeset
    |> Changeset.change(archived_at: attrs[:archived_at])
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:name, :value])
    |> Changeset.validate_required([:name])
  end
end
