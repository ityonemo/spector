defmodule Spector.Query do
  @moduledoc false

  import Ecto.Query

  @doc """
  Returns all events for a record from the beginning.

  Events are returned in insertion order.

  ## Example

      events = Spector.Query.all_events(MyApp.User, user_id)
  """
  @spec all_events(module(), Ecto.UUID.t()) :: Ecto.Query.t()
  def all_events(schema, parent_id) do
    events_module = schema.__spector__(:events)
    table = events_module.table_for(parent_id)

    from(e in {table, events_module},
      where: e.parent_id == ^parent_id and e.schema == ^schema,
      order_by: [asc: e.inserted_at]
    )
  end

  @doc """
  Returns a query for events starting from the most recent savepoint.

  If no savepoint exists, returns all events from the beginning.
  The savepoint event itself is included as the first element.

  Events are returned in insertion order.

  ## Example

      events = Repo.all(Spector.Query.recent_events(MyApp.User, user_id))
  """
  @spec recent_events(module(), Ecto.UUID.t()) :: Ecto.Query.t()
  def recent_events(schema, parent_id) do
    if function_exported?(schema, :savepoint, 2) do
      events_module = schema.__spector__(:events)
      table = events_module.table_for(parent_id)

      # Subquery to find the most recent savepoint's inserted_at
      savepoint_subquery =
        from(e in {table, events_module},
          where: e.parent_id == ^parent_id and e.schema == ^schema and e.action == :savepoint,
          order_by: [desc: e.inserted_at],
          limit: 1,
          select: e.inserted_at
        )

      from(e in {table, events_module},
        where: e.parent_id == ^parent_id and e.schema == ^schema,
        where: e.inserted_at >= coalesce(subquery(savepoint_subquery), e.inserted_at),
        order_by: [asc: e.inserted_at]
      )
    else
      all_events(schema, parent_id)
    end
  end

  @doc """
  Returns a query for all record IDs (parent_ids) for a schema.

  Returns only the IDs, not full event structs. Finds records by looking for
  insert events where id == parent_id.

  ## Example

      record_ids = Repo.all(Spector.Query.all_record_ids(MyApp.User))
  """
  @spec all_record_ids(module()) :: Ecto.Query.t()
  def all_record_ids(schema) do
    events_module = schema.__spector__(:events)
    table = events_module.__schema__(:source)

    from(e in {table, events_module},
      where: e.schema == ^schema and e.id == e.parent_id,
      select: e.parent_id
    )
  end

  @doc """
  Returns a query for all events up to and including a given event.

  Events are returned in insertion order. The specified event is included
  as the last element in the result.

  ## Example

      events = Repo.all(Spector.Query.previous_events(MyApp.Events, record_id, event_id))
  """
  @spec previous_events(module(), Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def previous_events(events_module, parent_id, event_id) do
    table = events_module.table_for(parent_id)

    target_inserted_at =
      from(t in {table, events_module},
        where: t.id == ^event_id,
        select: t.inserted_at
      )

    from(e in {table, events_module},
      where: e.parent_id == ^parent_id and e.inserted_at <= subquery(target_inserted_at),
      order_by: [asc: e.inserted_at]
    )
  end

  @doc """
  Returns a query for the last hash in a hashed events table.

  Used for hash chain integrity to get the previous hash when inserting a new event.

  ## Example

      last_hash = Repo.one(Spector.Query.last_hash(MyApp.Events, parent_id))
  """
  @spec last_hash(module(), Ecto.UUID.t()) :: Ecto.Query.t()
  def last_hash(events_module, parent_id) do
    table = events_module.table_for(parent_id)

    from(e in {table, events_module},
      order_by: [desc: e.inserted_at],
      limit: 1,
      select: e.hash
    )
  end

  @doc """
  Returns a query for all events in insertion order.

  ## Example

      events = Repo.all(Spector.Query.all_ordered(MyApp.Events))
  """
  @spec all_ordered(module()) :: Ecto.Query.t()
  def all_ordered(events_module) do
    table = events_module.__schema__(:source)

    from(e in {table, events_module},
      order_by: [asc: e.inserted_at]
    )
  end

  @doc """
  Returns a query for records without events (for bringup).

  Finds records in the schema's table that don't have any events in the event log.

  ## Example

      records = Repo.all(Spector.Query.records_without_events(MyApp.User))
  """
  @spec records_without_events(module()) :: Ecto.Query.t()
  def records_without_events(schema) do
    events_module = schema.__spector__(:events)
    events_table = events_module.__schema__(:source)
    [pk_field] = schema.__schema__(:primary_key)

    from(r in schema,
      left_join: e in ^{events_table, events_module},
      on: e.parent_id == field(r, ^pk_field) and e.schema == ^schema,
      where: is_nil(e.id)
    )
  end
end
