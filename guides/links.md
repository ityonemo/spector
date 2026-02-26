# Event Links Guide

This guide shows how to use Spector's event links feature to create many-to-many relationships between events. Links are useful for tracking ancestry, references, dependencies, and other relationships.

## Overview

Event links allow events to reference other events in the same event log. Common use cases include:

- **Ancestry tracking**: Building tree-structured data like conversation branches
- **Edit history**: Linking edited versions to their originals
- **References**: Connecting related events within the same record
- **Dependencies**: Tracking which events depend on others

## Setup

This guide demonstrates typed link tables, which add a `type` integer column to categorize different relationship types.

### Typed Link Schema

Define an Ecto schema to manage the type values:

```elixir
defmodule MyApp.TypedEventLink do
  use Ecto.Schema
  alias Ecto.Changeset

  @type link_type :: :parent | :sibling | :reference | :supersedes

  @primary_key false
  schema "typed_event_links" do
    field :event_id, :binary_id
    field :linked_id, :binary_id
    # Use explicit integer assignments for forward compatibility.
    # This ensures existing data remains valid if you rename a type.
    field :type, Ecto.Enum, values: [parent: 0, sibling: 1, reference: 2, supersedes: 3]
  end

  def changeset(link \\ %__MODULE__{}, attrs) do
    link
    |> Changeset.cast(attrs, [:event_id, :linked_id, :type])
    |> Changeset.validate_required([:event_id, :linked_id, :type])
  end

  @doc "Create a link struct for insertion"
  def new(event_id, linked_id, type) do
    %__MODULE__{event_id: event_id, linked_id: linked_id, type: type}
  end
end
```

### Document Schema with prepare_event

The `prepare_event/3` callback lets you populate link associations before an event is inserted into the event table:

```elixir
defmodule MyApp.TypedDoc do
  use Spector.Evented, events: MyApp.TypedLinkEvents, actions: [:revise]
  use Ecto.Schema
  alias Ecto.Changeset

  @behaviour Spector.Evented

  @primary_key {:id, :binary_id, autogenerate: false}
  embedded_schema do
    field :content, :string
    field :version, :integer, default: 1
  end

  @impl true
  def prepare_event(event_changeset, previous_events, attrs) do
    case Spector.get_attr(attrs, :supersedes) do
      nil ->
        event_changeset

      superseded_id ->
        # Find the superseded event
        superseded_event = Enum.find(previous_events, &(&1.id == superseded_id))

        if superseded_event do
          # Create a typed link marking this event as superseding another
          link = MyApp.TypedEventLink.new(
            Changeset.get_field(event_changeset, :id),
            superseded_id,
            :supersedes
          )
          Changeset.put_assoc(event_changeset, :links, [link])
        else
          event_changeset
        end
    end
  end

  def changeset(changeset, attrs) when changeset.action == :revise do
    current_version = Changeset.get_field(changeset, :version, 0)

    changeset
    |> Changeset.cast(attrs, [:content])
    |> Changeset.put_change(:version, current_version + 1)
    |> Changeset.validate_required([:content])
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:content])
    |> Changeset.validate_required([:content])
  end

  import Ecto.Query

  def get_superseding_events(event_id) do
    from(link in MyApp.TypedEventLink,
      where: link.linked_id == ^event_id and link.type == :supersedes,
      join: e in MyApp.TypedLinkEvents,
      on: e.id == link.event_id,
      select: e
    )
    |> MyApp.Repo.all()
  end

  def get_superseded_by(event_id) do
    from(link in MyApp.TypedEventLink,
      where: link.event_id == ^event_id and link.type == :supersedes,
      join: e in MyApp.TypedLinkEvents,
      on: e.id == link.linked_id,
      select: e
    )
    |> MyApp.Repo.all()
  end
end
```

### Events Module

```elixir
defmodule MyApp.TypedLinkEvents do
  use Spector.Events,
    table: "typed_link_events",
    links: [links: {MyApp.TypedEventLink, :linked_id}],
    schemas: [MyApp.TypedDoc],
    repo: MyApp.Repo
end
```

## Usage

### Creating a Document

```elixir
{:ok, doc} = Spector.insert(MyApp.TypedDoc, %{content: "First draft"})
assert doc.content == "First draft"
assert doc.version == 1
```

### Revising with a Supersedes Link

When revising, pass the `:supersedes` attribute to create a link to the original event:

```elixir
# Get the original event ID (same as doc.id for insert events)
original_event_id = doc.id

{:ok, revised} = Spector.execute(doc, :revise, %{
  content: "Second draft",
  supersedes: original_event_id
})
assert revised.content == "Second draft"
assert revised.version == 2
```

### Querying Links

Find which events supersede a given event:

```elixir
superseding = MyApp.TypedDoc.get_superseding_events(original_event_id)
assert length(superseding) == 1
assert hd(superseding).action == :revise
```

Find what an event supersedes:

```elixir
import Ecto.Query

# Get the revise event ID from the events table
[revise_event] = MyApp.Repo.all(
  from e in MyApp.TypedLinkEvents,
    where: e.parent_id == ^doc.id and e.action == :revise
)

superseded = MyApp.TypedDoc.get_superseded_by(revise_event.id)
assert length(superseded) == 1
assert hd(superseded).id == original_event_id
```

### Preloading Links

Events with links can be preloaded through the association:

```elixir
events = MyApp.Repo.all(MyApp.TypedLinkEvents)
  |> MyApp.Repo.preload(:links)

# The revise event should have one link
revise_event = Enum.find(events, &(&1.action == :revise))
assert length(revise_event.links) == 1
assert hd(revise_event.links).type == :supersedes
```

## Link Types Reference

Common relationship types and when to use them:

| Type | Use Case | Example |
|------|----------|---------|
| `:ancestor` | Tree-structured history | Conversation branches, version trees |
| `:parent` | Hierarchical relationships | Comment replies, nested items |
| `:sibling` | Peer relationships | Related documents, alternatives |
| `:reference` | Loose connections | Citations, mentions |
| `:supersedes` | Replacement relationships | Edits, corrections, updates |
| `:depends_on` | Dependency tracking | Build steps, prerequisites |

## Best Practices

1. **Links must connect events with the same parent_id**: Links are designed for relating events within the same record (e.g., linking messages in the same conversation, or revisions of the same document). Do not use links to connect events across different records.

2. **Choose between typed and separate link tables**: Separate link tables (one per relationship type) have a unique index on `(event_id, foreign_key)`. Typed link tables have a unique index on `(event_id, foreign_key, type)`, allowing the same pair of events to have multiple relationships of different types. Typed tables are particularly useful for heterogeneous event tables where you want flexible relationship types without creating a new link table for each one.

3. **Define clear type semantics**: Document what each type means in your domain and enforce it in `prepare_event/3`.

4. **Index appropriately**: The migration creates indexes on `event_id` and the foreign key. For typed tables, consider adding a composite index if you frequently query by type.

5. **Keep links immutable**: Links are created when events are inserted and shouldn't be modified afterward. This preserves the integrity of your event log.

6. **Use Ecto.Enum for types**: This provides compile-time checking and clear documentation of valid types.

## See Also

- [Building an AI Chat Log](AI_chat.md) - Uses links for conversation branching
- [Building a Basic Chat](basic_chat.md) - Uses links for edit history
