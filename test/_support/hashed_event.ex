defmodule SpectorTest.HashedEvent do
  @moduledoc false
  use Spector.Events,
    table: "hashed_events",
    schemas: [SpectorTest.Hashed],
    repo: SpectorTest.Repo,
    hashed: true
end
