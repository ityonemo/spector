# Spector

CQRS-style event sourcing for Ecto schemas.

Spector records all changes to your Ecto schemas as events in a separate event log table. This enables full audit trails, temporal queries, and the ability to replay history. For tamper-evident logs, enable optional hash chain integrity.

## Installation

Add `spector` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:spector, "~> 0.4.0"}
  ]
end
```

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
# For the events table
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

When you update or execute an action on a record, Spector "rolls forward" by replaying all stored events through your schema's `changeset/2` function. This means:

- Your changeset function handles both new operations AND historical replay
- Schema migrations happen automatically during replay (using version guards)
- The current state is always reconstructed from the event log
- Stale in-memory objects are never a problem

This design lets you evolve your schema over time while maintaining full compatibility with historical events.

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

### Chat and Conversation Logs

Spector includes features specifically designed for chat-log style applications:

- **Event links** for tracking message ancestry and edit history
- **Embedded schemas** for state reconstructed purely from events

See the [AI Chat Guide](guides/AI_chat.md) for conversation branching and the [Basic Chat Guide](guides/basic_chat.md) for edit history tracking.

## Database Support

Spector works with any database supported by Ecto for basic functionality.

**Note:** Hashed event tables (`hashed: true`) currently require PostgreSQL. The hash chain integrity feature uses `LOCK TABLE ... IN EXCLUSIVE MODE` which is PostgreSQL-specific.

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/spector).

## License

MIT License. See LICENSE for details.
