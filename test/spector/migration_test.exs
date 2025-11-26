defmodule Spector.MigrationTest do
  use ExUnit.Case

  test "migration module exists and has up/0 and down/0" do
    {:module, _} = Code.ensure_loaded(Spector.Migration)
    assert function_exported?(Spector.Migration, :up, 0)
    assert function_exported?(Spector.Migration, :down, 0)
  end
end
