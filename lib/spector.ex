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
  - Stale in-memory objects are never a problem

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
      Ecto.Changeset.change(changeset, archived_at: attrs[:archived_at])
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
      attrs = Map.put(attrs, "name", attrs["title"])
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

  alias Ecto.Changeset

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

    attrs =
      attrs
      |> Map.put(:__version__, version)
      |> Map.put(:__event_id__, id)

    changeset =
      schema
      |> struct!()
      |> Changeset.change()
      |> Map.replace!(:action, action)
      |> schema.changeset(attrs)

    if changeset.valid? do
      repo.transact(fn ->
        event_attrs = %{id: id, parent_id: id, schema: schema, action: action, payload: attrs}
        event_attrs = maybe_add_hash(events, event_attrs, id)
        [pk_field] = schema.__schema__(:primary_key)
        object_changeset = Changeset.put_change(changeset, pk_field, id)

        event_attrs
        |> events.changeset()
        |> maybe_prepare_event([], attrs)
        |> repo.insert()
        |> case do
          {:ok, _event} ->
            do_insert(object_changeset, repo, schema)

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
      insert_changeset = Map.replace!(changeset, :action, :insert)
      repo.insert(insert_changeset)
    else
      Changeset.apply_action(changeset, :insert)
    end
  end

  defp do_update(changeset, repo, schema) do
    if schema.__schema__(:source) do
      update_changeset = Map.replace!(changeset, :action, :update)
      repo.update(update_changeset)
    else
      Changeset.apply_action(changeset, :update)
    end
  end

  @doc """
  Update an existing record, creating an event in the event log.

  This is a convenience function that calls `execute(object, :update, attrs)`.

  Returns `{:ok, struct}` on success or `{:error, changeset}` on failure.

  ## Example

      {:ok, user} = Spector.update(user, %{name: "Alice Smith"})
  """
  @spec update(evented_struct(), attrs()) ::
          {:ok, evented_struct()} | {:error, Ecto.Changeset.t()}
  def update(object, attrs) do
    execute(object, :update, attrs)
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
    events_module = schema.__spector__(:events)

    parent_id
    |> events_module.list_by_parent_id(schema)
    |> roll_forward()
    |> and_apply(:get)
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
    import Ecto.Query

    action = Keyword.get(opts, :action, :insert)
    attr_fn = Keyword.get(opts, :attr_fn, &from_record/1)
    transfer_fn = Keyword.get(opts, :transfer, fn _, _ -> :ok end)

    events = schema.__spector__(:events)
    repo = get_repo(schema, events)

    repo.transact(fn ->
      # Only select records that don't already have events
      events_table = events.__schema__(:source)
      [pk_field] = schema.__schema__(:primary_key)

      query =
        from(r in schema,
          left_join: e in ^{events_table, events},
          on: e.parent_id == field(r, ^pk_field) and e.schema == ^schema,
          where: is_nil(e.id)
        )

      new_records =
        repo.all(query)
        |> Enum.map(fn record ->
          attrs = attr_fn.(record)

          case insert(schema, attrs, action) do
            {:ok, new_record} ->
              transfer_fn.(record, new_record)
              repo.delete!(record)
              new_record

            {:error, changeset} ->
              raise "Failed to bringup record #{inspect(record)}: #{inspect(changeset)}"
          end
        end)

      {:ok, new_records}
    end)
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
  def delete(object) do
    schema = object.__struct__
    events = schema.__spector__(:events)
    repo = get_repo(schema, events)
    [pk_field] = schema.__schema__(:primary_key)
    parent_id = Map.fetch!(object, pk_field)

    repo.transact(fn ->
      id = UUIDv7.generate()

      event_attrs = %{id: id, parent_id: parent_id, schema: schema, action: :delete, payload: %{}}
      event_attrs = maybe_add_hash(events, event_attrs, parent_id)

      with {:ok, _event} <- repo.insert(events.changeset(event_attrs)),
           {:ok, deleted} <- repo.delete(object) do
        {:ok, deleted}
      end
    end)
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
  def execute(object, action, attrs) do
    schema = object.__struct__
    events_module = schema.__spector__(:events)
    repo = get_repo(schema, events_module)
    [pk_field] = schema.__schema__(:primary_key)
    parent_id = Map.fetch!(object, pk_field)
    version = schema.__spector__(:version)
    id = UUIDv7.generate()

    attrs =
      attrs
      |> Map.put(:__version__, version)
      |> Map.put(:__event_id__, id)

    # Roll forward from events to get current state
    previous_events = events_module.list_by_parent_id(parent_id, schema)

    changeset =
      previous_events
      |> roll_forward()
      |> or_crash()
      |> Map.replace!(:action, action)
      |> schema.changeset(attrs)

    if changeset.valid? do
      repo.transact(fn ->
        event_attrs = %{
          id: id,
          parent_id: parent_id,
          schema: schema,
          action: action,
          payload: attrs
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

  @doc false
  # this is an internal utility function.
  # Assigns the event ID from attrs to a field on the changeset.
  #
  # If no `:__event_id__` is present in attrs, the changeset is returned unchanged.
  #
  # ## Parameters
  #
  #   - `changeset` - The Ecto changeset to modify
  #   - `attrs` - The attrs map passed to `changeset/2` (contains `:__event_id__`)
  #   - `field` - The field to assign the event ID to (default: `:id`)
  #
  # ## Example
  #
  #     def changeset(message, attrs) do
  #       message
  #       |> Ecto.Changeset.cast(attrs, [:content, :role])
  #       |> Spector.changeset_put_event_id(attrs)
  #       |> Ecto.Changeset.validate_required([:id, :content, :role])
  #     end
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

  defp lock_table(events, parent_id) do
    repo = events.__spector__(:repo)

    table =
      if shard_fn = events.__spector__(:shard) do
        apply(events, shard_fn, [parent_id])
      else
        events.__schema__(:source)
      end

    Ecto.Adapters.SQL.query!(repo, "LOCK TABLE #{table} IN EXCLUSIVE MODE")
  end

  defp get_last_hash(events, parent_id) do
    import Ecto.Query
    repo = events.__spector__(:repo)
    table = events.table_for(parent_id)

    case repo.one(from(e in {table, events}, order_by: [desc: e.id], limit: 1, select: e.hash)) do
      nil -> nil
      hash -> hash
    end
  end

  @json_library if Code.ensure_loaded?(Jason), do: Jason, else: JSON

  defp compute_hash(prev_hash, event_attrs) do
    prev_hash_hex = if prev_hash, do: "#{Base.encode16(prev_hash, case: :lower)}:", else: ""
    payload_json = @json_library.encode!(event_attrs.payload)
    data = "#{prev_hash_hex}#{event_attrs.schema}.#{event_attrs.action}#{payload_json}"
    :crypto.hash(:sha256, data)
  end

  # roll_forward should ONLY be called when all of the events belong to the same schema
  # and all events should have the same parent_id.
  defp roll_forward([]), do: nil

  defp roll_forward(events = [%{schema: schema, parent_id: parent_id} | _]) do
    [pk_field] = schema.__schema__(:primary_key)

    schema
    |> struct!([{pk_field, parent_id}])
    |> Changeset.change()
    |> then(
      &Enum.reduce(events, &1, fn %{parent_id: ^parent_id} = event, changeset ->
        changeset
        |> Map.replace!(:action, event.action)
        |> schema.changeset(Map.put(event.payload, "__event_id__", event.id))
      end)
    )
  end
end
