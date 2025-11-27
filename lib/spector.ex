defmodule Spector do
  @moduledoc """
  CQRS-style event sourcing for Ecto schemas.

  Spector provides event sourcing capabilities for Ecto schemas, recording all
  changes as immutable events in a separate event log table. This enables full
  audit trails, temporal queries, and the ability to replay history.

  ## Setup

  1. Define your event log table using `Spector.Events`:

  ```elixir
  defmodule MyApp.Events do
    use Spector.Events,
      table: "events",
      schemas: [MyApp.User, MyApp.Post],
      repo: MyApp.Repo
  end
  ```

  2. Mark your schemas as evented using `Spector.Evented`:

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

  3. Create a migration for the events table using `Spector.Migration`:

  ```elixir
  defmodule MyApp.Repo.Migrations.CreateEvents do
    use Ecto.Migration

    def up, do: Spector.Migration.up(table: "events")
    def down, do: Spector.Migration.down(table: "events")
  end
  ```

  ## Usage

  Use the Spector functions instead of `Repo.insert/2`, `Repo.update/2`, etc.:

  ```elixir
  # Insert a new record
  {:ok, user} = Spector.insert(MyApp.User, %{name: "Alice", email: "alice@example.com"})

  # Update an existing record
  {:ok, user} = Spector.update(user, %{name: "Alice Smith"})

  # Delete a record
  {:ok, user} = Spector.delete(user)
  ```

  Each operation creates an event in the event log, providing a complete history
  of all changes to the record.

  ## Custom Actions

  Beyond insert/update/delete, you can define custom actions for domain-specific
  operations. See `Spector.Evented` for details.

  ```elixir
  {:ok, item} = Spector.execute(item, :archive, %{archived_at: DateTime.utc_now()})
  ```

  ## Roll Forward

  When updating records, Spector "rolls forward" by replaying all stored events
  through your schema's `changeset/2` function. This means:

  - Your changeset function handles both new operations AND historical replay
  - Schema migrations happen automatically during replay (using version guards)
  - The current state is always reconstructed from the event log
  - Stale in-memory objects are never a problem
  """

  alias Ecto.Changeset

  defp get_repo(schema, events) do
    schema.__spector__(:repo) || events.__spector__(:repo)
  end

  def insert(schema, attrs) do
    events = schema.__spector__(:events)
    repo = get_repo(schema, events)
    version = schema.__spector__(:version)
    attrs = Map.put(attrs, :__version__, version)

    changeset =
      schema
      |> struct!()
      |> Changeset.change()
      |> Map.replace!(:action, :insert)
      |> schema.changeset(attrs)

    if changeset.valid? do
      repo.transact(fn ->
        id = UUIDv7.generate()

        event_attrs = %{id: id, parent_id: id, schema: schema, action: :insert, payload: attrs}
        event_attrs = maybe_add_hash(events, event_attrs, id)
        object_changeset = Changeset.put_change(changeset, :id, id)

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
      repo.insert(changeset)
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

  def update(object, attrs) do
    execute(object, :update, attrs)
  end

  def get(schema, parent_id) do
    events_module = schema.__spector__(:events)

    parent_id
    |> events_module.list_by_parent_id(schema)
    |> roll_forward()
    |> and_apply(:get)
  end

  defp and_apply(nil, _action), do: nil
  defp and_apply(changeset, action), do: Changeset.apply_action!(changeset, action)

  defp or_crash(nil), do: raise("No such record")
  defp or_crash(changeset), do: changeset

  def delete(object) do
    schema = object.__struct__
    events = schema.__spector__(:events)
    repo = get_repo(schema, events)
    parent_id = object.id

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

  def execute(object, action, attrs) do
    schema = object.__struct__
    events_module = schema.__spector__(:events)
    repo = get_repo(schema, events_module)
    parent_id = object.id
    version = schema.__spector__(:version)
    attrs = Map.put(attrs, :__version__, version)

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
        id = UUIDv7.generate()

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
    schema
    |> struct!(id: parent_id)
    |> Changeset.change()
    |> then(
      &Enum.reduce(events, &1, fn %{parent_id: ^parent_id} = event, changeset ->
        changeset
        |> Map.replace!(:action, event.action)
        |> schema.changeset(event.payload)
      end)
    )
  end
end
