defmodule SpectorTest do
  use ExUnit.Case
  doctest Spector

  test "greets the world" do
    assert Spector.hello() == :world
  end
end
