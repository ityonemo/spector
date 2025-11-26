defmodule Spector.Evented do
  @moduledoc """
  Mark a schema as evented, linking it to an event log table.

      defmodule MyApp.User do
        use Spector.Evented, events: MyApp.Events
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
  """

  @doc """
  Guard to check if attrs version is within a range or list of integers.

  Example: `def changeset(struct, attrs) when version_in(attrs, 0..2)`
  """
  defmacro version_in(attrs, range) do
    quote do
      (is_map_key(unquote(attrs), "version") and (:erlang.map_get("version", unquote(attrs)) in unquote(range))) or
      (is_map_key(unquote(attrs), :version) and (:erlang.map_get(:version, unquote(attrs)) in unquote(range)))
    end
  end

  @doc """
  Guard to check if attrs version equals a specific integer.

  Example: `def changeset(struct, attrs) when version_is(attrs, 0)`
  """
  defmacro version_is(attrs, version) do
    quote do
      (is_map_key(unquote(attrs), "version") and :erlang.map_get("version", unquote(attrs)) == unquote(version)) or
        (is_map_key(unquote(attrs), :version) and :erlang.map_get(:version, unquote(attrs)) == unquote(version))
    end
  end

  defmacro __using__(opts) do
    events = Keyword.fetch!(opts, :events)
    version = Keyword.get(opts, :version, 0)
    actions = Keyword.get(opts, :actions, [])

    quote do
      import Spector.Evented, only: [version_in: 2, version_is: 2]

      @primary_key {:id, UUIDv7, autogenerate: false}

      def __spector__(:events), do: unquote(events)
      def __spector__(:version), do: unquote(version)
      def __spector__(:actions), do: unquote(actions)
    end
  end
end
