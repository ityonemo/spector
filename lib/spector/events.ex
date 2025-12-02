defmodule Spector.Events do
  @moduledoc """
  Define an event log table for storing events from evented schemas.

  ## Basic Usage

  ```elixir
  defmodule MyApp.Events do
    use Spector.Events,
      table: "events",
      schemas: [MyApp.User, MyApp.Post],
      repo: MyApp.Repo
  end
  ```

  ## Options

  * `:table` (required) - The database table name for storing events
  * `:schemas` (required) - List of schemas that will log events to this table
  * `:repo` (required) - The Ecto repo module to use for database operations
  * `:hashed` - Enable hash chain integrity (default: `false`). See "Hash Chain Integrity" below
  * `:aliases` - Action aliases for refactoring. See "Action Aliases" below
  * `:shard` - Sharding function name (atom). See "Table Sharding" below
  * `:links` - List of link associations for many-to-many relationships. See "Event Links" below

  ## Table Sharding

  For high-volume event logs, you can shard events across multiple tables using
  the `:shard` option. Specify a function name (atom) that takes a `parent_id`
  and returns the table name:

  ```elixir
  defmodule MyApp.Events do
    use Spector.Events,
      table: "events",  # base table name (used for schema definition)
      schemas: [MyApp.User],
      repo: MyApp.Repo,
      shard: :shard_table

    def shard_table(parent_id) do
      # Shard based on first byte of UUID
      <<first_byte, _rest::binary>> = parent_id
      "events_\#{rem(first_byte, 4)}"
    end
  end
  ```

  You'll need to create migrations for each shard table. The sharding function
  must be deterministic - the same `parent_id` must always map to the same table.

  When combining sharding with hash chain integrity (`hashed: true`), each shard
  table maintains its own independent hash chain.

  ## Event Links

  Enable event linking with the `:links` option to create many-to-many relationships
  between events:

  ```elixir
  use Spector.Events,
    table: "events",
    schemas: [MyApp.Chat],
    repo: MyApp.Repo,
    links: [ancestors: {"event_ancestors", :ancestor_id}]
  ```

  Each link creates a join table and a `many_to_many` association on the events module.
  You can define multiple links:

  ```elixir
  links: [
    ancestors: {"event_ancestors", :ancestor_id},
    categories: {"event_categories", :category_id}
  ]
  ```

  For links that use an Ecto schema module, pass the module instead of a table name:

  ```elixir
  links: [links: {MyApp.EventLink, :linked_id}]
  ```

  The two approaches differ in what the association returns:

  - **Table name string**: Creates a `many_to_many` association. Preloading returns the
    linked **events** directly. You cannot use `put_assoc` to set fields on the join table.

  - **Schema module**: Creates a `has_many` association. Preloading returns the **link
    records** themselves (e.g., `%EventLink{event_id: ..., linked_id: ..., type: ...}`).
    You can use `put_assoc` in `prepare_event/3` to create links with custom fields.

  Use a schema module when you need to store metadata on links (types, timestamps, etc.)
  or need to create links via `put_assoc`. Use a table name string for simple joins where
  you only care about which events are connected.

  See the [Event Links Guide](links.md) for details.

  ### Sharding with Links

  When combining sharding with links, a separate link table is created for each shard.
  Use `link_table_for/2` to get the correct link table name for a given parent_id:

  ```elixir
  def prepare_event(event_changeset, _previous_events, attrs) do
    parent_id = Ecto.Changeset.get_field(event_changeset, :parent_id)
    link_table = MyEvents.link_table_for(parent_id, "ancestors")

    link = %MyLink{ancestor_id: attrs[:ancestor_id]}
    link = Ecto.put_meta(link, source: link_table)

    Ecto.Changeset.put_assoc(event_changeset, :ancestors, [link])
  end
  ```

  ## Schema Indexing

  Schemas are stored as integers in the database. By default, schemas are
  auto-indexed starting from 0. To ensure stability when adding/removing schemas,
  you can specify explicit indexes:

  ```elixir
  schemas: [MyApp.User, MyApp.Post, {MyApp.Comment, 10}]
  ```

  In this example, `User` gets index 0, `Post` gets index 1, and `Comment` gets
  index 10. This allows you to remove `Post` later without breaking existing data.

  ## Hash Chain Integrity

  Enable `hashed: true` to create a cryptographic hash chain linking all events:

  ```elixir
  use Spector.Events,
    table: "events",
    schemas: [MyApp.User],
    repo: MyApp.Repo,
    hashed: true
  ```

  Each event's hash includes the previous event's hash, creating a tamper-evident
  chain. Any modification to historical events will break the chain.

  **Note:** Hash chain integrity requires PostgreSQL due to the use of
  `LOCK TABLE ... IN EXCLUSIVE MODE` for serialization.

  ## Action Aliases

  When refactoring action names, use aliases to maintain backwards compatibility
  with existing events in the database:

  ```elixir
  use Spector.Events,
    table: "events",
    schemas: [MyApp.Item],
    repo: MyApp.Repo,
    aliases: [soft_delete: :archive]  # soft_delete uses archive's hash
  ```

  This allows renaming `:archive` to `:soft_delete` in your code while still
  reading old events that used `:archive`.

  ## Compilation Dependencies

  Using this module creates a compilation dependency on all schema modules
  listed in the `:schemas` option. This means changes to those schema modules
  will trigger recompilation of the events module.

  ## Generated Functions

  Using this module generates the following functions:

  * `changeset/1`, `changeset/2` - Build an event changeset
  * `list_by_parent_id/2` - List all events for a given record ID and schema
  * `backtrace/1` - List all events up to and including a given event
  * `table_for/1` - Get the table name for a given parent_id
  * `shard/2` - Apply sharding to a changeset
  * `__spector__/1` - Internal metadata accessor
  """

  @doc """
  Build an event changeset from attributes.
  """
  @callback changeset(attrs :: map()) :: Ecto.Changeset.t()

  @doc """
  Build an event changeset from an existing struct and attributes.
  """
  @callback changeset(struct :: struct(), attrs :: map()) :: Ecto.Changeset.t()

  @doc """
  List all events for a given parent_id and schema, ordered by id.
  """
  @callback list_by_parent_id(parent_id :: binary(), schema :: module()) :: [struct()]

  @doc """
  List all events up to and including a given event, ordered by id.

  Useful for reconstructing state at a specific point in time.
  """
  @callback backtrace(entry :: struct()) :: [struct()]

  @doc """
  Get the table name for a given parent_id.

  For non-sharded tables, returns the configured table name.
  For sharded tables, calls the shard function to determine the table.
  """
  @callback table_for(parent_id :: binary()) :: String.t()

  @doc """
  Apply sharding to a changeset based on the parent_id.

  Updates the changeset's data source to the appropriate shard table.
  """
  @callback shard(changeset :: Ecto.Changeset.t(), parent_id :: binary()) :: Ecto.Changeset.t()

  @doc """
  Get the link table name for a given parent_id and base link table name.

  With sharding, link tables are prefixed with the shard table name.
  Without sharding, returns the link table name unchanged.
  """
  @callback link_table_for(parent_id :: binary(), link_table :: String.t()) :: String.t()

  @base_actions [insert: 1, update: 2, delete: 3, savepoint: 4]

  defp index_schemas(schemas, caller) do
    elem(
      for schema <- schemas, reduce: {[], 0} do
        {acc, index} ->
          case schema do
            {_, too_low} when index > too_low ->
              raise ArgumentError,
                    "Schema #{inspect(schema)} has an index lower than a previous schema"

            {mod, index} ->
              {acc ++ [{Macro.expand(mod, caller), index}], index + 1}

            mod ->
              {acc ++ [{Macro.expand(mod, caller), index}], index + 1}
          end
      end,
      0
    )
  end

  @doc false
  def action_value(action, aliases) do
    value = Keyword.get(aliases, action, action)
    {action, :erlang.phash2(value)}
  end

  @doc false
  def validate_primary_key!(schema) do
    case schema.__schema__(:primary_key) do
      [] ->
        raise CompileError,
          description: "#{inspect(schema)} must have a primary key"

      [pk_field] ->
        pk_type = schema.__schema__(:type, pk_field)

        if pk_type in [:id, :integer] do
          raise CompileError,
            description:
              "#{inspect(schema)} primary key #{inspect(pk_field)} must be a binary type, got: #{inspect(pk_type)}"
        end

      pk_fields when is_list(pk_fields) ->
        raise CompileError,
          description:
            "#{inspect(schema)} must have a single primary key, got: #{inspect(pk_fields)}"
    end
  end

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    schemas = Keyword.fetch!(opts, :schemas)
    repo = Keyword.fetch!(opts, :repo)
    hashed = Keyword.get(opts, :hashed, false)
    aliases = Keyword.get(opts, :aliases, [])
    shard = Keyword.get(opts, :shard)
    links = Keyword.get(opts, :links, [])
    schema_values = index_schemas(schemas, __CALLER__)
    hash_field = List.wrap(if hashed, do: :hash)

    requires =
      for mod <- Keyword.keys(schema_values) do
        quote do
          require unquote(mod)

          if unquote(mod).__spector__(:events) != __MODULE__ do
            raise CompileError,
              description:
                "#{inspect(unquote(mod))} does not declare #{inspect(__MODULE__)} as its events module"
          end

          Spector.Events.validate_primary_key!(unquote(mod))
        end
      end

    quote do
      @behaviour Spector.Events

      use Ecto.Schema
      alias Ecto.Changeset

      unquote_splicing(requires)

      # Collect custom actions from all schemas
      custom_actions =
        unquote(Keyword.keys(schema_values))
        |> Enum.flat_map(fn mod -> mod.__spector__(:actions) end)
        |> Enum.uniq()
        |> Enum.map(&unquote(__MODULE__).action_value(&1, unquote(aliases)))

      action_values = unquote(@base_actions) ++ custom_actions

      @primary_key {:id, UUIDv7, autogenerate: true}

      def __spector__(:repo), do: unquote(repo)
      def __spector__(:hashed), do: unquote(hashed)
      def __spector__(:shard), do: unquote(shard)
      def __spector__(:links), do: unquote(links)

      if unquote(shard) do
        @doc false
        def shard(changeset, parent_id) do
          %{changeset | data: Ecto.put_meta(changeset.data, source: unquote(shard)(parent_id))}
        end

        @doc false
        def table_for(parent_id), do: unquote(shard)(parent_id)

        @doc false
        def link_table_for(parent_id, link_table) do
          "#{table_for(parent_id)}_#{link_table}"
        end

        defoverridable link_table_for: 2
      else
        @doc false
        def shard(changeset, _parent_id), do: changeset

        @doc false
        def table_for(_parent_id), do: unquote(table)

        @doc false
        def link_table_for(_parent_id, link_table), do: link_table
      end

      schema unquote(table) do
        belongs_to(:parent, __MODULE__, type: UUIDv7)
        field(:payload, :map)
        field(:schema, Ecto.Enum, values: unquote(schema_values))
        field(:action, Ecto.Enum, values: action_values)

        if unquote(hashed) do
          field(:hash, :binary)
        end

        for {assoc_name, link_spec} <- unquote(links) do
          case link_spec do
            {table, foreign_key} when is_binary(table) ->
              many_to_many(assoc_name, __MODULE__,
                join_through: table,
                join_keys: [{:event_id, :id}, {foreign_key, :id}]
              )

            {schema_module, foreign_key} when is_atom(schema_module) ->
              # For schema modules, create a has_many for the join schema
              # This allows using put_assoc with the link schema directly
              has_many(assoc_name, schema_module, foreign_key: :event_id)
          end
        end

        timestamps(type: :utc_datetime_usec)
      end

      @required_fields ~w[id parent_id schema action]a ++ unquote(hash_field)
      @all_fields @required_fields ++ ~w[payload]a

      def changeset(struct \\ %__MODULE__{}, attrs) do
        struct
        |> Changeset.cast(attrs, @all_fields)
        |> Changeset.validate_required(@required_fields)
        |> Changeset.foreign_key_constraint(:parent_id)
        |> then(&shard(&1, Changeset.get_field(&1, :parent_id)))
      end

      def list_by_parent_id(parent_id, schema) do
        import Ecto.Query
        table = table_for(parent_id)

        unquote(repo).all(
          from(e in {table, __MODULE__},
            where: e.parent_id == ^parent_id and e.schema == ^schema,
            order_by: [asc: e.inserted_at]
          )
        )
      end

      def backtrace(entry) do
        import Ecto.Query
        table = table_for(entry.parent_id)

        unquote(repo).all(
          from(e in {table, __MODULE__},
            where: e.parent_id == ^entry.parent_id and e.id <= ^entry.id,
            order_by: e.id
          )
        )
      end
    end
  end
end
