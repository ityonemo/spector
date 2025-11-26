defmodule SpectorTest.Basic do
  use Spector.Evented, events: SpectorTest.Event
  use Ecto.Schema
  import Ecto.Changeset

  schema "basic" do
    field :name, :string
    field :value, :integer
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:name, :value])
    |> validate_required([:name])
  end
end
