defmodule SpectorTest.TreeEvent do
  use Spector.Events,
    table: "tree_events",
    links: [ancestors: {"tree_ancestors", :ancestor_id}],
    schemas: [SpectorTest.TreeChat],
    repo: SpectorTest.Repo
end
