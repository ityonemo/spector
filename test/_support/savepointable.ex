defmodule SpectorTest.Savepointable do
  @behaviour Spector.Evented
  use Spector.Evented, events: SpectorTest.Event
  use Ecto.Schema
  alias Ecto.Changeset

  schema "basic" do
    field(:name, :string)
    field(:value, :integer)
    timestamps()
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:name, :value])
    |> Changeset.validate_required([:name])
  end

  @impl true
  def savepoint(record) do
    %{
      name: record.name,
      value: record.value
    }
  end
end
