defmodule SpectorTest.Event do
  use Spector.Events, table: "events", schemas: [SpectorTest.Basic], repo: SpectorTest.Repo
end
