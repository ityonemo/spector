defmodule SpectorTest.Versioned do
  # Version 0: field :title, :string
  use Spector.Evented, events: SpectorTest.Event, version: 1
  use Ecto.Schema
  alias Ecto.Changeset

  schema "versioned" do
    field(:name, :string)
    field(:value, :integer)
  end

  def changeset(changeset, attrs) when version_in(attrs, 0..0) do
    # Migrate v0 title -> v1 name
    attrs = Map.put(attrs, "name", attrs["title"])

    changeset
    |> Changeset.cast(attrs, [:name, :value])
    |> Changeset.validate_required([:name])
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:name, :value])
    |> Changeset.validate_required([:name])
  end
end
