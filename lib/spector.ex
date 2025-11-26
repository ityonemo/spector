defmodule Spector do
  @moduledoc """
  CQRS-style event sourcing for Ecto schemas.

  Use this module to define an event log table:

      defmodule MyApp.Events do
        use Spector, table: "events", schemas: [MyApp.User, MyApp.Post]
      end
  """

  @action_values [insert: 1, update: 2, delete: 3]

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    schemas = Keyword.fetch!(opts, :schemas)
    # TODO: This auto-indexing scheme needs to be replaced with explicit mappings
    # to allow adding/removing/reordering schemas without breaking existing data
    schema_values = Enum.with_index(schemas, 1)

    quote do
      use Ecto.Schema

      @primary_key {:id, UUIDv7, autogenerate: true}

      schema unquote(table) do
        field :parent_id, UUIDv7
        field :payload, :map
        field :schema, Ecto.Enum, values: unquote(schema_values)
        field :action, Ecto.Enum, values: unquote(@action_values)

        timestamps(type: :utc_datetime_usec)
      end
    end
  end
end
