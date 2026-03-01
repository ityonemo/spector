# Otzel Integration Guide

This guide covers integrating [Otzel](https://github.com/ityonemo/otzel), an Operational Transformation (OT) library for Elixir, with Spector event-sourced schemas. Otzel provides Quill.js-compatible rich text operations that pair naturally with event sourcing.

## Overview

### Why Otzel + Event Sourcing?

Traditional approaches store full document contents on each save. With Otzel and Spector:

- **Store diffs, not documents**: Events contain delta operations (insertions, deletions, formatting changes) rather than full content
- **Automatic composition**: When replaying events, deltas compose into the current document state
- **Full edit history**: Every keystroke or edit is preserved in the event log
- **Conflict resolution**: OT transforms handle concurrent edits from multiple clients

### The Key Insight

Otzel deltas are composable: `delta1 |> Otzel.compose(delta2) |> Otzel.compose(delta3)` produces the final document state. This maps perfectly to event replay—each event stores a delta, and composing them during replay reconstructs the document.

## Basic Usage with `Otzel.Ecto.Delta`

For simple cases without custom embeds, use Otzel's built-in Ecto type:

```elixir
defmodule MyApp.Document do
  use Spector.Evented, events: MyApp.Events
  use Ecto.Schema
  alias Ecto.Changeset

  schema "documents" do
    field :title, :string
    field :content, Otzel.Ecto.Delta, default: Otzel.quill_init()

    timestamps()
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:title, :inserted_at, :updated_at])
    |> apply_delta_change(attrs)
    |> Changeset.validate_required([:title, :content])
  end

  defp apply_delta_change(changeset, attrs) do
    case Spector.fetch_attr(attrs, :content_diff) do
      {:ok, diff} when not is_nil(diff) ->
        changeset
        |> Changeset.get_field(:content)
        |> Otzel.compose(ensure_otzel_structs(diff))
        |> then(&Changeset.put_change(changeset, :content, &1))

      _ ->
        changeset
    end
  end

  # Event payloads come back as JSON maps during replay
  # Convert them back to Otzel structs
  defp ensure_otzel_structs([diff | _] = delta) when not is_struct(diff) do
    {:ok, ops} = Otzel.from_json(delta)
    ops
  end

  defp ensure_otzel_structs(delta), do: delta
end
```

### The Quill Default

Quill.js requires documents to end with a newline character. Use `Otzel.quill_init()` which returns `[Otzel.insert("\n")]` as the default value for Quill-backed fields.

## Custom Embeds with `embed_encoder` Option

When you need custom embeds (checkboxes, images, etc.), use the `:embed_encoder` option with `Otzel.from_json/2`:

```elixir
# Signature: Otzel.from_json(json, embed_encoder: {Module, :function})
# Or: Otzel.from_json(json, embed_encoder: &function/1)

# The encoder function receives a raw JSON map and returns:
# - A struct for recognized embeds
# - The original value unchanged for unrecognized data

defmodule MyApp.Embeds do
  def encode(%{"checkbox" => checked}) do
    %MyApp.Checkbox{checked: checked}
  end

  def encode(%{"image" => %{"url" => url, "alt" => alt}}) do
    %MyApp.Image{url: url, alt: alt}
  end

  def encode(other), do: other  # Pass through unchanged
end

# Usage:
{:ok, delta} = Otzel.from_json(json, embed_encoder: {MyApp.Embeds, :encode})

# Or with function capture:
{:ok, delta} = Otzel.from_json(json, embed_encoder: &MyApp.Embeds.encode/1)
```

### Embed Structs

Define struct modules for your custom embeds:

```elixir
defmodule MyApp.Checkbox do
  @derive Jason.Encoder
  defstruct [:checked]
end

defmodule MyApp.Image do
  @derive Jason.Encoder
  defstruct [:url, :alt]
end
```

Embeds appear in deltas as `Otzel.insert(%MyApp.Checkbox{checked: true})`.

## Schema with Custom Embeds

When using custom embeds, you need to handle struct conversion during event replay:

```elixir
defmodule MyApp.Document do
  use Spector.Evented, events: MyApp.Events
  use Ecto.Schema
  alias Ecto.Changeset

  schema "documents" do
    field :title, :string
    field :content, Otzel.Ecto.Delta, default: Otzel.quill_init()

    # Virtual fields for conflict resolution
    field :last_event_id, :binary_id, virtual: true
    field :replay_events, {:array, :map}, virtual: true

    timestamps()
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:title, :inserted_at, :updated_at])
    |> apply_delta_change(attrs)
    |> Changeset.validate_required([:title, :content])
  end

  defp apply_delta_change(changeset, attrs) do
    case Spector.fetch_attr(attrs, :content_diff) do
      {:ok, diff} when not is_nil(diff) ->
        changeset
        |> Changeset.get_field(:content)
        |> Otzel.compose(ensure_otzel_structs(diff))
        |> then(&Changeset.put_change(changeset, :content, &1))

      _ ->
        changeset
    end
  end

  # Event payloads come back as JSON maps during replay
  # Convert them back to Otzel structs, handling custom embeds
  defp ensure_otzel_structs([diff | _] = delta) when not is_struct(diff) do
    Otzel.from_json(delta, embed_encoder: &embed_encoder/1)
  end

  defp ensure_otzel_structs(delta), do: delta

  defp embed_encoder(%{"checkbox" => checked}) do
    %MyApp.Checkbox{checked: checked}
  end

  defp embed_encoder(%{"image" => %{"url" => url, "alt" => alt}}) do
    %MyApp.Image{url: url, alt: alt}
  end

  defp embed_encoder(other), do: other
end
```

## Delta Composition in Changesets

The core pattern composes incoming diffs with the current document state:

```elixir
defp apply_delta_change(changeset, attrs) do
  case Spector.fetch_attr(attrs, :content_diff) do
    {:ok, diff} when not is_nil(diff) ->
      changeset
      |> Changeset.get_field(:content)
      |> Otzel.compose(ensure_otzel_structs(diff))
      |> then(&Changeset.put_change(changeset, :content, &1))

    _ ->
      changeset
  end
end
```

### Why Diffs Compose Correctly During Replay

When events replay:

1. First event: `[] |> compose(diff1)` = state after edit 1
2. Second event: `state1 |> compose(diff2)` = state after edit 2
3. And so on...

Each event stores only the delta (diff), but composition rebuilds the full document state. This is storage-efficient and provides complete edit history.

### Events That Don't Modify the Delta

When an event only modifies non-delta fields (e.g., updating `title` without changing `content`), you have two options:

1. **Omit `content_diff`**: The `apply_delta_change` function returns the changeset unchanged
2. **Pass `content_diff: []`**: An empty delta composes to a no-op (`Otzel.compose(content, []) == content`)

Both approaches work correctly during replay. Omitting the field is cleaner, but explicit `[]` can be useful for audit trails showing the field was considered.

**Warning**: Never pass `content_diff: nil`. The guard `when not is_nil(diff)` protects against this, but `nil` values stored in event payloads can cause subtle bugs during replay. Always omit the key entirely or use `[]`.

## Conflict Resolution

When multiple clients edit concurrently, the server may receive a diff based on stale state. OT transforms resolve this.

### The Pattern

1. Client sends diff + `previous_id` (the last event ID it knew about)
2. Server checks if `previous_id` matches the actual last event
3. If stale, transform the incoming diff against intervening server changes
4. Store the transformed diff

### Full Implementation

```elixir
defmodule MyApp.Document do
  use Spector.Evented, events: MyApp.Events
  use Ecto.Schema
  alias Ecto.Changeset

  schema "documents" do
    field :title, :string
    field :content, Otzel.Ecto.Delta, default: Otzel.quill_init()

    # Virtual fields for conflict resolution
    field :last_event_id, :binary_id, virtual: true
    field :replay_events, {:array, :map}, virtual: true

    timestamps()
  end

  def changeset(changeset, attrs) do
    changeset
    |> Changeset.cast(attrs, [:title, :inserted_at, :updated_at])
    |> apply_delta_change(attrs)
    |> Changeset.validate_required([:title, :content])
  end

  defp apply_delta_change(changeset, attrs) do
    case Spector.fetch_attr(attrs, :content_diff) do
      {:ok, diff} when not is_nil(diff) ->
        diff = ensure_otzel_structs(diff)

        # Check for conflict: did other events happen since the client's base state?
        transformed_diff = maybe_transform_diff(diff, attrs)

        changeset
        |> Changeset.get_field(:content)
        |> Otzel.compose(transformed_diff)
        |> then(&Changeset.put_change(changeset, :content, &1))

      _ ->
        changeset
    end
  end

  defp maybe_transform_diff(diff, attrs) do
    previous_id = Spector.get_attr(attrs, :previous_id)
    replay_events = Spector.get_attr(attrs, :replay_events, [])

    case find_client_base_index(replay_events, previous_id) do
      nil ->
        # No previous_id or not found - no transform needed
        diff

      base_index ->
        # Transform against all events after the client's base
        server_changes =
          replay_events
          |> Enum.drop(base_index + 1)
          |> Enum.map(&extract_content_diff/1)
          |> Enum.reject(&is_nil/1)

        Enum.reduce(server_changes, diff, fn server_diff, client_diff ->
          # Transform: given concurrent edits, how should the client diff be adjusted?
          Otzel.transform(server_diff, client_diff, :right)
        end)
    end
  end

  defp find_client_base_index(events, previous_id) when is_binary(previous_id) do
    Enum.find_index(events, fn event ->
      to_string(event.id) == previous_id or event.id == previous_id
    end)
  end

  defp find_client_base_index(_, _), do: nil

  defp extract_content_diff(%{payload: %{"content_diff" => diff}}) do
    ensure_otzel_structs(diff)
  end

  defp extract_content_diff(%{payload: %{content_diff: diff}}) do
    ensure_otzel_structs(diff)
  end

  defp extract_content_diff(_), do: nil

  defp ensure_otzel_structs([diff | _] = delta) when not is_struct(diff) do
    Otzel.from_json(delta, embed_encoder: &embed_encoder/1)
  end

  defp ensure_otzel_structs(delta), do: delta

  defp embed_encoder(%{"checkbox" => checked}) do
    %MyApp.Checkbox{checked: checked}
  end

  defp embed_encoder(other), do: other
end
```

### Usage with Conflict Detection

```elixir
def update_document(document, content_diff, previous_id) do
  # Fetch events for replay and conflict detection
  events = Spector.all_events(MyApp.Document, document.id)

  Spector.update(document, %{
    content_diff: content_diff,
    previous_id: previous_id,
    replay_events: events
  })
end
```

## Frontend Integration

On the Elixir side, receive JSON deltas from the frontend and pass to your context:

```elixir
defmodule MyAppWeb.DocumentLive do
  # Handle delta from Quill.js
  def handle_event("text_change", %{"delta" => delta_json, "previous_id" => prev_id}, socket) do
    case Otzel.from_json(delta_json, embed_encoder: &embed_encoder/1) do
      {:ok, delta} ->
        MyApp.Documents.update_content(
          socket.assigns.document,
          delta,
          prev_id
        )

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid delta")}
    end
  end

  defp embed_encoder(%{"checkbox" => checked}) do
    %MyApp.Checkbox{checked: checked}
  end

  defp embed_encoder(other), do: other
end
```

This pattern works with any frontend that sends Quill-compatible delta JSON.

## Custom Ecto Type (When Needed)

Create a custom Ecto type only when you need:
- Custom embeds baked into the type
- A different default (non-Quill)

```elixir
defmodule MyApp.Delta.Richtext do
  use Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  def cast(data) when is_list(data), do: {:ok, data}

  def cast(data) when is_map(data) do
    Otzel.from_json(data, embed_encoder: &embed_encoder/1)
  end

  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, Otzel.quill_init()}

  def load(data) when is_map(data) do
    Otzel.from_json(data, embed_encoder: &embed_encoder/1)
  end

  @impl true
  def dump(delta) when is_list(delta), do: {:ok, Otzel.to_json(delta)}
  def dump(_), do: :error

  defp embed_encoder(%{"checkbox" => checked}) do
    %MyApp.Checkbox{checked: checked}
  end

  defp embed_encoder(other), do: other
end
```

## Advanced: Non-Quill OT Fields

Sometimes you need OT for structured data that isn't Quill rich text—annotated sequences, custom formats, or domain-specific structures.

### Key Differences from Quill Fields

1. **Different default**: Use `[]` (empty list), NOT `Otzel.quill_init()`
2. **Must be non-null**: Use `default: []` in the schema
3. **Different embed encoder**: Handle domain-specific embeds

### Example: Annotated Sequence

```elixir
defmodule MyApp.Delta.Sequence do
  use Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  def cast(data) when is_list(data), do: {:ok, data}

  def cast(data) when is_map(data) do
    Otzel.from_json(data, embed_encoder: &sequence_embed_encoder/1)
  end

  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, []}  # Empty list, not Quill newline

  def load(data) when is_map(data) do
    Otzel.from_json(data, embed_encoder: &sequence_embed_encoder/1)
  end

  @impl true
  def dump(delta) when is_list(delta), do: {:ok, Otzel.to_json(delta)}
  def dump(_), do: :error

  # Domain-specific embeds
  defp sequence_embed_encoder(%{"marker" => %{"type" => type, "position" => pos}}) do
    %MyApp.Marker{type: type, position: pos}
  end

  defp sequence_embed_encoder(other), do: other
end
```

```elixir
defmodule MyApp.Annotation do
  use Spector.Evented, events: MyApp.Events
  use Ecto.Schema

  schema "annotations" do
    field :name, :string
    field :sequence, MyApp.Delta.Sequence, default: []  # Empty list default
    timestamps()
  end
end
```

## Multiple OT Types in One Application

You may need different OT field types in the same application.

### Pattern 1: Quill + Non-Quill Fields

When you have both a rich text editor and a structured OT field:

```elixir
defmodule MyApp.AnnotatedDocument do
  use Spector.Evented, events: MyApp.Events
  use Ecto.Schema

  schema "annotated_documents" do
    # Quill rich text - requires trailing newline
    field :content, Otzel.Ecto.Delta, default: Otzel.quill_init()

    # Structured annotations - empty list default
    field :annotations, MyApp.Delta.Sequence, default: []

    timestamps()
  end
end
```

Each field uses its own Ecto type with the appropriate:
- Default value (`Otzel.quill_init()` vs `[]`)
- Embed encoder (Quill embeds vs domain embeds)

### Pattern 2: Multiple Quill Fields with Different Plugins

When you have multiple Quill editors with different embed configurations, create custom types:

```elixir
defmodule MyApp.Delta.BasicRichtext do
  use Ecto.Type
  # Standard Quill with no custom embeds
  # ... standard implementation using Otzel.from_json/1
end

defmodule MyApp.Delta.ChecklistRichtext do
  use Ecto.Type
  # Quill with checkbox support
  defp embed_encoder(%{"checkbox" => checked}) do
    %MyApp.Checkbox{checked: checked}
  end
  defp embed_encoder(other), do: other
end
```

## Best Practices

1. **Use `Otzel.Ecto.Delta` for simple cases**: Only create custom Ecto types when you need custom embeds baked into the type

2. **Use the correct `embed_encoder` signature**:
   ```elixir
   # Correct - as keyword option
   Otzel.from_json(data, embed_encoder: &embed_encoder/1)
   Otzel.from_json(data, embed_encoder: {Module, :function})

   # Wrong - as positional argument
   Otzel.from_json(data, &embed_encoder/1)
   ```

3. **Embed encoders return values directly** (not wrapped in `{:ok, ...}`):
   ```elixir
   # Correct
   defp embed_encoder(%{"checkbox" => checked}) do
     %MyApp.Checkbox{checked: checked}
   end
   defp embed_encoder(other), do: other

   # Wrong
   defp embed_encoder(%{"checkbox" => checked}) do
     {:ok, %MyApp.Checkbox{checked: checked}}
   end
   ```

4. **Always store diffs, not full documents**: Pass `content_diff` to your changeset, compose with current state

5. **Use the correct default**:
   - Quill fields: `Otzel.quill_init()` (returns `[Otzel.insert("\n")]`)
   - Non-Quill OT fields: `[]`

6. **Handle JSON round-trip in changesets**: Event payloads come back as JSON maps during replay. Use `ensure_otzel_structs` pattern with `Otzel.from_json/2`

7. **Handle both atom and string keys**: Use `Spector.get_attr/2` or `Spector.fetch_attr/2`

8. **Test conflict resolution**: Write tests that simulate concurrent edits with stale `previous_id` values

## See Also

- [Otzel Documentation](https://hexdocs.pm/otzel)
- [Quill.js Delta Format](https://quilljs.com/docs/delta/)
- [Building a Basic Chat](basic_chat.md) - For simpler text fields without OT
