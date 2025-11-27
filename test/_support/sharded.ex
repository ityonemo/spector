defmodule SpectorTest.Sharded do
  use Spector.Evented, events: SpectorTest.ShardedEvent
  use Ecto.Schema
  alias Ecto.Changeset

  schema "sharded" do
    field(:name, :string)
    field(:value, :integer)
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:name, :value])
    |> Changeset.validate_required([:name])
  end
end
