defmodule SpectorTest.Event do
  use Spector.Events,
    table: "events",
    schemas: [
      SpectorTest.Basic,
      SpectorTest.Versioned,
      {SpectorTest.Custom, 10},
      SpectorTest.Chat,
      SpectorTest.BringupSchema,
      SpectorTest.CustomPK,
      SpectorTest.Savepointable
    ],
    repo: SpectorTest.Repo
end
