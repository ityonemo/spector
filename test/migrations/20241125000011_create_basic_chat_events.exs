defmodule SpectorTest.Repo.Migrations.CreateBasicChatEvents do
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
