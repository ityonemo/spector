defmodule Spector.Migration do
  @moduledoc """
  Migration helpers for creating Spector event tables.

  ## Basic Usage

      defmodule MyApp.Repo.Migrations.CreateEvents do
        use Ecto.Migration

        def up, do: Spector.Migration.up(table: "events")
        def down, do: Spector.Migration.down(table: "events")
      end

  ## Options

  * `:table` (required) - The database table name for the events
  * `:hashed` - Add a `hash` column for hash chain integrity (default: `false`)

  ## With Hash Chain Integrity

  If using hashed events, include the `:hashed` option:

      def up, do: Spector.Migration.up(table: "events", hashed: true)
      def down, do: Spector.Migration.down(table: "events")

  ## Generated Schema

  The migration creates a table with:

  * `id` - UUIDv7 primary key
  * `parent_id` - Foreign key reference to the first event (self-referential)
  * `payload` - Map/JSONB column storing the event data
  * `schema` - Integer identifying which schema this event belongs to
  * `action` - Integer identifying the action (insert, update, delete, or custom)
  * `hash` - Binary column for SHA-256 hash (only if `hashed: true`)
  * `inserted_at`, `updated_at` - Timestamps with microsecond precision

  Indexes are created on `schema` and `parent_id` for efficient queries.
  """

  use Ecto.Migration

  def up(opts) do
    table = Keyword.fetch!(opts, :table)

    create table(table, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :parent_id, references(table, type: :binary_id), null: false
      add :payload, :map
      add :schema, :integer, null: false
      add :action, :integer, null: false

      if Keyword.get(opts, :hashed, false) do
        add :hash, :binary
      end

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
