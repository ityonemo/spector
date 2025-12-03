defmodule SpectorTest.BringupSchema do
  @moduledoc false
  use Spector.Evented, events: SpectorTest.Event, actions: [:import]
  use Ecto.Schema
  alias Ecto.Changeset

  schema "basic" do
    field(:name, :string)
    field(:value, :integer)
    timestamps()
  end

  # For import action, prefix name and accept timestamps to preserve original values
  def changeset(changeset, attrs) when changeset.action == :import do
    changeset
    |> Changeset.cast(attrs, [:name, :value, :inserted_at, :updated_at])
    |> Changeset.update_change(:name, &("imported_" <> &1))
    |> Changeset.validate_required([:name])
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:name, :value, :inserted_at, :updated_at])
    |> Changeset.validate_required([:name])
  end
end
