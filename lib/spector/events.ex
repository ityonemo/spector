defmodule Spector.Events do
  @moduledoc """
  Define an event log table.

      defmodule MyApp.Events do
        use Spector.Events, table: "events", schemas: [MyApp.User, MyApp.Post]
      end
  """

  @action_values [insert: 1, update: 2, delete: 3]

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    schemas = Keyword.fetch!(opts, :schemas)
    repo = Keyword.fetch!(opts, :repo)
    # TODO: This auto-indexing scheme needs to be replaced with explicit mappings
    # to allow adding/removing/reordering schemas without breaking existing data
    schema_values = Enum.with_index(schemas, 1)

    quote do
      use Ecto.Schema
      alias Ecto.Changeset

      @primary_key {:id, UUIDv7, autogenerate: true}

      def __spector__(:repo), do: unquote(repo)

      schema unquote(table) do
        belongs_to :parent, __MODULE__, type: UUIDv7
        field :payload, :map
        field :schema, Ecto.Enum, values: unquote(schema_values)
        field :action, Ecto.Enum, values: unquote(@action_values)

        timestamps(type: :utc_datetime_usec)
      end

      def changeset(struct \\ %__MODULE__{}, attrs) do
        struct
        |> Changeset.cast(attrs, [:id, :parent_id, :payload, :schema, :action])
        |> Changeset.validate_required([:id, :parent_id, :schema, :action])
        |> Changeset.foreign_key_constraint(:parent_id)
      end

      def list_by_parent_id(parent_id) do
        import Ecto.Query
        unquote(repo).all(from e in __MODULE__, where: e.parent_id == ^parent_id, order_by: e.id)
      end
    end
  end
end
