defmodule Spector do
  @moduledoc """
  CQRS-style event sourcing for Ecto schemas.

  Use this module to define an event log table:

      defmodule MyApp.Events do
        use Spector, table: "events", schemas: [MyApp.User, MyApp.Post]
      end
  """

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    schemas = Keyword.fetch!(opts, :schemas)

    quote do
      use Ecto.Schema

      @primary_key {:id, UUIDv7, autogenerate: true}

      schema unquote(table) do
        field :parent_id, UUIDv7
        field :payload, :map
        field :schema, Ecto.Enum, values: unquote(schemas)
        field :action, Ecto.Enum, values: [:insert, :update, :delete]

        timestamps(type: :utc_datetime_usec)
      end
    end
  end
end
