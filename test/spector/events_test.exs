defmodule SpectorTest.EventsTest do
  use ExUnit.Case

  describe "schema validation" do
    test "raises when schema does not declare this events module" do
      assert_raise CompileError,
                   ~r/SpectorTest.Orphan does not declare SpectorTest.WrongEvents as its events module/,
                   fn ->
                     Code.compile_file("test/spector/events_orphan.exs")
                   end
    end
  end
end
