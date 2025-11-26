defmodule SpectorTest.Orphan do
  use Spector.Evented, events: SpectorTest.SomeOtherEvents
  use Ecto.Schema

  schema "orphans" do
    field :name, :string
  end

  def changeset(struct, attrs), do: Ecto.Changeset.cast(struct, attrs, [:name])
end

defmodule SpectorTest.WrongEvents do
  use Spector.Events, table: "wrong_events", schemas: [SpectorTest.Orphan], repo: SpectorTest.Repo
end
