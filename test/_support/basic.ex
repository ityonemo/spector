defmodule SpectorTest.Basic do
  use Ecto.Schema

  schema "basic" do
    field :name, :string
    field :value, :integer
  end
end
