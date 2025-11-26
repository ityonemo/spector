defmodule SpectorTest.Event do
  use Spector.Events, table: "events", schemas: [SpectorTest.Basic, SpectorTest.Versioned], repo: SpectorTest.Repo
end
