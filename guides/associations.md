# Associations Guide

This guide covers how to handle Ecto associations with Spector event-sourced schemas. The key insight is that event sourcing stores changes to individual records, so associations work differently than in traditional Ecto applications.

## Overview

Event sourcing captures changes as immutable events. When dealing with associations, you need to consider:

1. **Where is the foreign key stored?** The schema that stores the foreign key is straightforward to event-source.
2. **Can the relationship be rebuilt from events?** If replaying events can't reconstruct the relationship, you need a different approach.
3. **Who owns the relationship data?** This determines which schema's events capture changes.

## belongs_to (Straightforward)

`belongs_to` associations are the simplest case because the foreign key is stored directly in the schema that declares the association.

### Schema Definition

```elixir
defmodule MyApp.Item do
  use Spector.Evented, events: MyApp.Events
  use Ecto.Schema
  alias Ecto.Changeset

  schema "items" do
    field :title, :string
    belongs_to :workspace, MyApp.Workspace
    timestamps()
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:title, :workspace_id])
    |> Changeset.validate_required([:title, :workspace_id])
    |> Changeset.foreign_key_constraint(:workspace_id)
  end
end
```

### Usage

```elixir
# Create an item belonging to a workspace
{:ok, item} = Spector.insert(MyApp.Item, %{
  title: "New Task",
  workspace_id: workspace.id
})

# The workspace_id is stored in the event payload
# Replaying events correctly rebuilds the association
```

The foreign key (`workspace_id`) is cast like any other field. Events capture changes to this field, and replaying events correctly reconstructs which workspace the item belongs to.

## Why Not has_one

`has_one` associations are problematic with event sourcing and are generally not recommended.

### The Problem

With `has_one`, the "owned" side stores the foreign key, not the owner:

```elixir
defmodule MyApp.User do
  has_one :profile, MyApp.Profile  # Profile stores user_id
end

defmodule MyApp.Profile do
  belongs_to :user, MyApp.User  # user_id is here
end
```

When you replay events for a User, you only see changes to the User schema. The `user_id` field lives in Profile, so the User's event history knows nothing about whether a Profile exists or which one it points to.

### The Same Problem as has_many

`has_one` has the same conceptual issues as `has_many` - the "many" side stores the foreign key. The only difference is cardinality, which doesn't help with event replay.

### Recommendations

1. **Use belongs_to from the other side**: Query the Profile by `user_id` when you need it
2. **Embed the data**: If the profile is truly owned by the user, consider using an embedded schema or JSON field
3. **Accept the limitation**: Preload the association separately after rebuilding from events

## has_many (Child Stores Parent ID)

`has_many` associations work well when each child is event-sourced independently.

### The Pattern

```elixir
defmodule MyApp.Item do
  use Spector.Evented, events: MyApp.Events
  use Ecto.Schema

  schema "items" do
    field :title, :string
    has_many :comments, MyApp.Comment
    timestamps()
  end
end

defmodule MyApp.Comment do
  use Spector.Evented, events: MyApp.Events
  use Ecto.Schema
  alias Ecto.Changeset

  schema "comments" do
    field :body, :string
    belongs_to :item, MyApp.Item
    timestamps()
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:body, :item_id])
    |> Changeset.validate_required([:body, :item_id])
  end
end
```

### Why This Works

- Each Comment is an independent event-sourced entity
- Comments store their own `item_id`
- Replaying Comment events rebuilds which Item each Comment belongs to
- No special Spector handling needed

### Usage

```elixir
# Create a comment on an item
{:ok, comment} = Spector.insert(MyApp.Comment, %{
  body: "Great work!",
  item_id: item.id
})

# Query comments for an item
comments = MyApp.Repo.all(
  from c in MyApp.Comment,
    where: c.item_id == ^item.id
)

# Or preload through the association
item = MyApp.Repo.preload(item, :comments)
```

## many_to_many (Virtual Field Pattern)

`many_to_many` associations require special handling because the relationship data lives in a join table, not in either schema.

### The Challenge

Events capture changes to schema fields. A join table is a separate entity, so changes to relationships aren't automatically tracked. The solution is to:

1. Store relationship IDs in a virtual field
2. Capture changes to this virtual field in events
3. Sync to the join table using `prepare_materialization/1`

### Schema Definition

```elixir
defmodule MyApp.Item do
  @behaviour Spector.Evented
  use Spector.Evented, events: MyApp.Events
  use Ecto.Schema
  alias Ecto.Changeset

  schema "items" do
    field :title, :string
    field :member_ids, {:array, :binary_id}, virtual: true, default: []
    many_to_many :members, MyApp.Member, join_through: "item_members"
    timestamps()
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:title, :member_ids])
    |> Changeset.validate_required([:title])
  end

  @impl true
  def prepare_materialization(changeset) do
    member_ids = Changeset.get_field(changeset, :member_ids) || []
    members = Enum.map(member_ids, &%MyApp.Member{id: &1})
    Changeset.put_assoc(changeset, :members, members)
  end
end
```

### Join Table Migration (No Schema)

This simple case uses `join_through: "item_members"` with a table name string. There is no Ecto schema for the join table—Ecto manages it directly. This works when you only need to track which records are related, with no additional metadata.

```elixir
defmodule MyApp.Repo.Migrations.CreateItemMembers do
  use Ecto.Migration

  def change do
    create table(:item_members, primary_key: false) do
      add :item_id, references(:items, type: :binary_id, on_delete: :delete_all), null: false
      add :member_id, references(:members, type: :binary_id, on_delete: :delete_all), null: false
    end

    create unique_index(:item_members, [:item_id, :member_id])
    create index(:item_members, [:member_id])
  end
end
```

### How It Works

1. **On insert/update**: The `member_ids` virtual field is cast into the changeset
2. **Event creation**: The `member_ids` array is stored in the event payload
3. **On replay**: Events rebuild the `member_ids` virtual field
4. **Materialization**: `prepare_materialization/1` converts IDs to association structs
5. **Database sync**: `put_assoc` handles the join table insert/update/delete

### Usage

```elixir
# Create with members
{:ok, item} = Spector.insert(MyApp.Item, %{
  title: "Team Task",
  member_ids: [user1.id, user2.id]
})

# Update members
{:ok, item} = Spector.update(%{item | member_ids: [user1.id, user2.id, user3.id]})

# The event log captures:
# 1. Insert event with member_ids: [user1.id, user2.id]
# 2. Update event with member_ids: [user1.id, user2.id, user3.id]
```

### Handling Updates (Preloading)

For updates, you need to preload existing member IDs into the virtual field:

```elixir
def get_item_for_update(id) do
  item = MyApp.Repo.get!(MyApp.Item, id) |> MyApp.Repo.preload(:members)
  %{item | member_ids: Enum.map(item.members, & &1.id)}
end

# Now updates work correctly
item = get_item_for_update(item.id)
{:ok, updated} = Spector.update(%{item | member_ids: new_member_ids})
```

### Join Table with Join Schema (Metadata on Association)

When you need to store metadata on the relationship itself (e.g., role, permissions, timestamps), use a join schema instead of a bare table name.

#### Join Schema Definition

```elixir
defmodule MyApp.ItemMember do
  use Ecto.Schema
  alias Ecto.Changeset

  @primary_key false
  schema "item_members" do
    belongs_to :item, MyApp.Item, primary_key: true
    belongs_to :member, MyApp.Member, primary_key: true
    field :role, :string, default: "viewer"
    field :added_at, :utc_datetime
  end

  def changeset(item_member \\ %__MODULE__{}, attrs) do
    item_member
    |> Changeset.cast(attrs, [:item_id, :member_id, :role, :added_at])
    |> Changeset.validate_required([:item_id, :member_id])
    |> Changeset.validate_inclusion(:role, ["viewer", "editor", "admin"])
  end
end
```

#### Updated Item Schema

Instead of storing just IDs, store maps with the metadata:

```elixir
defmodule MyApp.Item do
  @behaviour Spector.Evented
  use Spector.Evented, events: MyApp.Events
  use Ecto.Schema
  alias Ecto.Changeset

  schema "items" do
    field :title, :string
    # Store member data as maps: %{member_id: uuid, role: "editor"}
    field :member_data, {:array, :map}, virtual: true, default: []
    many_to_many :members, MyApp.Member, join_through: MyApp.ItemMember
    timestamps()
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:title, :member_data])
    |> Changeset.validate_required([:title])
  end

  @impl true
  def prepare_materialization(changeset) do
    member_data = Changeset.get_field(changeset, :member_data) || []
    item_id = Changeset.get_field(changeset, :id)

    item_members = Enum.map(member_data, fn data ->
      %MyApp.ItemMember{
        item_id: item_id,
        member_id: data["member_id"],
        role: data["role"] || "viewer",
        added_at: parse_datetime(data["added_at"])
      }
    end)

    Changeset.put_assoc(changeset, :members, item_members)
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(str) when is_binary(str), do: DateTime.from_iso8601(str) |> elem(1)
  defp parse_datetime(%DateTime{} = dt), do: dt
end
```

#### Usage

```elixir
# Create with members and roles
{:ok, item} = Spector.insert(MyApp.Item, %{
  title: "Team Project",
  member_data: [
    %{member_id: alice.id, role: "admin", added_at: DateTime.utc_now()},
    %{member_id: bob.id, role: "editor", added_at: DateTime.utc_now()}
  ]
})

# Update a member's role
item = get_item_for_update(item.id)
updated_data = Enum.map(item.member_data, fn
  %{"member_id" => id} = data when id == bob.id ->
    Map.put(data, "role", "admin")
  data ->
    data
end)
{:ok, item} = Spector.update(%{item | member_data: updated_data})
```

#### Preloading with Metadata

```elixir
def get_item_for_update(id) do
  item = MyApp.Repo.get!(MyApp.Item, id)
    |> MyApp.Repo.preload(members: :item_member)

  member_data = Enum.map(item.members, fn member ->
    # Access the join record through the preloaded association
    join = Enum.find(member.item_members, &(&1.item_id == item.id))
    %{
      "member_id" => member.id,
      "role" => join.role,
      "added_at" => join.added_at
    }
  end)

  %{item | member_data: member_data}
end
```

The key difference from the simple case: events capture the full relationship data (including metadata), not just IDs. This lets you replay events and reconstruct not just *which* members are associated, but *how* they're associated.

## Polymorphic Relations (Advanced)

For relationships between different entity types, store type+id pairs.

### Schema Definition

```elixir
defmodule MyApp.Item do
  @behaviour Spector.Evented
  use Spector.Evented, events: MyApp.Events, actions: [:add_relation, :remove_relation]
  use Ecto.Schema
  alias Ecto.Changeset

  schema "items" do
    field :title, :string
    # Store relations as maps: %{type: "item", id: uuid}
    field :relations, {:array, :map}, virtual: true, default: []
    timestamps()
  end

  def changeset(changeset, attrs) when changeset.action == :add_relation do
    current = Changeset.get_field(changeset, :relations) || []
    new_relation = %{
      "type" => Spector.get_attr(attrs, :relation_type),
      "id" => Spector.get_attr(attrs, :relation_id)
    }
    Changeset.put_change(changeset, :relations, [new_relation | current])
  end

  def changeset(changeset, attrs) when changeset.action == :remove_relation do
    current = Changeset.get_field(changeset, :relations) || []
    remove_id = Spector.get_attr(attrs, :relation_id)
    filtered = Enum.reject(current, &(&1["id"] == remove_id))
    Changeset.put_change(changeset, :relations, filtered)
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:title, :relations])
    |> Changeset.validate_required([:title])
  end

  @impl true
  def prepare_materialization(changeset) do
    # Sync relations to a join table if needed
    relations = Changeset.get_field(changeset, :relations) || []
    item_id = Changeset.get_field(changeset, :id)

    relation_structs = Enum.map(relations, fn rel ->
      %MyApp.ItemRelation{
        item_id: item_id,
        target_type: rel["type"],
        target_id: rel["id"]
      }
    end)

    Changeset.put_assoc(changeset, :item_relations, relation_structs)
  end
end
```

### Join Table

```elixir
defmodule MyApp.ItemRelation do
  use Ecto.Schema

  @primary_key false
  schema "item_relations" do
    field :item_id, :binary_id
    field :target_type, :string
    field :target_id, :binary_id
  end
end
```

### Usage

```elixir
# Add a dependency on another item
{:ok, item} = Spector.execute(item, :add_relation, %{
  relation_type: "item",
  relation_id: other_item.id
})

# Add a dependency on a milestone
{:ok, item} = Spector.execute(item, :add_relation, %{
  relation_type: "milestone",
  relation_id: milestone.id
})
```

## Additional Join Table Patterns

### has_many :through

For relationships like `Item -> ItemMember -> Member -> MemberRole`:

```elixir
# Option 1: Event-source the middle entity
defmodule MyApp.ItemMember do
  use Spector.Evented, events: MyApp.Events

  schema "item_members" do
    belongs_to :item, MyApp.Item
    belongs_to :member, MyApp.Member
    field :role, :string
  end
end

# Option 2: Virtual field on the source
# Store the full path: [{member_id: x, role: y}, ...]
```

### Self-Referential many_to_many

For items that depend on other items:

```elixir
defmodule MyApp.Item do
  schema "items" do
    field :dependency_ids, {:array, :binary_id}, virtual: true, default: []
    many_to_many :dependencies, MyApp.Item,
      join_through: "item_dependencies",
      join_keys: [source_id: :id, target_id: :id]
  end
end
```

The join table needs distinct column names:

```elixir
create table(:item_dependencies, primary_key: false) do
  add :source_id, references(:items, type: :binary_id), null: false
  add :target_id, references(:items, type: :binary_id), null: false
end

create unique_index(:item_dependencies, [:source_id, :target_id])
```

### Temporal/Versioned Joins

For tracking when relationships were active:

```elixir
defmodule MyApp.ItemMembership do
  use Spector.Evented, events: MyApp.Events

  schema "item_memberships" do
    belongs_to :item, MyApp.Item
    belongs_to :member, MyApp.Member
    field :joined_at, :utc_datetime
    field :left_at, :utc_datetime
  end
end
```

Event-sourcing the join table itself provides a complete audit trail of relationship changes.

## Best Practices

1. **Prefer belongs_to**: The simplest pattern. Put the foreign key on the side you're event-sourcing.

2. **Event-source children independently**: For `has_many`, let each child be its own event-sourced entity rather than trying to manage the list from the parent.

3. **Use virtual fields for many_to_many**: Store IDs in a virtual field, sync to the join table in `prepare_materialization/1`.

4. **Consider embedded schemas**: For truly owned data that doesn't need independent identity, embedded schemas or JSON fields avoid association complexity.

5. **Be explicit about ownership**: Decide which side "owns" the relationship and captures changes in its events.

6. **Preload before updates**: For virtual field patterns, load existing relationship IDs into the virtual field before making changes.

7. **Document your patterns**: Association handling varies by use case. Document the pattern each relationship uses.

## See Also

- [Building a Basic Chat](basic_chat.md) - Uses belongs_to for conversation membership
- [Event Links Guide](links.md) - For event-to-event relationships within the same record
