defmodule Spector.Migration do
  @moduledoc """
  Migration helpers for creating Spector event tables.

  Usage in your migration:

      defmodule MyApp.Repo.Migrations.CreateEvents do
        use Ecto.Migration

        def up, do: Spector.Migration.up(table: "events")
        def down, do: Spector.Migration.down(table: "events")
      end
  """

  use Ecto.Migration

  def up(opts) do
    table = Keyword.fetch!(opts, :table)

    create table(table, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :parent_id, :binary_id
      add :payload, :map
      add :schema, :integer, null: false
      add :action, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(table, [:schema])
    create index(table, [:parent_id])
  end

  def down(opts) do
    table = Keyword.fetch!(opts, :table)
    drop table(table)
  end
end
