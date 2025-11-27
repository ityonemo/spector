defmodule SpectorTest.Repo.Migrations.CreateCustom do
  use Ecto.Migration

  def change do
    create table(:custom, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string)
      add(:value, :integer)
      add(:archived_at, :utc_datetime_usec)
    end
  end
end
