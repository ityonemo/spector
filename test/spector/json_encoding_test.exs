defmodule SpectorTest.JsonEncodingTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "JSON encoding key order" do
    property "string key maps are encoded with keys in lexicographic order" do
      check all map <- map_of(string(:alphanumeric, min_length: 1), integer()) do
        json = Spector._json_encode!(map)

        # Extract all keys from the JSON by matching quoted strings followed by :
        keys =
          Regex.scan(~r/"([^"]+)":/, json)
          |> Enum.map(fn [_, key] -> key end)

        # Verify keys are in lexicographic order
        assert keys == Enum.sort(keys),
               "Keys not in lexicographic order: #{inspect(keys)} vs #{inspect(Enum.sort(keys))}"

        # Verify round-trip: decoded JSON equals original map (with string keys)
        assert map = JSON.decode!(json)
      end
    end
  end
end
