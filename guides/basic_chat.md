# Building a Basic Chat with Spector

This guide shows how to use Spector to build a simple chat with edit history tracking using event links.

## Overview

Basic chat applications need:
- Message history with user identification
- Ability to edit messages while preserving previous versions
- Simple linear conversation flow (no branching)

Spector's event sourcing with links tracks every edit as a linked event chain.

## Setup

### 1. Define the Chat Schema

```elixir
defmodule MyApp.BasicChat do
  use Spector.Evented, events: MyApp.BasicChatEvents, actions: [:edit]
  use Ecto.Schema
  alias Ecto.Changeset
  import Ecto.Query

  @behaviour Spector.Evented

  defmodule Message do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :id, :binary_id
      field :user_id, :binary_id
      field :content, :string
    end

    def changeset(message \\ %__MODULE__{}, attrs) do
      message
      |> Changeset.cast(attrs, [:user_id, :content])
      |> Spector.changeset_put_event_id(attrs)
      |> Changeset.validate_required([:id, :user_id, :content])
    end
  end

  @primary_key {:id, :binary_id, autogenerate: false}
  embedded_schema do
    embeds_many :messages, Message
  end

  @impl true
  def prepare_event(event_changeset, previous_events, %{edits: previous_id}) do
    previous_events
    |> Enum.find(&(&1.id == previous_id))
    |> then(&Changeset.put_assoc(event_changeset, :edits, [&1]))
  end

  def prepare_event(event_changeset, _previous_events, _attrs) do
    event_changeset
  end

  def changeset(chat \\ %__MODULE__{}, attrs)

  def changeset(chat, %{edits: message_id, content: new_content}) when chat.action == :edit do
    chat = Changeset.change(chat)
    current_messages = Changeset.get_field(chat, :messages, [])

    updated_messages =
      Enum.map(current_messages, fn message ->
        if message.id == message_id do
          %{message | content: new_content}
        else
          message
        end
      end)

    Changeset.put_change(chat, :messages, updated_messages)
  end

  def changeset(chat, attrs) do
    chat = Changeset.change(chat)

    message =
      attrs
      |> Message.changeset()
      |> Changeset.apply_action!(:insert)

    current_messages = Changeset.get_field(chat, :messages, [])
    Changeset.put_change(chat, :messages, [message | current_messages])
  end

  def list_messages(chat_id) do
    edited_ids =
      from(link in "basic_chat_edits", select: link.previous_id)
      |> MyApp.Repo.all()

    Spector.all_events(__MODULE__, chat_id)
    |> Enum.reject(&(&1.id in edited_ids))
  end

  def get_edit_history(message_id) do
    previous_ids =
      from(link in "basic_chat_edits",
        where: link.event_id == type(^message_id, :binary_id),
        select: link.previous_id
      )

    MyApp.Repo.all(
      from(e in MyApp.BasicChatEvents,
        where: e.id == ^message_id or e.id in subquery(previous_ids),
        order_by: [asc: e.inserted_at]
      )
    )
  end
end
```

### 2. Define the Events Module

```elixir
defmodule MyApp.BasicChatEvents do
  use Spector.Events,
    table: "basic_chat_events",
    links: [edits: {"basic_chat_edits", :previous_id}],
    schemas: [MyApp.BasicChat],
    repo: MyApp.Repo
end
```

The `edits` link creates a relationship from the edited message to its previous version.

### 3. Create the Migration

```elixir
defmodule MyApp.Repo.Migrations.CreateBasicChatEvents do
  use Ecto.Migration

  def up do
    Spector.Migration.up(
      table: "basic_chat_events",
      links: [{"basic_chat_edits", :previous_id}]
    )
  end

  def down do
    Spector.Migration.down(
      table: "basic_chat_events",
      links: [{"basic_chat_edits", :previous_id}]
    )
  end
end
```

## Usage

### Starting a Conversation

```elixir
user_id = Ecto.UUID.generate()

assert {:ok, %MyApp.BasicChat{messages: [%{user_id: ^user_id, content: "Hello everyone!"}]} = chat} =
  Spector.insert(MyApp.BasicChat, %{
    user_id: user_id,
    content: "Hello everyone!"
  })
```

### Adding Messages

Note that messages are prepended, so the most recent message appears first:

```elixir
other_user_id = Ecto.UUID.generate()

assert {:ok, %{messages: [%{user_id: ^other_user_id, content: "Hi there!"}, %{content: "Hello everyone!"}]} = chat} =
  Spector.update(chat, %{
    user_id: other_user_id,
    content: "Hi there!"
  })
```

### Editing a Message

Use the `:edit` action with `:edits` pointing to the message ID being edited:

```elixir
[_, %{id: first_message_id}] = chat.messages

assert {:ok, %{messages: [%{content: "Hi there!"}, %{content: "Hello everyone! (edited)"}]}} =
  Spector.execute(chat, :edit, %{
    edits: first_message_id,
    content: "Hello everyone! (edited)"
  })
```


## How It Works

1. **Insert**: Creates the first event with the initial message.

2. **Update**: Adds new messages to the conversation.

3. **Edit**: Creates a new event linked to the previous version via `basic_chat_edits`. The original remains in the event log.

4. **History**: Follow the `edits` links backward to see all versions of a message.

## Tips

- The `user_id` in each message tracks the author
- Edits preserve the original `user_id` - add an `edited_by` field if you need to track who made edits
- For real-time updates, combine with Phoenix PubSub
- Add `inserted_at` from the event for message timestamps
