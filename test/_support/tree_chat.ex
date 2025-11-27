defmodule SpectorTest.TreeChat do
  @behaviour Spector.Evented
  use Spector.Evented, events: SpectorTest.TreeEvent, actions: [:append]
  use Ecto.Schema
  alias Ecto.Changeset
  alias SpectorTest.Repo

  @primary_key {:id, :binary_id, autogenerate: false}
  embedded_schema do
    # TODO: make this embeds_many
    field(:messages, {:array, :map}, default: [])
  end

  @impl true
  def prepare_event(event_changeset, previous_events, %{to: ancestor_id}) do
    previous_events
    |> Enum.find(&(&1.id == ancestor_id))
    |> Repo.preload(:ancestors)
    |> then(&[&1 | &1.ancestors])
    |> then(&Changeset.put_assoc(event_changeset, :ancestors, &1))
  end

  def prepare_event(event_changeset, _previous_events, _attrs) do
    if Changeset.fetch_field!(event_changeset, :action) == :append do
      raise ArgumentError, "Missing :to attribute for append action"
    else
      event_changeset
    end
  end

  def changeset(changeset, attrs) when changeset.action == :insert do
    message = %{
      content: attrs[:content] || attrs["content"],
      role: attrs[:role] || attrs["role"]
    }

    Changeset.put_change(changeset, :messages, [message])
  end

  def changeset(changeset, attrs) when changeset.action == :append do
    message = %{
      content: attrs[:content] || attrs["content"],
      role: attrs[:role] || attrs["role"]
    }

    current_messages = Changeset.get_field(changeset, :messages) || []
    Changeset.put_change(changeset, :messages, current_messages ++ [message])
  end
end
