defmodule SpectorTest.Repo do
  use Ecto.Repo,
    otp_app: :spector,
    adapter: Ecto.Adapters.Postgres
end
