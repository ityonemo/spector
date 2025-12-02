defmodule SpectorTest.Repo.Migrations.CreateTypedLinkEvents do
  use Ecto.Migration

  def up do
    Spector.Migration.up(
      table: "typed_link_events",
      links: [{"typed_event_links", :linked_id, typed: true}]
    )
  end

  def down do
    Spector.Migration.down(
      table: "typed_link_events",
      links: [{"typed_event_links", :linked_id, typed: true}]
    )
  end
end
