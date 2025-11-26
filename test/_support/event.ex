defmodule SpectorTest.Event do
  use Spector, table: "events", schemas: [SpectorTest.User]
end

defmodule SpectorTest.User do
  # Placeholder schema for testing
end
