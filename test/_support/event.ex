defmodule SpectorTest.Event do
  @moduledoc false
  use Spector.Events,
    table: "events",
    schemas: [
      SpectorTest.Basic,
      SpectorTest.Versioned,
      {SpectorTest.Custom, 10},
      SpectorTest.Chat,
      SpectorTest.BringupSchema,
      SpectorTest.CustomPK,
      SpectorTest.Savepointable,
      SpectorTest.PrepareMaterializationSchema
    ],
    repo: SpectorTest.Repo
end
