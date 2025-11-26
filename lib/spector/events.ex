defmodule Spector.Events do
  @moduledoc """
  Define an event log table.

      defmodule MyApp.Events do
        use Spector.Events, table: "events", schemas: [MyApp.User, MyApp.Post]
      end
  """

  @base_actions [insert: 1, update: 2, delete: 3]

  defp index_schemas(schemas) do
    elem(for schema <- schemas, reduce: {[], 0} do
      {acc, index} ->
        case schema do
          {_, too_low} when index > too_low ->
            raise ArgumentError, "Schema #{inspect(schema)} has an index lower than a previous schema"
          {_mod, index} = s ->
            {acc ++ [s], index + 1}
          mod ->
            {acc ++ [{mod, index}], index + 1}
        end
    end, 0)
  end

  defp validate_and_get_actions({mod, _}, caller), do: validate_and_get_actions(mod, caller)

  defp validate_and_get_actions(mod, caller) do
    mod = Macro.expand(mod, caller)
    events_module = caller.module

    if not match?({:module, ^mod}, Code.ensure_loaded(mod)) do
      raise CompileError,
        description: "Schema #{inspect(mod)} is not loaded or does not exist"
    end

    if not function_exported?(mod, :__spector__, 1) do
      raise CompileError,
        description: "Schema #{inspect(mod)} does not `use Spector.Evented`"
    end

    if mod.__spector__(:events) != events_module do
      raise CompileError,
        description: "#{inspect(mod)} does not declare #{inspect(events_module)} as its events module"
    end

    mod.__spector__(:actions)
  end

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    schemas = Keyword.fetch!(opts, :schemas)
    repo = Keyword.fetch!(opts, :repo)
    hashed = Keyword.get(opts, :hashed, false)
    schema_values = index_schemas(schemas)

    # Collect custom actions from all schemas and validate
    custom_actions =
      schemas
      |> Enum.flat_map(&validate_and_get_actions(&1, __CALLER__))
      |> Enum.uniq()
      |> Enum.with_index(4)

    action_values = @base_actions ++ custom_actions

    quote do
      use Ecto.Schema
      alias Ecto.Changeset

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
