defmodule Spector do
  @typedoc "An Ecto schema module that uses `Spector.Evented`"
  @type evented_schema :: module()

  @typedoc "A struct instance of an evented schema"
  @type evented_struct :: struct()

  @typedoc "Attributes map passed to changesets"
  @type attrs :: map()

  @typedoc "An action atom (e.g., :insert, :update, :delete, or custom actions)"
  @type action :: atom()

  @typedoc "Options for `bringup/2`"
  @type bringup_opts :: [
          action: action(),
          attr_fn: (evented_struct() -> attrs()),
          transfer: (evented_struct(), evented_struct() -> any())
        ]

  @moduledoc """
  CQRS-style event sourcing for Ecto schemas.

  Spector records all changes to your Ecto schemas as events in a separate event
  log table. This enables full audit trails, temporal queries, and the ability to
  replay history. For tamper-evident logs, enable optional hash chain integrity.

  ## Quick Start

  ### 1. Define an Events Table

  ```elixir
  defmodule MyApp.Events do
    use Spector.Events,
      table: "events",
      schemas: [MyApp.User, MyApp.Post],
      repo: MyApp.Repo
  end
  ```

  ### 2. Mark Schemas as Evented

  ```elixir
  defmodule MyApp.User do
    use Spector.Evented, events: MyApp.Events
    use Ecto.Schema

    schema "users" do
      field :name, :string
      field :email, :string
    end

    def changeset(changeset, attrs) do
      changeset
      |> Ecto.Changeset.cast(attrs, [:name, :email])
      |> Ecto.Changeset.validate_required([:name, :email])
    end
  end
  ```

  ### 3. Create Migrations

  ```elixir
  defmodule MyApp.Repo.Migrations.CreateEvents do
    use Ecto.Migration

    def up, do: Spector.Migration.up(table: "events")
    def down, do: Spector.Migration.down(table: "events")
  end
  ```

  ### 4. Use Spector Instead of Repo

  ```elixir
  # Insert
  {:ok, user} = Spector.insert(MyApp.User, %{name: "Alice", email: "alice@example.com"})

  # Update
  {:ok, user} = Spector.update(user, %{name: "Alice Smith"})

  # Delete
  {:ok, user} = Spector.delete(user)
  ```

  ## How It Works

  When you update or execute an action on a record, Spector "rolls forward" by
  replaying all stored events through your schema's `changeset/2` function. This means:

  - Your changeset function handles both new operations AND historical replay
  - Schema migrations happen automatically during replay (using version guards)
  - The current state is always reconstructed from the event log
  - Stale in-memory records are never a problem

  This design lets you evolve your schema over time while maintaining full
  compatibility with historical events.

  ## Guides

  For complete examples of building applications with Spector:

  - [Building an AI Chat Log](AI_chat.md) - Conversation branching with tree-structured message history
  - [Building a Basic Chat](basic_chat.md) - Simple chat with edit history tracking

  ## Features

  ### Custom Actions

  Define domain-specific actions beyond insert/update/delete:

  ```elixir
  defmodule MyApp.Item do
    use Spector.Evented, events: MyApp.Events, actions: [:archive]

    def changeset(changeset, attrs) when changeset.action == :archive do
      Ecto.Changeset.change(changeset, archived_at: Spector.get_attr(attrs, :archived_at))
    end

    def changeset(changeset, attrs) do
      Ecto.Changeset.cast(changeset, attrs, [:name, :value])
    end
  end

  # Execute custom action
  {:ok, item} = Spector.execute(item, :archive, %{archived_at: DateTime.utc_now()})
  ```

  ### Schema Versioning

  Handle schema migrations with version guards:

  ```elixir
  defmodule MyApp.User do
    use Spector.Evented, events: MyApp.Events, version: 1

    # Migrate v0 events (with :title) to v1 (with :name)
    def changeset(changeset, attrs) when version_is(attrs, 0) do
      attrs = Map.put(attrs, "name", Spector.get_attr(attrs, :title))
      do_changeset(changeset, attrs)
    end

    def changeset(changeset, attrs), do: do_changeset(changeset, attrs)
  end
  ```

  ### Hash Chain Integrity

  Enable tamper-evident event logs with cryptographic hashing:

  ```elixir
  defmodule MyApp.Events do
    use Spector.Events,
      table: "events",
      schemas: [MyApp.User],
      repo: MyApp.Repo,
      hashed: true
  end
  ```

  ### Explicit Schema Indexing

  Ensure stability when adding/removing schemas:

  ```elixir
  schemas: [MyApp.User, MyApp.Post, {MyApp.Comment, 10}]
  ```

  ### Action Aliases

  Maintain backwards compatibility when renaming actions:

  ```elixir
  use Spector.Events,
    aliases: [soft_delete: :archive]
  ```

  ## Reserved Attributes

  Spector injects reserved attributes into the `attrs` map passed to your
  `changeset/2` function. These provide metadata about the event being applied:

  - `:__version__` - The schema version when the event was created. Use with
    `version_is/2` guards to handle schema migrations during replay.

  - `:__event_id__` - The unique ID of the event being applied. Use
    `Spector.changeset_put_event_id/3` to assign this to a field:

    ```elixir
    def changeset(message, attrs) do
      message
      |> Ecto.Changeset.cast(attrs, [:content])
      |> Spector.changeset_put_event_id(attrs)  # puts :__event_id__ into :id field
    end
    ```

  These attributes are also stored in the event payload for reference.

  ## Database Support

  Spector works with any database supported by Ecto for basic functionality.

  **Note:** Hashed event tables (`hashed: true`) currently require PostgreSQL.
  The hash chain integrity feature uses `LOCK TABLE ... IN EXCLUSIVE MODE` which
  is PostgreSQL-specific.
  """

  alias Ecto.Adapters.SQL
  alias Ecto.Changeset
  alias Spector.Query

  defp get_repo(schema, events) do
    schema.__spector__(:repo) || events.__spector__(:repo)
  end

  @doc """
  Insert a new record, creating an event in the event log.

  Returns `{:ok, struct}` on success or `{:error, changeset}` on failure.

  ## Example

      {:ok, user} = Spector.insert(MyApp.User, %{name: "Alice", email: "alice@example.com"})

  The inserted struct will have a new UUIDv7 `id` assigned.
  """
  @spec insert(evented_schema(), attrs()) ::
          {:ok, evented_struct()} | {:error, Ecto.Changeset.t()}
  @spec insert(evented_schema(), attrs(), action()) ::
          {:ok, evented_struct()} | {:error, Ecto.Changeset.t()}
  def insert(schema, attrs, action \\ :insert) do
    events = schema.__spector__(:events)
    repo = get_repo(schema, events)
    version = schema.__spector__(:version)
    id = UUIDv7.generate()
    # TODO: in the future we might want to support alternative timestamp field names
    now = DateTime.utc_now()

    # inserted_at and updated_at are put_new so that we may override them for bringup operations
    # (we want the record to be branded with its original timestamps). The event will still have
    # the accurate inserted_at timestamp.
    attrs =
      attrs
      |> Map.put(:__version__, version)
      |> Map.put(:__event_id__, id)
      |> Map.put_new(:inserted_at, now)
      |> Map.put_new(:updated_at, now)

    changeset =
      schema
      |> struct!()
      |> Changeset.change()
      |> _set_changeset_action(action)
      |> schema.changeset(attrs)

    if changeset.valid? do
      repo.transact(fn ->
        event_attrs = %{
          id: id,
          parent_id: id,
          schema: schema,
          action: action,
          payload: attrs,
          inserted_at: now
        }

        event_attrs = maybe_add_hash(events, event_attrs, id)
        [pk_field] = schema.__schema__(:primary_key)
        record_changeset = Changeset.put_change(changeset, pk_field, id)

        event_attrs
        |> events.changeset()
        |> maybe_prepare_event([], attrs)
        |> repo.insert()
        |> case do
          {:ok, _event} ->
            do_insert(record_changeset, repo, schema)

          {:error, event_changeset} ->
            {:error, event_changeset}
        end
      end)
    else
      {:error, changeset}
    end
  end

  defp do_insert(changeset, repo, schema) do
    if schema.__schema__(:source) do
      changeset
      |> _set_changeset_action(:insert)
      |> maybe_prepare_materialization(schema)
      |> repo.insert()
    else
      Changeset.apply_action(changeset, :insert)
    end
  end

  defp do_update(changeset, repo, schema) do
    if schema.__schema__(:source) do
      changeset
      |> _set_changeset_action(:update)
      |> maybe_prepare_materialization(schema)
      |> repo.update()
    else
      Changeset.apply_action(changeset, :update)
    end
  end

  @doc """
  Update an existing record, creating an event in the event log.

  This is a convenience function that calls `execute(record, :update, attrs)`.

  Returns `{:ok, struct}` on success or `{:error, changeset}` on failure.

  ## Example

      {:ok, user} = Spector.update(user, %{name: "Alice Smith"})
  """
  @spec update(evented_struct(), attrs()) ::
          {:ok, evented_struct()} | {:error, Ecto.Changeset.t()}
  def update(record, attrs) do
    execute(record, :update, attrs)
  end

  @doc """
  Retrieve the current state of a record by replaying its events.

  Returns the struct if found, or `nil` if no events exist for the given ID.

  This is useful for embedded schemas (without database tables) or when you
  want to reconstruct state purely from the event log.

  ## Example

      user = Spector.get(MyApp.User, "019ac640-dfc0-7407-8238-39a9c45e8813")
  """
  @spec get(evented_schema(), String.t()) :: evented_struct() | nil
  def get(schema, parent_id) do
    schema
    |> recent_events(parent_id)
    |> roll_forward()
    |> and_apply(:get)
  end

  @doc """
  Materialize a record from the event log into its database table.

  Takes an events module and parent_id, replays all events to reconstruct the
  record, and inserts it into the database.

  Returns `{:ok, struct}` on success, or an error tuple:
  - `{:error, :invalid}` - No events exist for the given parent_id
  - `{:error, :deleted}` - Event history ends with a delete action
  - `{:error, changeset}` - Insert failed (e.g., record already exists)

  ## Example

      {:ok, user} = Spector.materialize(MyApp.Events, parent_id)
  """
  @spec materialize(module(), Ecto.UUID.t()) ::
          {:ok, evented_struct()} | {:error, :invalid | :deleted | Ecto.Changeset.t()}
  def materialize(events_module, parent_id) do
    import Ecto.Query
    repo = events_module.__spector__(:repo)
    table = events_module.table_for(parent_id)

    events =
      from(e in {table, events_module},
        where: e.parent_id == ^parent_id,
        order_by: [asc: e.inserted_at]
      )
      |> repo.all()

    cond do
      changeset = roll_forward(events) ->
        schema = hd(events).schema

        if !schema.__schema__(:source) do
          raise ArgumentError,
                "materialize/2 requires a database-backed schema, " <>
                  "but #{inspect(schema)} is an embedded schema"
        end

        changeset
        |> _set_changeset_action(:insert)
        |> maybe_prepare_materialization(schema)
        |> repo.insert()

      Enum.empty?(events) ->
        {:error, :invalid}

      :else ->
        {:error, :deleted}
    end
  rescue
    error in Ecto.ConstraintError ->
      {:error, Changeset.add_error(%Changeset{}, :id, error.message)}
  end

  @doc """
  Returns all events for a record from the beginning.

  Events are returned in insertion order.

  ## Example

      events = Spector.all_events(MyApp.User, user_id)
  """
  @spec all_events(evented_schema(), Ecto.UUID.t()) :: [struct()]
  def all_events(schema, parent_id) do
    events_module = schema.__spector__(:events)
    repo = get_repo(schema, events_module)

    schema
    |> Query.all_events(parent_id)
    |> repo.all()
  end

  @doc """
  Returns events starting from the most recent savepoint.

  If no savepoint exists, returns all events from the beginning.
  The savepoint event itself is included as the first element.

  Events are returned in insertion order.

  Use of this function over `all_events/2` is preferable; if the
  schema does not support savepoints, the two functions behave
  identically.

  ## Example

      events = Spector.recent_events(MyApp.User, user_id)
  """
  @spec recent_events(evented_schema(), Ecto.UUID.t()) :: [struct()]
  def recent_events(schema, parent_id) do
    events_module = schema.__spector__(:events)
    repo = get_repo(schema, events_module)

    schema
    |> Query.recent_events(parent_id)
    |> repo.all()
  end

  @doc """
  Returns all events up to and including the given event.

  Events are returned in insertion order. The specified event is included
  as the last element in the result.

  > ### Note {: .warning }
  >
  > This function does not take into account savepoints.

  ## Example

      events = Spector.previous_events(event)
  """
  def previous_events(event) do
    events_module = event.__struct__
    [pk_field] = events_module.__schema__(:primary_key)
    event_id = Map.fetch!(event, pk_field)
    repo = events_module.__spector__(:repo)

    events_module
    |> Query.previous_events(event.parent_id, event_id)
    |> repo.all()
  end

  @doc """
  Import existing database records into the event log.

  Reads all rows from the schema's table and migrates each to Spector management:
  deletes the original record and creates a new one with a UUIDv7 ID and
  corresponding event. The entire operation runs in a single transaction.

  Records that are already tracked by Spector (have existing events) are skipped.

  ## Options

    * `:action` - The action to use for the event (default: `:insert`). Use a custom
      action like `:import` to trigger different changeset behavior during migration.

    * `:attr_fn` - A function that takes a record and returns the attributes map to
      insert (default: extracts all schema fields except the primary key). Use this to
      transform or augment data during migration.

    * `:transfer` - A function that receives the old record and the new record before
      the old record is deleted. Use this to update associations or perform other
      transfer operations (default: no-op).

  Returns `{:ok, [struct]}` on success or `{:error, reason}` on failure.

  ## Timestamps

  By default, bringup creates new records, so `inserted_at` and `updated_at` timestamps
  will be set to the current time. To preserve original timestamps from the source
  records, include them in the attr_fn and ensure your changeset accepts them.

  If you don't want your regular changeset to accept timestamp fields, use a custom
  action like `:import` to handle them separately:

      # Register :import as a custom action
      use Spector.Evented, events: MyApp.Events, actions: [:import]

      # Handle :import with timestamp support
      def changeset(changeset, attrs) when changeset.action == :import do
        changeset
        |> cast(attrs, [:name, :inserted_at, :updated_at])
        |> validate_required([:name])
      end

      # Regular changeset doesn't accept timestamps
      def changeset(changeset, attrs) do
        changeset
        |> cast(attrs, [:name])
        |> validate_required([:name])
      end

      # Pass timestamps in attr_fn
      attr_fn = fn record ->
        %{name: record.name, inserted_at: record.inserted_at, updated_at: record.updated_at}
      end

      {:ok, users} = Spector.bringup(MyApp.User, action: :import, attr_fn: attr_fn)

  ## Examples

  Basic usage migrates all untracked records (timestamps reset to now):

      {:ok, users} = Spector.bringup(MyApp.User)

  Use a custom attr_fn to transform data during migration:

      {:ok, users} = Spector.bringup(MyApp.User, attr_fn: fn record ->
        %{
          name: String.upcase(record.name),
          value: record.value || 0  # provide defaults for nil values
        }
      end)

  Use a transfer function to update associations before the old record is deleted:

      {:ok, users} = Spector.bringup(MyApp.User, transfer: fn old, new ->
        Repo.update_all(
          from(p in Post, where: p.user_id == ^old.id),
          set: [user_id: new.id]
        )
      end)
  """
  @spec bringup(evented_schema()) :: {:ok, [evented_struct()]}
  @spec bringup(evented_schema(), bringup_opts()) :: {:ok, [evented_struct()]}
  def bringup(schema, opts \\ []) do
    action = Keyword.get(opts, :action, :insert)
    attr_fn = Keyword.get(opts, :attr_fn, &from_record/1)
    transfer_fn = Keyword.get(opts, :transfer, fn _, _ -> :ok end)

    events = schema.__spector__(:events)
    repo = get_repo(schema, events)

    repo.transact(fn ->
      new_records =
        schema
        |> Query.records_without_events()
        |> repo.all()
        |> Enum.map(&bringup_record(&1, schema, attr_fn, transfer_fn, repo, action))

      {:ok, new_records}
    end)
  end

  defp bringup_record(record, schema, attr_fn, transfer_fn, repo, action) do
    attrs = attr_fn.(record)

    case insert(schema, attrs, action) do
      {:ok, new_record} ->
        transfer_fn.(record, new_record)
        repo.delete!(record)
        new_record

      {:error, changeset} ->
        raise "Failed to bringup record #{inspect(record)}: #{inspect(changeset)}"
    end
  end

  defp from_record(record) do
    schema = record.__struct__
    [pk_field] = schema.__schema__(:primary_key)

    :fields
    |> schema.__schema__()
    |> then(&Map.take(record, &1))
    |> Map.delete(pk_field)
  end

  defp and_apply(nil, _action), do: nil
  defp and_apply(changeset, action), do: Changeset.apply_action!(changeset, action)

  defp or_crash(nil), do: raise("No such record")
  defp or_crash(changeset), do: changeset

  @doc """
  Delete a record, creating a delete event in the event log.

  Returns `{:ok, struct}` on success or `{:error, changeset}` on failure.

  The delete event is recorded in the event log before the record is removed
  from the database, providing a complete audit trail.

  ## Example

      {:ok, user} = Spector.delete(user)
  """
  @spec delete(evented_struct()) :: {:ok, evented_struct()} | {:error, Ecto.Changeset.t()}
  def delete(record) do
    schema = record.__struct__
    events = schema.__spector__(:events)
    repo = get_repo(schema, events)
    [pk_field] = schema.__schema__(:primary_key)
    parent_id = Map.fetch!(record, pk_field)

    repo.transact(fn ->
      id = UUIDv7.generate()
      now = DateTime.utc_now()

      event_attrs = %{
        id: id,
        parent_id: parent_id,
        schema: schema,
        action: :delete,
        payload: %{},
        inserted_at: now
      }

      event_attrs = maybe_add_hash(events, event_attrs, parent_id)

      with {:ok, _event} <- repo.insert(events.changeset(event_attrs)) do
        repo.delete(record)
      end
    end)
  end

  @doc """
  Create a savepoint event capturing the current state of a record.

  Returns `{:ok, struct}` on success or raises on failure.

  Savepoints store the complete state of a record at a point in time, allowing
  event replay to start from the savepoint instead of replaying all events
  from the beginning. This is useful for records with long event histories.

  The schema must implement the `savepoint/2` callback to define how the
  current state is converted to an attrs map:

      @behaviour Spector.Evented

      @impl true
      def savepoint(record, _version) do
        %{name: record.name, email: record.email}
      end

  ## Forms

  There are two ways to create a savepoint:

  ### From a record (`savepoint/1`)

  Pass the record directly. This verifies that the record matches the current
  state in the event log (replayed events must produce the same field values).
  This guards against creating savepoints from stale records:

      {:ok, user} = Spector.savepoint(user)

  If the record is stale (e.g., another process updated it), this raises an error.

  ### From schema and ID (`savepoint/2`)

  Pass the schema module and record ID. This replays events to determine
  current state without verification:

      {:ok, user} = Spector.savepoint(MyApp.User, user_id)

  Use this form when you don't have the record in memory or don't need
  stale record detection.
  """
  def savepoint(record) when is_struct(record), do: do_savepoint(record.__struct__, nil, record)
  def savepoint(schema, id) when is_atom(schema), do: do_savepoint(schema, id, nil)

  @spec do_savepoint(module(), Ecto.UUID.t() | nil, evented_struct() | nil) ::
          {:ok, evented_struct()} | {:error, term()}
  defp do_savepoint(schema, id, reference_record) do
    if not function_exported?(schema, :savepoint, 2),
      do: raise("Schema #{inspect(schema)} must implement savepoint/2 callback")

    events_module = schema.__spector__(:events)
    version = schema.__spector__(:version)
    [id_field] = schema.__schema__(:primary_key)

    id = if reference_record, do: Map.fetch!(reference_record, id_field), else: id

    repo = get_repo(schema, events_module)

    repo.transact(fn ->
      # Replay to get current state
      record =
        schema
        |> Query.recent_events(id)
        |> repo.all()
        |> roll_forward()
        |> Changeset.apply_changes()
        |> verify_record!(reference_record)

      event_id = UUIDv7.generate()
      now = DateTime.utc_now()

      payload =
        record
        |> schema.savepoint(version)
        |> Map.put(:__version__, version)
        |> Map.put(:__event_id__, event_id)

      event_attrs = %{
        id: event_id,
        parent_id: id,
        schema: schema,
        action: :savepoint,
        payload: payload,
        inserted_at: now
      }

      events_module.changeset(event_attrs)
      |> repo.insert!()

      {:ok, record}
    end)
  end

  defp verify_record!(record, nil), do: record

  defp verify_record!(record, reference_record) do
    fields = record.__struct__.__schema__(:fields)

    if Map.take(record, fields) != Map.take(reference_record, fields) do
      raise "Savepoint record does not match reference record"
    end

    record
  end

  @doc """
  Execute an action on a record, creating an event in the event log.

  This is the general-purpose function for applying any action to a record,
  including custom actions defined in the schema's `:actions` option.

  Returns `{:ok, struct}` on success or `{:error, changeset}` on failure.

  The function rolls forward from the event log to reconstruct current state,
  applies the action through the schema's `changeset/2` function, and records
  the new event.

  ## Example

      # Using a custom :archive action
      {:ok, item} = Spector.execute(item, :archive, %{archived_at: DateTime.utc_now()})

      # The :update action (same as Spector.update/2)
      {:ok, user} = Spector.execute(user, :update, %{name: "New Name"})
  """
  @spec execute(evented_struct(), action(), attrs()) ::
          {:ok, evented_struct()} | {:error, Ecto.Changeset.t()}
  def execute(record, action, attrs) do
    schema = record.__struct__
    events_module = schema.__spector__(:events)
    repo = get_repo(schema, events_module)
    [pk_field] = schema.__schema__(:primary_key)
    parent_id = Map.fetch!(record, pk_field)
    version = schema.__spector__(:version)
    id = UUIDv7.generate()
    # TODO: in the future we might want to support alternative timestamp field names
    now = DateTime.utc_now()

    attrs =
      attrs
      |> Map.put(:__version__, version)
      |> Map.put(:__event_id__, id)
      |> Map.put(:updated_at, now)

    # Roll forward from events to get current state
    previous_events = recent_events(schema, parent_id)

    changeset =
      previous_events
      |> roll_forward()
      |> or_crash()
      |> _set_changeset_action(action)
      |> schema.changeset(attrs)

    if changeset.valid? do
      repo.transact(fn ->
        event_attrs = %{
          id: id,
          parent_id: parent_id,
          schema: schema,
          action: action,
          payload: attrs,
          inserted_at: now
        }

        event_attrs = maybe_add_hash(events_module, event_attrs, parent_id)

        event_attrs
        |> events_module.changeset()
        |> maybe_prepare_event(previous_events, attrs)
        |> repo.insert()
        |> case do
          {:ok, _event} ->
            do_update(changeset, repo, schema)

          {:error, event_changeset} ->
            {:error, event_changeset}
        end
      end)
    else
      {:error, changeset}
    end
  end

  @doc """
  Assigns the current event ID to a changeset field.

  When Spector calls your `changeset/2` function, it includes an `:__event_id__`
  key in the attrs map. This function extracts that ID and assigns it to
  the specified field in your changeset.

  This is useful for embedded schemas and `{:array, :map}` rollup records
  where you want each record to have a unique ID that matches its creation event.

  ## Parameters

    - `changeset` - The changeset to modify
    - `attrs` - The attrs map passed to `changeset/2` (contains `:__event_id__`)
    - `field` - The field to assign the event ID to (default: `:id`)

  ## Example

      def changeset(message, attrs) do
        message
        |> Ecto.Changeset.cast(attrs, [:content, :role])
        |> Spector.changeset_put_event_id(attrs)
        |> Ecto.Changeset.validate_required([:id, :content, :role])
      end

  """
  @spec changeset_put_event_id(Ecto.Changeset.t(), attrs()) :: Ecto.Changeset.t()
  @spec changeset_put_event_id(Ecto.Changeset.t(), attrs(), atom()) :: Ecto.Changeset.t()
  def changeset_put_event_id(changeset, attrs, field \\ :id) do
    case attrs do
      %{"__event_id__" => event_id} ->
        Changeset.put_change(changeset, field, event_id)

      %{__event_id__: event_id} ->
        Changeset.put_change(changeset, field, event_id)

      _ ->
        changeset
    end
  end

  @doc """
  Fetches a field from attrs, checking both atom and string keys.

  Returns `{:ok, value}` if the key exists, or `:error` if not found.

  This is useful in changesets where attrs may come with string keys (from JSON)
  or atom keys (from internal calls).

  ## Example

      def changeset(record, attrs) do
        case Spector.fetch_attr(attrs, :parent_id) do
          {:ok, parent_id} -> # handle parent_id
          :error -> # no parent_id provided
        end
      end
  """
  @spec fetch_attr(attrs(), atom()) :: {:ok, any()} | :error
  def fetch_attr(attrs, key) when is_atom(key) do
    case attrs do
      %{^key => value} -> {:ok, value}
      _ -> Map.fetch(attrs, Atom.to_string(key))
    end
  end

  @doc """
  Fetches a field from attrs, checking both atom and string keys.

  Returns the value if the key exists, or raises `KeyError` if not found.

  ## Example

      def changeset(record, attrs) do
        parent_id = Spector.fetch_attr!(attrs, :parent_id)
        # use parent_id
      end
  """
  @spec fetch_attr!(attrs(), atom()) :: any()
  def fetch_attr!(attrs, key) when is_atom(key) do
    case fetch_attr(attrs, key) do
      {:ok, value} -> value
      :error -> raise KeyError, key: key, term: attrs
    end
  end

  @doc """
  Gets a field from attrs, checking both atom and string keys.

  Returns the value if the key exists, or `default` if not found.

  ## Example

      def changeset(record, attrs) do
        parent_id = Spector.get_attr(attrs, :parent_id, nil)
        # use parent_id, which may be nil
      end
  """
  @spec get_attr(attrs(), atom()) :: any()
  @spec get_attr(attrs(), atom(), any()) :: any()
  def get_attr(attrs, key, default \\ nil) when is_atom(key) do
    case fetch_attr(attrs, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  defp maybe_add_hash(events, event_attrs, parent_id) do
    if events.__spector__(:hashed) do
      lock_table(events, parent_id)
      prev_hash = get_last_hash(events, parent_id)
      hash = compute_hash(prev_hash, event_attrs)
      Map.put(event_attrs, :hash, hash)
    else
      event_attrs
    end
  end

  defp maybe_prepare_event(event_changeset, previous_events, attrs) do
    schema = Changeset.fetch_field!(event_changeset, :schema)

    if function_exported?(schema, :prepare_event, 3) do
      schema.prepare_event(event_changeset, previous_events, attrs)
    else
      event_changeset
    end
  end

  defp maybe_prepare_materialization(changeset, schema) do
    if function_exported?(schema, :prepare_materialization, 1) do
      schema.prepare_materialization(changeset)
    else
      changeset
    end
  end

  defp lock_table(events, parent_id) do
    repo = events.__spector__(:repo)

    table =
      if shard_fn = events.__spector__(:shard) do
        apply(events, shard_fn, [parent_id])
      else
        events.__schema__(:source)
      end

    SQL.query!(repo, "LOCK TABLE #{table} IN EXCLUSIVE MODE")
  end

  defp get_last_hash(events, parent_id) do
    repo = events.__spector__(:repo)

    events
    |> Query.last_hash(parent_id)
    |> repo.one()
  end

  @doc false
  def _json_encode!(data), do: JSON.encode!(data, &spector_encoder/2)

  defp spector_encoder(map, encoder) when is_map(map) and not is_struct(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.sort()
    |> :json.encode_key_value_list(encoder)
  end

  defp spector_encoder(value, encoder), do: JSON.protocol_encode(value, encoder)

  defp compute_hash(prev_hash, event_attrs) do
    prev_hash_hex = if prev_hash, do: "#{Base.encode16(prev_hash, case: :lower)}:", else: ""
    payload_json = _json_encode!(event_attrs.payload)
    data = "#{prev_hash_hex}#{event_attrs.schema}.#{event_attrs.action}#{payload_json}"
    :crypto.hash(:sha256, data)
  end

  # roll_forward should ONLY be called when all of the events belong to the same schema
  # and all events should have the same parent_id.
  defp roll_forward([]), do: nil

  defp roll_forward([%{schema: schema, parent_id: parent_id} | _] = events) do
    [pk_field] = schema.__schema__(:primary_key)

    # If schema implements savepoint/1, start from the most recent savepoint
    initial =
      schema
      |> struct!([{pk_field, parent_id}])
      |> Changeset.change()

    Enum.reduce(events, initial, &_roll_one(&1, &2, schema))
  end

  @doc false
  def _set_changeset_action(changeset, action) do
    Map.replace!(changeset, :action, action)
  end

  @doc false
  def _roll_one(%{action: :savepoint} = event, _changeset, schema) do
    [pk_field] = schema.__schema__(:primary_key)

    schema
    |> struct!([{pk_field, event.parent_id}])
    |> Changeset.change()
    |> _set_changeset_action(:savepoint)
    |> schema.changeset(Map.put(event.payload, "__event_id__", event.id))
  end

  def _roll_one(%{action: :delete}, _changeset, _schema), do: nil

  def _roll_one(event, changeset, schema) do
    changeset
    |> _set_changeset_action(event.action)
    |> schema.changeset(Map.put(event.payload, "__event_id__", event.id))
  end
end
