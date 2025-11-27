defmodule SpectorTest.Repo.Migrations.CreateSharded do
  use Ecto.Migration

  def change do
    create table(:sharded, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string)
      add(:value, :integer)
    end
  end
end
