defmodule SpectorTest.AttrHelpersTest do
  use ExUnit.Case

  describe "Spector.fetch_attr/2" do
    test "returns {:ok, value} for atom key" do
      attrs = %{name: "Alice", value: 42}
      assert {:ok, "Alice"} = Spector.fetch_attr(attrs, :name)
      assert {:ok, 42} = Spector.fetch_attr(attrs, :value)
    end

    test "returns {:ok, value} for string key" do
      attrs = %{"name" => "Bob", "value" => 99}
      assert {:ok, "Bob"} = Spector.fetch_attr(attrs, :name)
      assert {:ok, 99} = Spector.fetch_attr(attrs, :value)
    end

    test "returns :error for missing key" do
      attrs = %{name: "Alice"}
      assert :error = Spector.fetch_attr(attrs, :missing)
    end

    test "returns {:ok, nil} for key with nil value" do
      attrs = %{name: nil}
      assert {:ok, nil} = Spector.fetch_attr(attrs, :name)
    end
  end

  describe "Spector.fetch_attr!/2" do
    test "returns value for atom key" do
      attrs = %{name: "Alice"}
      assert "Alice" = Spector.fetch_attr!(attrs, :name)
    end

    test "returns value for string key" do
      attrs = %{"name" => "Bob"}
      assert "Bob" = Spector.fetch_attr!(attrs, :name)
    end

    test "raises KeyError for missing key" do
      attrs = %{name: "Alice"}
      assert_raise KeyError, fn -> Spector.fetch_attr!(attrs, :missing) end
    end

    test "returns nil for key with nil value" do
      attrs = %{name: nil}
      assert nil == Spector.fetch_attr!(attrs, :name)
    end
  end

  describe "Spector.get_attr/2,3" do
    test "returns value for atom key" do
      attrs = %{name: "Alice"}
      assert "Alice" = Spector.get_attr(attrs, :name)
    end

    test "returns value for string key" do
      attrs = %{"name" => "Bob"}
      assert "Bob" = Spector.get_attr(attrs, :name)
    end

    test "returns nil for missing key with no default" do
      attrs = %{name: "Alice"}
      assert nil == Spector.get_attr(attrs, :missing)
    end

    test "returns default for missing key" do
      attrs = %{name: "Alice"}
      assert "default" = Spector.get_attr(attrs, :missing, "default")
    end

    test "returns nil for key with nil value (not default)" do
      attrs = %{name: nil}
      assert nil == Spector.get_attr(attrs, :name, "default")
    end
  end
end
