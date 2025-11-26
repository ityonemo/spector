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

  defmacro __using__(opts) do
    events = Keyword.fetch!(opts, :events)

    quote do
      @primary_key {:id, UUIDv7, autogenerate: false}

      def __spector__(:events), do: unquote(events)
    end
  end
end
