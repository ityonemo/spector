defmodule Spector.Events do
  @moduledoc """
  Define an event log table for storing events from evented schemas.

  ## Basic Usage

      defmodule MyApp.Events do
        use Spector.Events,
          table: "events",
          schemas: [MyApp.User, MyApp.Post],
          repo: MyApp.Repo
      end

  ## Options

  * `:table` (required) - The database table name for storing events
  * `:schemas` (required) - List of schemas that will log events to this table
  * `:repo` (required) - The Ecto repo module to use for database operations
  * `:hashed` - Enable hash chain integrity (default: `false`). See "Hash Chain Integrity" below
  * `:aliases` - Action aliases for refactoring. See "Action Aliases" below

  ## Schema Indexing

  Schemas are stored as integers in the database. By default, schemas are
  auto-indexed starting from 0. To ensure stability when adding/removing schemas,
  you can specify explicit indexes:

      schemas: [MyApp.User, MyApp.Post, {MyApp.Comment, 10}]

  In this example, `User` gets index 0, `Post` gets index 1, and `Comment` gets
  index 10. This allows you to remove `Post` later without breaking existing data.

  ## Hash Chain Integrity

  Enable `hashed: true` to create a cryptographic hash chain linking all events:

      use Spector.Events,
        table: "events",
        schemas: [MyApp.User],
        repo: MyApp.Repo,
        hashed: true

  Each event's hash includes the previous event's hash, creating a tamper-evident
  chain. Any modification to historical events will break the chain.

  **Note:** Hash chain integrity requires PostgreSQL due to the use of
  `LOCK TABLE ... IN EXCLUSIVE MODE` for serialization.

  ## Action Aliases

  When refactoring action names, use aliases to maintain backwards compatibility
  with existing events in the database:

      use Spector.Events,
        table: "events",
        schemas: [MyApp.Item],
        repo: MyApp.Repo,
        aliases: [soft_delete: :archive]  # soft_delete uses archive's hash

  This allows renaming `:archive` to `:soft_delete` in your code while still
  reading old events that used `:archive`.

  ## Generated Functions

  Using this module generates the following functions:

  * `changeset/1`, `changeset/2` - Build an event changeset
  * `list_by_parent_id/1` - List all events for a given record ID
  * `backtrace/1` - List all events up to and including a given event
  * `__spector__/1` - Internal metadata accessor
  """

  @base_actions [insert: 1, update: 2, delete: 3]

  defp index_schemas(schemas, caller) do
    elem(for schema <- schemas, reduce: {[], 0} do
      {acc, index} ->
        case schema do
          {_, too_low} when index > too_low ->
            raise ArgumentError, "Schema #{inspect(schema)} has an index lower than a previous schema"
          {mod, index} ->
            {acc ++ [{Macro.expand(mod, caller), index}], index + 1}
          mod ->
            {acc ++ [{Macro.expand(mod, caller), index}], index + 1}
        end
    end, 0)
  end

  @doc false
  def action_value(action, aliases) do
    value = Keyword.get(aliases, action, action)
    {action, :erlang.phash2(value)}
  end

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    schemas = Keyword.fetch!(opts, :schemas)
    repo = Keyword.fetch!(opts, :repo)
    hashed = Keyword.get(opts, :hashed, false)
    aliases = Keyword.get(opts, :aliases, [])
    schema_values = index_schemas(schemas, __CALLER__)

    requires = for mod <- Keyword.keys(schema_values) do
      quote do
        require unquote(mod)

        if unquote(mod).__spector__(:events) != __MODULE__ do
          raise CompileError,
            description: "#{inspect(unquote(mod))} does not declare #{inspect(__MODULE__)} as its events module"
        end
      end
    end

    quote do
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

      schema unquote(table) do
        belongs_to :parent, __MODULE__, type: UUIDv7
        field :payload, :map
        field :schema, Ecto.Enum, values: unquote(schema_values)
        field :action, Ecto.Enum, values: action_values

        if unquote(hashed) do
          field :hash, :binary
        end

        timestamps(type: :utc_datetime_usec)
      end

      if unquote(hashed) do
        def changeset(struct \\ %__MODULE__{}, attrs) do
          struct
          |> Changeset.cast(attrs, [:id, :parent_id, :payload, :schema, :action, :hash])
          |> Changeset.validate_required([:id, :parent_id, :schema, :action, :hash])
          |> Changeset.foreign_key_constraint(:parent_id)
        end
      else
        def changeset(struct \\ %__MODULE__{}, attrs) do
          struct
          |> Changeset.cast(attrs, [:id, :parent_id, :payload, :schema, :action])
          |> Changeset.validate_required([:id, :parent_id, :schema, :action])
          |> Changeset.foreign_key_constraint(:parent_id)
        end
      end

      def list_by_parent_id(parent_id) do
        import Ecto.Query
        unquote(repo).all(from e in __MODULE__, where: e.parent_id == ^parent_id, order_by: e.id)
      end

      def backtrace(entry) do
        import Ecto.Query
        unquote(repo).all(from e in __MODULE__, where: e.parent_id == ^entry.parent_id and e.id <= ^entry.id, order_by: e.id)
      end
    end
  end
end
