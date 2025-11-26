defmodule Spector.Migration do
  use Ecto.Migration

  def up do
    create table(:spector_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :parent_id, :binary_id
      add :payload, :map
      add :schema, :string, null: false
      add :action, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:spector_events, [:schema])
    create index(:spector_events, [:parent_id])
  end

  def down do
    drop table(:spector_events)
  end
end
