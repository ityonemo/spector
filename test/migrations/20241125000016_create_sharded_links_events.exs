defmodule SpectorTest.Repo.Migrations.CreateShardedLinksEvents do
  use Ecto.Migration

  def up do
    Spector.Migration.up(
      shards: ["sharded_links_events_0", "sharded_links_events_1"],
      links: [{"ancestors", :ancestor_id}]
    )
  end

  def down do
    Spector.Migration.down(
      shards: ["sharded_links_events_0", "sharded_links_events_1"],
      links: [{"ancestors", :ancestor_id}]
    )
  end
end
