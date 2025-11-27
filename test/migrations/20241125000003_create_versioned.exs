defmodule SpectorTest.Repo.Migrations.CreateVersioned do
  use Ecto.Migration

  def change do
    create table(:versioned, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string)
      add(:value, :integer)
    end
  end
end
