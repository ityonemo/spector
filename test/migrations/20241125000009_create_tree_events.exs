defmodule SpectorTest.Repo.Migrations.CreateTreeEvents do
  use Ecto.Migration

  def up,
    do: Spector.Migration.up(table: "tree_events", links: [{"tree_ancestors", :ancestor_id}])

  def down,
    do: Spector.Migration.down(table: "tree_events", links: [{"tree_ancestors", :ancestor_id}])
end
