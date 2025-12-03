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

  When combining shards with links, a link table is created for each shard by
  concatenating the shard name to the link table name. For example:

  ```elixir
  Spector.Migration.up(
    shards: ["events_0", "events_1"],
    links: [{"ancestors", :ancestor_id}]
  )
  ```

  This creates four tables: `events_0`, `events_1`, `events_0_ancestors`, and
  `events_1_ancestors`. If you need a different naming convention, omit the
  `:links` option and use `link_up/2` separately for each shard.

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
  along with indexes for efficient queries. A database trigger enforces that both
  ends of a link must have the same `parent_id` (i.e., links can only connect events
  within the same record).

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
    shards = Keyword.get(opts, :shards)
    tables = shards || [Keyword.fetch!(opts, :table)]
    hashed = Keyword.get(opts, :hashed, false)
    links = Keyword.get(opts, :links, [])

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

        timestamps(type: :utc_datetime_usec, updated_at: false)
      end

      create(index(table, [:schema]))
      create(index(table, [:parent_id]))
      create(index(table, [:inserted_at]))
    end

    for link <- links do
      if shards do
        # Create a link table for each shard with concatenated name
        for shard <- shards do
          link_up(shard, prefix_link(link, shard))
        end
      else
        link_up(List.first(tables), link)
      end
    end
  end

  defp prefix_link({link_table, foreign_key}, shard) do
    {"#{shard}_#{link_table}", foreign_key}
  end

  defp prefix_link({link_table, foreign_key, opts}, shard) do
    {"#{shard}_#{link_table}", foreign_key, opts}
  end

  @doc """
  Drop the event table(s) and any link tables.

  Pass the same options used in `up/1` to ensure link tables are also dropped.
  """
  def down(opts) do
    shards = Keyword.get(opts, :shards)
    tables = shards || [Keyword.fetch!(opts, :table)]
    links = Keyword.get(opts, :links, [])

    for link <- links do
      if shards do
        for shard <- shards do
          link_down(prefix_link(link, shard))
        end
      else
        link_down(link)
      end
    end

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
  * `:constrained` - Create a database trigger to enforce that linked events share the
    same `parent_id` (default: `true`). Set to `false` for non-PostgreSQL databases.

  ## Examples

  Basic link table:

      Spector.Migration.link_up("events", {"event_ancestors", :ancestor_id})

  Link table with type column:

      Spector.Migration.link_up("events", {"event_links", :linked_id, typed: true})

  Link table without parent_id constraint (for non-PostgreSQL databases):

      Spector.Migration.link_up("events", {"event_links", :linked_id, constrained: false})
  """
  def link_up(events_table, {link_table, foreign_key}) do
    link_up(events_table, {link_table, foreign_key, []})
  end

  def link_up(events_table, {link_table, foreign_key, opts}) do
    typed = Keyword.get(opts, :typed, false)
    constrained = Keyword.get(opts, :constrained, true)

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

    if constrained do
      # Create trigger to enforce same parent_id constraint
      execute("""
      CREATE OR REPLACE FUNCTION check_link_same_parent_#{link_table}()
      RETURNS TRIGGER AS $$
      DECLARE
        event_parent_id uuid;
        linked_parent_id uuid;
      BEGIN
        SELECT parent_id INTO event_parent_id FROM #{events_table} WHERE id = NEW.event_id;
        SELECT parent_id INTO linked_parent_id FROM #{events_table} WHERE id = NEW.#{foreign_key};

        IF event_parent_id != linked_parent_id THEN
          RAISE EXCEPTION 'Link events must have the same parent_id: % != %',
            event_parent_id, linked_parent_id;
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """)

      execute("""
      CREATE TRIGGER enforce_same_parent_#{link_table}
        BEFORE INSERT ON #{link_table}
        FOR EACH ROW
        EXECUTE FUNCTION check_link_same_parent_#{link_table}();
      """)
    end
  end

  @doc """
  Drop a link table.

  ## Example

      Spector.Migration.link_down({"event_ancestors", :ancestor_id})
  """
  def link_down({link_table, foreign_key}) do
    link_down({link_table, foreign_key, []})
  end

  def link_down({link_table, _foreign_key, opts}) do
    constrained = Keyword.get(opts, :constrained, true)

    if constrained do
      execute("DROP TRIGGER IF EXISTS enforce_same_parent_#{link_table} ON #{link_table}")
      execute("DROP FUNCTION IF EXISTS check_link_same_parent_#{link_table}()")
    end

    drop(table(link_table))
  end
end
