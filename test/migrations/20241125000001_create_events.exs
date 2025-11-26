defmodule SpectorTest.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def up, do: Spector.Migration.up(table: "events")
  def down, do: Spector.Migration.down(table: "events")
end
