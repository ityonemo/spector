defmodule SpectorTest.Savepointable do
  @moduledoc false
  @behaviour Spector.Evented
  use Spector.Evented, events: SpectorTest.Event
  use Ecto.Schema
  alias Ecto.Changeset

  schema "basic" do
    field(:name, :string)
    field(:value, :integer)
    # Field intentionally omitted from savepoint/1 for testing integrity verification
    field(:bugged, :string)
    timestamps()
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:name, :value, :bugged, :inserted_at, :updated_at])
    |> Changeset.validate_required([:name])
  end

  @impl true
  def savepoint(record, _version) do
    # BUG: intentionally omits :bugged field to test integrity verification
    %{
      name: record.name,
      value: record.value,
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }
  end
end
