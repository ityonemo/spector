defmodule Spector.Evented do
  @moduledoc """
  Mark a schema as evented, linking it to an event log table.

  ## Basic Usage

  ```elixir
  defmodule MyApp.User do
    use Spector.Evented, events: MyApp.Events
    use Ecto.Schema

    schema "users" do
      field :name, :string
    end

    def changeset(changeset, attrs) do
      changeset
      |> Ecto.Changeset.cast(attrs, [:name])
      |> Ecto.Changeset.validate_required([:name])
    end
  end
  ```

  ## Options

  * `:events` (required) - The events module (defined with `Spector.Events`)
  * `:repo` - Override the repo for this schema's table (default: uses events repo)
  * `:version` - Schema version for migrations (default: `0`). See "Schema Versioning" below
  * `:actions` - List of custom action atoms (default: `[]`). See "Custom Actions" below

  ## Custom Actions

  Beyond the built-in `:insert`, `:update`, and `:delete` actions, you can define
  custom actions for domain-specific operations:

  ```elixir
  defmodule MyApp.Item do
    use Spector.Evented,
      events: MyApp.Events,
      actions: [:archive, :restore]

    # Handle the archive action
    def changeset(changeset, attrs) when changeset.action == :archive do
      changeset
      |> Ecto.Changeset.change(archived_at: attrs[:archived_at])
    end

    # Handle other actions
    def changeset(changeset, attrs) do
      changeset
      |> Ecto.Changeset.cast(attrs, [:name, :value])
    end
  end
  ```

  Execute custom actions with `Spector.execute/3`:

  ```elixir
  {:ok, item} = Spector.execute(item, :archive, %{archived_at: DateTime.utc_now()})
  ```

  ## Schema Versioning

  When you change your schema (add/remove/rename fields), increment the version
  and handle migrations in your changeset:

  ```elixir
  defmodule MyApp.User do
    # Version 0: had :title field
    # Version 1: renamed :title to :name
    use Spector.Evented, events: MyApp.Events, version: 1

    schema "users" do
      field :name, :string
    end

    # Migrate v0 events (with :title) to v1 (with :name)
    def changeset(changeset, attrs) when version_is(attrs, 0) do
      attrs = Map.put(attrs, "name", attrs["title"])
      do_changeset(changeset, attrs)
    end

    def changeset(changeset, attrs), do: do_changeset(changeset, attrs)

    defp do_changeset(changeset, attrs) do
      changeset
      |> Ecto.Changeset.cast(attrs, [:name])
      |> Ecto.Changeset.validate_required([:name])
    end
  end
  ```

  The `version_is/2` and `version_in/2` guards help you handle different versions.

  During updates, Spector replays all stored events through your `changeset/2`
  function. Old events retain their original version, so your version guards
  automatically migrate historical data during replay.

  ## Generated Functions

  Using this module generates:

  * `__spector__/1` - Internal metadata accessor
  * Imports `version_in/2` and `version_is/2` guards
  * Sets `@primary_key` to `{:id, UUIDv7, autogenerate: false}` (Spector manages IDs)

  ## Customizing the Primary Key

  The default `@primary_key` can be overridden by defining it after `use Spector.Evented`:

  ```elixir
  defmodule MyApp.Record do
    use Spector.Evented, events: MyApp.Events
    use Ecto.Schema

    @primary_key {:uuid, UUIDv7, autogenerate: false}
    schema "records" do
      field :name, :string
    end
  end
  ```

  The primary key must be a binary type (not integer). This is validated at compile time.

  ## Optional Callbacks

  ### `prepare_event/3`

  Called before inserting an event, allowing last-minute modifications to the
  event changeset. Useful for populating link associations.

  ```elixir
  @behaviour Spector.Evented

  @impl true
  def prepare_event(event_changeset, existing_events, attrs) do
    # Modify event_changeset as needed
    event_changeset
  end
  ```

  The callback receives:
  * `event_changeset` - The changeset for the event about to be inserted
  * `existing_events` - All existing events for this record (with links preloaded)
  * `attrs` - The attributes passed to the action

  Note: `prepare_event/3` always runs inside a transaction.
  """

  @callback prepare_event(
              event_changeset :: Ecto.Changeset.t(),
              existing_events :: [struct()],
              attrs :: map()
            ) ::
              Ecto.Changeset.t()

  @optional_callbacks [prepare_event: 3]

  @doc """
  Creates a has_many association to the event log for this record.

  Use this inside your schema definition to add an association that retrieves
  all events for a given record.

  **Note:** This macro only works with database-backed schemas, not embedded schemas.
  Embedded schemas cannot use Ecto associations for preloading.

  ## Example

      defmodule MyApp.User do
        use Spector.Evented, events: MyApp.Events
        use Ecto.Schema

        schema "users" do
          field :name, :string
          event_log :log
        end
      end

  Then you can preload and access events:

      user = Repo.get(User, id) |> Repo.preload(:log)
      user.log  # Returns all events for this user
  """
  defmacro event_log(name) do
    quote do
      events_module = @__spector_events__
      schema_module = __MODULE__
      {pk_field, _, _} = @primary_key

      has_many(unquote(name), events_module,
        foreign_key: :parent_id,
        references: pk_field,
        where: [schema: schema_module],
        preload_order: [asc: :inserted_at]
      )
    end
  end

  @doc """
  Guard to check if attrs version is within a range or list of integers.

  Example: `def changeset(struct, attrs) when version_in(attrs, 0..2)`
  """
  defmacro version_in(attrs, range) do
    quote do
      (is_map_key(unquote(attrs), "__version__") and
         :erlang.map_get("__version__", unquote(attrs)) in unquote(range)) or
        (is_map_key(unquote(attrs), :__version__) and
           :erlang.map_get(:__version__, unquote(attrs)) in unquote(range))
    end
  end

  @doc """
  Guard to check if attrs version equals a specific integer.

  Example: `def changeset(struct, attrs) when version_is(attrs, 0)`
  """
  defmacro version_is(attrs, version) do
    quote do
      (is_map_key(unquote(attrs), "__version__") and
         :erlang.map_get("__version__", unquote(attrs)) == unquote(version)) or
        (is_map_key(unquote(attrs), :__version__) and
           :erlang.map_get(:__version__, unquote(attrs)) == unquote(version))
    end
  end

  defmacro __using__(opts) do
    events = Keyword.fetch!(opts, :events)
    repo = Keyword.get(opts, :repo)
    version = Keyword.get(opts, :version, 0)
    actions = Keyword.get(opts, :actions, [])

    quote do
      import Spector.Evented, only: [version_in: 2, version_is: 2, event_log: 1]

      @primary_key {:id, UUIDv7, autogenerate: false}
      @__spector_events__ unquote(events)

      def __spector__(:events), do: unquote(events)
      def __spector__(:repo), do: unquote(repo)
      def __spector__(:version), do: unquote(version)
      def __spector__(:actions), do: unquote(actions)
    end
  end
end
