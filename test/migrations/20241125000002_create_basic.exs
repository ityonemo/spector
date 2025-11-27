defmodule SpectorTest.Repo.Migrations.CreateBasic do
  use Ecto.Migration

  def change do
    create table(:basic, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string)
      add(:value, :integer)
    end
  end
end
