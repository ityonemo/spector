defmodule SpectorTest.Repo.Migrations.CreateAIChatEvents do
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
