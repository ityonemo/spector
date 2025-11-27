defmodule SpectorTest.TestTemplate do
  def execute(module, test_blocks) do
    combined =
      test_blocks
      |> Enum.map(&Code.string_to_quoted!/1)
      |> Enum.reduce(fn block, acc ->
        quote do
          unquote(acc)
          unquote(block)
        end
      end)

    full_code = quote do
      defmodule unquote(module) do
        use ExUnit.Case

        setup do
          :ok = Ecto.Adapters.SQL.Sandbox.checkout(SpectorTest.Repo)
        end

        test "usage examples" do
          unquote(combined)
        end
      end
    end

    Code.eval_quoted(full_code)
  end
end
