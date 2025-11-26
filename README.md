# Spector

CQRS-style event sourcing for Ecto schemas.

## Database Support

Spector works with any database supported by Ecto for basic functionality.

**Note:** Hashed event tables (`hashed: true`) currently require PostgreSQL. The hash chain integrity feature uses `LOCK TABLE ... IN EXCLUSIVE MODE` which is PostgreSQL-specific. SQLite and other databases are not yet supported for hashed tables.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `spector` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:spector, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/spector>.

