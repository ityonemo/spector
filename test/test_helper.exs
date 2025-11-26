ExUnit.start()

# Configure the test repo
Application.put_env(:spector, SpectorTest.Repo,
  database: "spector_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
)

# Create and migrate the database
{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(SpectorTest.Repo, :temporary)

# Drop and recreate DB to ensure clean state
_ = SpectorTest.Repo.__adapter__().storage_down(SpectorTest.Repo.config())

case SpectorTest.Repo.__adapter__().storage_up(SpectorTest.Repo.config()) do
  :ok -> :ok
  {:error, :already_up} -> :ok
  {:error, reason} -> raise "Failed to create database: #{inspect(reason)}"
end

# Start the Repo
{:ok, _} = SpectorTest.Repo.start_link()

# Run migrations
Ecto.Migrator.run(SpectorTest.Repo, "test/migrations", :up, all: true)

# Set up sandbox for test isolation
Ecto.Adapters.SQL.Sandbox.mode(SpectorTest.Repo, :manual)
