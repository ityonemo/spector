defmodule SpectorTest.ShardedEvent do
  @moduledoc false
  use Spector.Events,
    table: "sharded_events_0",
    shard: :shard_for,
    schemas: [SpectorTest.Sharded],
    repo: SpectorTest.Repo

  def shard_for(uuid) do
    # Last hex char determines parity: 0,2,4,6,8,a,c,e = even, 1,3,5,7,9,b,d,f = odd
    last = String.last(uuid)

    case last in ~w(0 2 4 6 8 a c e) do
      true -> "sharded_events_0"
      false -> "sharded_events_1"
    end
  end
end
