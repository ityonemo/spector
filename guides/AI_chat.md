# Building an AI Chat Log with Spector

This guide shows how to use Spector to build an AI chat log that supports conversation branching (like ChatGPT's "edit and regenerate" feature).

## Overview

AI chat applications often need:
- Full conversation history
- Ability to branch from any point in the conversation
- Reconstruct any conversation path from the event log

Spector's event sourcing with links provides exactly this. Each message becomes an event, and branching is handled by tracking ancestors.

## Setup

### 1. Define the Chat Schema

Since chat state is reconstructed from events, use an embedded schema (no database table):

```elixir
defmodule MyApp.AIChat do
  use Spector.Evented, events: MyApp.AIChatEvents, actions: [:append]
  use Ecto.Schema
  alias Ecto.Changeset

  defmodule Message do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :id, :binary_id
      field :content, :string
      field :role, Ecto.Enum, values: [:user, :assistant, :system]
    end

    def changeset(message \\ %__MODULE__{}, attrs) do

      message
      |> Changeset.cast(attrs, [:id, :content, :role])
      |> Spector.changeset_put_event_id(attrs)
      |> Changeset.validate_required([:id, :content, :role])
    end
  end

  @primary_key {:id, :binary_id, autogenerate: false}
  embedded_schema do
    embeds_many :messages, Message
  end

  @impl true
  def prepare_event(event_changeset, previous_events, %{to: ancestor_id}) do
    # Find the ancestor event and build the ancestry chain
    previous_events
    |> Enum.find(&(&1.id == ancestor_id))
    |> MyApp.Repo.preload(:ancestors)
    |> then(&[&1 | &1.ancestors])
    |> then(&Changeset.put_assoc(event_changeset, :ancestors, &1))
  end

  def prepare_event(event_changeset, _previous_events, _attrs) do
    # Require :to for append actions (except the first message)
    if Changeset.fetch_field!(event_changeset, :action) == :append do
      raise ArgumentError, "Missing :to attribute for append action"
    else
      event_changeset
    end
  end

  def changeset(changeset \\ %__MODULE__{}, attrs) do
    changeset = Changeset.change(changeset)

    message =
      attrs
      |> Message.changeset()
      |> Changeset.apply_action!(:insert)

    current_messages = Changeset.get_field(changeset, :messages, [])
    Changeset.put_change(changeset, :messages, [message | current_messages])
  end

  def get_branch(tail_id) do
    case get_branch_events(tail_id) do
      [%{parent_id: parent_id} | _] = events ->
        events
        |> Enum.reduce(%__MODULE__{id: parent_id}, fn event, acc ->
          changeset(acc, Map.put(event.payload, "__event_id__", event.id))
        end)
        |> Changeset.apply_action!(:get)
      [] -> nil
    end
  end

  defp get_branch_events(tail_id) do
    import Ecto.Query

    ancestor_ids =
      from(link in "ai_chat_ancestors",
        where: link.event_id == type(^tail_id, :binary_id),
        select: link.ancestor_id
      )

    MyApp.Repo.all(
      from(e in MyApp.AIChatEvents,
        where: e.id == ^tail_id or e.id in subquery(ancestor_ids),
        order_by: [desc: e.inserted_at]
      )
    )
  end
end
```

### 2. Define the Events Module

```elixir
defmodule MyApp.AIChatEvents do
  use Spector.Events,
    table: "ai_chat_events",
    links: [ancestors: {"ai_chat_ancestors", :ancestor_id}],
    schemas: [MyApp.AIChat],
    repo: MyApp.Repo
end
```

The `links` option creates a many-to-many relationship for tracking message ancestry. Each event can reference its ancestor events, enabling tree-structured conversations.

### 3. Create the Migration

```elixir
defmodule MyApp.Repo.Migrations.CreateChatEvents do
  use Ecto.Migration

  def up do
    Spector.Migration.up(
      table: "ai_chat_events",
      links: [{"ai_chat_ancestors", :ancestor_id}]
    )
  end

  def down do
    Spector.Migration.down(
      table: "ai_chat_events",
      links: [{"ai_chat_ancestors", :ancestor_id}]
    )
  end
end
```

## Usage

### Starting a Conversation

```elixir
assert {:ok, %MyApp.AIChat{messages: [%{role: :user, content: "Hello, how are you?"}]} = chat} =
  Spector.insert(MyApp.AIChat, %{
    role: :user,
    content: "Hello, how are you?"
  })
```

### Adding Messages

To add a message, use `Spector.execute/3` with the `:append` action. The `:to` attribute specifies which message to append after:

```elixir
# Append assistant response
assert {:ok, %{messages: [%{role: :assistant, content: "I'm doing well, thank you!"}, _]} = chat} =
  Spector.execute(chat, :append, %{
    to: chat.id,
    role: :assistant,
    content: "I'm doing well, thank you!"
  })
```

### Branching a Conversation

To branch from an earlier point, specify the `:to` attribute pointing to the message you want to branch from:

```elixir
# branch from the first message
{:ok, %{messages: [%{id: branch_id}, %{id: base_id}, _]}} = Spector.execute(chat, :append, %{
  to: chat.id,
  role: :user,
  content: "Actually, let me rephrase that..."
})
```

### Reconstructing a Conversation Branch

Use `get_branch/1` (defined in the Chat module above) to retrieve the chat state at a specific branch point. Note that messages are prepended in our implementation above, so the most recent message appears first:

```elixir
# Get the assistant's branch (original user message + assistant response)
assert %{messages: [
  %{role: :user, content: "Hello, how are you?"}, 
  %{role: :assistant, content: "I'm doing well, thank you!"}]} = MyApp.AIChat.get_branch(base_id)

# Get the new branch (original user message + rephrased user message)
assert %{messages: [
  %{role: :user, content: "Hello, how are you?"}, 
  %{role: :user, content: "Actually, let me rephrase that..."}]} = MyApp.AIChat.get_branch(branch_id)
```

## How It Works

1. **Insert**: Creates the first event with the initial message. The event `id` and `parent_id` are the same (this is the conversation root).

2. **Append**: Creates a new event linked to the conversation (`parent_id`) with ancestry tracking to the specified message (`to`).

3. **Branching**: When you append with a `:to` pointing to an earlier message, `prepare_event/3` builds the ancestry chain from that point. This creates a new branch in the conversation tree.

4. **Reconstruction**: The `ancestors` association lets you traverse back through any branch to reconstruct the full conversation path.

## Tips

- The `role` enum (`:user`, `:assistant`, `:system`) matches common AI API conventions
- Consider adding timestamps to message payloads for display purposes
- The `parent_id` groups all events for a conversation; use it to list all branches
- Use `get_branch/1` for reconstructing a single path through the conversation tree
