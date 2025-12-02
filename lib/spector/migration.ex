defmodule Spector.Migration do
  @moduledoc """
  Migration helpers for creating Spector event tables.

  ## Basic Usage

  ```elixir
  defmodule MyApp.Repo.Migrations.CreateEvents do
    use Ecto.Migration

    def up, do: Spector.Migration.up(table: "events")
    def down, do: Spector.Migration.down(table: "events")
  end
  ```

  ## Options

  * `:table` (required) - The database table name for the events
  * `:shards` - List of table names for sharded setups (creates multiple tables)
  * `:hashed` - Add a `hash` column for hash chain integrity (default: `false`)
  * `:links` - List of link tables to create: `[{"table_name", :foreign_key}, ...]`

  ## With Table Sharding

  For sharded event tables, use `:shards` to create multiple tables:

  ```elixir
  def up do
    Spector.Migration.up(shards: ["events_0", "events_1", "events_2", "events_3"])
  end

  def down do
    Spector.Migration.down(shards: ["events_0", "events_1", "events_2", "events_3"])
  end
  ```

  ## With Hash Chain Integrity

  If using hashed events, include the `:hashed` option:

  ```elixir
  def up, do: Spector.Migration.up(table: "events", hashed: true)
  def down, do: Spector.Migration.down(table: "events")
  ```

  ## With Event Links

  To create join tables for event linking (e.g., ancestry tracking):

  ```elixir
  def up do
    Spector.Migration.up(
      table: "events",
      links: [{"event_ancestors", :ancestor_id}]
    )
  end

  def down do
    Spector.Migration.down(
      table: "events",
      links: [{"event_ancestors", :ancestor_id}]
    )
  end
  ```

  Each link tuple creates a join table with `event_id` and the specified foreign key,
  along with indexes for efficient queries.

  ## Typed Link Tables

  To distinguish different relationship types on the same link table, use the
  `:typed` option to add a `type` integer column:

  ```elixir
  def up do
    Spector.Migration.up(
      table: "events",
      links: [{"event_links", :linked_id, typed: true}]
    )
  end
  ```

  The type column allows a single link table to represent multiple relationship types
  (e.g., "parent", "sibling", "reference") by assigning each type an integer value.

  It is recommended to use an Ecto schema for typed link tables. See the
  [Event Links Guide](links.md) for examples.

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

  @doc """
  Create the event table(s) and any link tables.

  Use `:table` for a single table or `:shards` for sharded setups.

  See module documentation for available options.
  """
  def up(opts) do
    tables = Keyword.get(opts, :shards) || [Keyword.fetch!(opts, :table)]
    hashed = Keyword.get(opts, :hashed, false)

    for table <- tables do
      create table(table, primary_key: false) do
        add(:id, :binary_id, primary_key: true)
        add(:parent_id, references(table, type: :binary_id), null: false)
        add(:payload, :map)
        add(:schema, :integer, null: false)
        add(:action, :integer, null: false)

        if hashed do
          add(:hash, :binary)
        end

        timestamps(type: :utc_datetime_usec)
      end

      create(index(table, [:schema]))
      create(index(table, [:parent_id]))
    end

    events_table = List.first(tables)

    for link <- Keyword.get(opts, :links, []) do
      link_up(events_table, link)
    end
  end

  @doc """
  Drop the event table(s) and any link tables.

  Pass the same options used in `up/1` to ensure link tables are also dropped.
  """
  def down(opts) do
    for link <- Keyword.get(opts, :links, []) do
      link_down(link)
    end

    tables = Keyword.get(opts, :shards) || [Keyword.fetch!(opts, :table)]

    for table <- tables do
      drop(table(table))
    end
  end

  @doc """
  Create a link table for many-to-many event relationships.

  Use this to add link tables in a separate migration after the events table exists.

  ## Parameters

  * `events_table` - The events table this link table references
  * `link_spec` - Either `{link_table, foreign_key}` or `{link_table, foreign_key, opts}`

  ## Options

  * `:typed` - Add a `type` integer column to distinguish different relationship types
    on the same link table (default: `false`)

  ## Examples

  Basic link table:

      Spector.Migration.link_up("events", {"event_ancestors", :ancestor_id})

  Link table with type column:

      Spector.Migration.link_up("events", {"event_links", :linked_id, typed: true})
  """
  def link_up(events_table, {link_table, foreign_key}) do
    link_up(events_table, {link_table, foreign_key, []})
  end

  def link_up(events_table, {link_table, foreign_key, opts}) do
    typed = Keyword.get(opts, :typed, false)

    create table(link_table, primary_key: false) do
      add(:event_id, references(events_table, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(foreign_key, references(events_table, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      if typed do
        add(:type, :integer, null: false)
      end
    end

    create(index(link_table, [:event_id]))
    create(index(link_table, [foreign_key]))

    if typed do
      create(unique_index(link_table, [:event_id, foreign_key, :type]))
    else
      create(unique_index(link_table, [:event_id, foreign_key]))
    end
  end

  @doc """
  Drop a link table.

  ## Example

      Spector.Migration.link_down({"event_ancestors", :ancestor_id})
  """
  def link_down({link_table, _foreign_key}) do
    drop(table(link_table))
  end

  def link_down({link_table, _foreign_key, _opts}) do
    drop(table(link_table))
  end
end
