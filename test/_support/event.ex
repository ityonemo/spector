defmodule SpectorTest.Event do
  use Spector.Events,
    table: "events",
    schemas: [SpectorTest.Basic, SpectorTest.Versioned, SpectorTest.Custom],
    repo: SpectorTest.Repo
end
