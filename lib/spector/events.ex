defmodule Spector.Events do
  @moduledoc """
  Define an event log table.

      defmodule MyApp.Events do
        use Spector.Events, table: "events", schemas: [MyApp.User, MyApp.Post]
      end
  """

  @base_actions [insert: 1, update: 2, delete: 3]

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    schemas = Keyword.fetch!(opts, :schemas)
    repo = Keyword.fetch!(opts, :repo)
    hashed = Keyword.get(opts, :hashed, false)
    # TODO: This auto-indexing scheme needs to be replaced with explicit mappings
    # to allow adding/removing/reordering schemas without breaking existing data
    schema_values = Enum.with_index(schemas, 1)

    # Collect custom actions from all schemas
    custom_actions =
      schemas
      |> Enum.map(&Macro.expand(&1, __CALLER__))
      |> Enum.flat_map(fn schema -> schema.__spector__(:actions) end)
      |> Enum.uniq()
      |> Enum.with_index(4)

    action_values = @base_actions ++ custom_actions

    requirements = for schema <- schemas do
      quote do
        require unquote(schema)

        if unquote(schema).__spector__(:events) != __MODULE__ do
          raise CompileError,
            description: "#{inspect(unquote(schema))} does not declare #{inspect(__MODULE__)} as its events module"
        end
      end
    end

    quote do
      use Ecto.Schema
      alias Ecto.Changeset

      unquote_splicing(requirements)

      @primary_key {:id, UUIDv7, autogenerate: true}

      def __spector__(:repo), do: unquote(repo)
      def __spector__(:hashed), do: unquote(hashed)

      schema unquote(table) do
        belongs_to :parent, __MODULE__, type: UUIDv7
        field :payload, :map
        field :schema, Ecto.Enum, values: unquote(schema_values)
        field :action, Ecto.Enum, values: unquote(action_values)

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
