defmodule SpectorTest.Repo.Migrations.CreateHashedEvents do
  use Ecto.Migration

  def up, do: Spector.Migration.up(table: "hashed_events", hashed: true)
  def down, do: Spector.Migration.down(table: "hashed_events")
end
