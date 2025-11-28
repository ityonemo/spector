defmodule SpectorTest.Repo.Migrations.CreateCustomPK do
  use Ecto.Migration

  def change do
    create table(:custom_pk, primary_key: false) do
      add(:uuid, :binary_id, primary_key: true)
      add(:name, :string)
      add(:value, :integer)
    end
  end
end
