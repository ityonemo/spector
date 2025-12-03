ExUnit.start()

Logger.configure(level: :error)

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

# Helper to generate tests from guide markdown files
defmodule SpectorTest.GuideHelper do
  def load_guide(path) do
    File.read!(path)
    |> then(&Regex.scan(~r/```elixir\n(.*?)```/s, &1, capture: :all_but_first))
    |> Enum.map(&hd/1)
    |> Enum.reject(&String.contains?(&1, "use Ecto.Migration"))
    |> Enum.map(&String.replace(&1, "MyApp.Repo", "SpectorTest.Repo"))
    |> Enum.split_with(&String.starts_with?(&1, "defmodule"))
  end
end

# Generate tests from AI_chat.md
{ai_modules, ai_tests} = SpectorTest.GuideHelper.load_guide("guides/AI_chat.md")
Enum.each(ai_modules, &Code.eval_string/1)
SpectorTest.TestTemplate.execute(AIChatTest, ai_tests)

# Generate tests from basic_chat.md
{basic_modules, basic_tests} = SpectorTest.GuideHelper.load_guide("guides/basic_chat.md")
Enum.each(basic_modules, &Code.eval_string/1)
SpectorTest.TestTemplate.execute(BasicChatTest, basic_tests)

# Generate tests from links.md
{links_modules, links_tests} = SpectorTest.GuideHelper.load_guide("guides/links.md")
Enum.each(links_modules, &Code.eval_string/1)
SpectorTest.TestTemplate.execute(LinksTest, links_tests)
