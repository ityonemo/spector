defmodule SpectorTest.PrepareMaterializationSchema do
  @moduledoc false
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
    |> Changeset.cast(attrs, [:name, :value, :inserted_at, :updated_at])
    |> Changeset.validate_required([:name])
  end

  @impl true
  def prepare_materialization(changeset) do
    :telemetry.execute(
      [:spector_test, :prepare_materialization],
      %{},
      %{changeset: changeset}
    )

    # Modify the changeset to prove we can
    Changeset.put_change(changeset, :name, "PREPARED:" <> Changeset.get_field(changeset, :name))
  end
end
