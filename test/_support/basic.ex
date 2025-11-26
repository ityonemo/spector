defmodule SpectorTest.Basic do
  use Spector.Evented, events: SpectorTest.Event
  use Ecto.Schema
  alias Ecto.Changeset

  schema "basic" do
    field :name, :string
    field :value, :integer
  end

  def changeset(struct, attrs) do
    struct
    |> Changeset.cast(attrs, [:name, :value])
    |> Changeset.validate_required([:name])
  end
end
