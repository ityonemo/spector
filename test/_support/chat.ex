defmodule SpectorTest.Chat do
  use Spector.Evented, events: SpectorTest.Event
  use Ecto.Schema
  alias Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  embedded_schema do
    # TODO: make this embeds_many
    field(:messages, {:array, :map}, default: [])
  end

  def changeset(changeset, attrs) do
    # Append new message to the messages list
    message = %{
      content: attrs[:content] || attrs["content"],
      role: attrs[:role] || attrs["role"]
    }

    current_messages = Changeset.get_field(changeset, :messages) || []

    changeset
    |> Changeset.put_change(:messages, current_messages ++ [message])
  end
end
