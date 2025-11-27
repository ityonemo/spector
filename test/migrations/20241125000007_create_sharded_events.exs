defmodule SpectorTest.Repo.Migrations.CreateShardedEvents do
  use Ecto.Migration

  def up do
    Spector.Migration.up(table: "sharded_events_0")
    Spector.Migration.up(table: "sharded_events_1")
  end

  def down do
    Spector.Migration.down(table: "sharded_events_0")
    Spector.Migration.down(table: "sharded_events_1")
  end
end
