# CLAUDE.md

## Project Overview

**Spector** is an Elixir/Ecto library for CQRS-style event sourcing.

### Core Concepts

- **Event Log**: A generic table storing all state changes as events
- **Evented Schemas**: Ecto schemas that can rebuild their state from the event log
- **Event Structure**:
  - `id`: UUIDv7 (provides ordering and uniqueness)
  - `parent_id`: Reference to parent event for tracing lineage
  - `payload`: JSONB containing changeset attrs
  - `schema`: The parent schema module name
  - `action`: The action to apply (insert, update, delete)

## Development Commands

```bash
mix deps.get          # Install dependencies
mix test              # Run tests
mix test path:line    # Run specific test
mix format            # Format code
```

## Git Best Practices

- **Feature branches**: `git checkout -b feature/event-log`
- **Commit messages**: Imperative mood, 50 char summary, then details
- **Atomic commits**: Each commit builds successfully and contains one logical change

## TDD Workflow (CRITICAL)

1. **RED**: Write a failing test first
2. **GREEN**: Implement minimal code to pass
3. **REFACTOR**: Clean up while keeping tests green
4. **COMMIT**: One microfeature per commit (test + implementation)

## Avoid Overarchitecting

- Build only what is needed now
- Don't create infrastructure for future features
- If removing code wouldn't break tests, remove it

## Mix Module Usage

**NEVER call Mix functions at runtime** - use conditional compilation or module attributes instead.

## Code Style

- **NO grouped aliases** - Don't use `alias X.{Y, Z}`. This is only for iex. Use separate alias statements instead.
- **alias over import** - Use `alias Ecto.Changeset` instead of `import Ecto.Changeset`. Call functions explicitly as `Changeset.cast/3`.
- **Destructuring assertions** - Use pattern matching in assertions: `assert {:ok, %{id: id, name: "Bob"}} = result` then `assert id == expected_id`. Don't use `assert result.field == value`.

## Library Rules

- **NO config files** - users configure in their application
- Tests handle Repo startup in `test/test_helper.exs`
- Use `Ecto.Adapters.SQL.Sandbox` for test isolation

## Architecture

### Directory Structure

```
lib/spector/
├── spector.ex              # Core public API (insert, update, delete, get, execute)
├── evented.ex              # Macro for marking schemas as event-sourced
├── events.ex               # Macro for defining event log tables
├── query.ex                # Query builders (internal)
├── migration.ex            # Migration helpers for event/link tables
└── integrity/              # Verification modules
    ├── integrity.ex        # Savepoint and hash verification
    ├── hash_mismatch.ex    # Hash chain break exception
    └── savepoint_failure.ex # Savepoint mismatch exception
```

### Key Modules

- **Spector**: Public API - `insert/2`, `update/2`, `delete/1`, `execute/3`, `get/2`, `savepoint/1`, `bringup/1`
- **Spector.Evented**: `use` macro that sets UUIDv7 primary key, injects `__spector__/1` metadata, provides version guards
- **Spector.Events**: `use` macro that creates event log schema with changeset, sharding, and link support
- **Spector.Query**: Internal query builders for event retrieval
- **Spector.Migration**: `up/1`, `down/1` for creating event and link tables

### Macros and Callbacks

**`use Spector.Evented`** options:
- `:events` (required) - Events module
- `:repo` - Override repo (defaults to events module's repo)
- `:version` - Schema version integer (default: 0)
- `:actions` - List of custom action atoms

**`use Spector.Events`** options:
- `:table` (required) - Database table name
- `:schemas` (required) - List of schema modules
- `:repo` (required) - Ecto repo module
- `:hashed` - Enable SHA-256 hash chain (default: false)
- `:shard` - Function name for table sharding
- `:links` - Event linking associations

**Optional callbacks** (`@behaviour Spector.Evented`):
- `prepare_event/3` - Modify event changeset before insertion
- `savepoint/2` - Convert record state to attrs for savepoints

### Event Replay Pattern

Events replay through the schema's `changeset/2` function:
```elixir
def changeset(changeset, attrs) when changeset.action == :custom_action do
  # Handle custom action
end

def changeset(changeset, attrs) when version_is(attrs, 0) do
  # Migrate from v0 to current schema
end

def changeset(changeset, attrs) do
  # Standard insert/update handling
end
```

Use `Spector.get_attr/2` or `Spector.fetch_attr/2` for safe attribute access (handles both atom and string keys from JSON payloads).

## Test Organization

```
test/
├── test_helper.exs         # Repo setup, migration runner, dynamic test generation
├── spector_test.exs        # Main test module
├── spector/                # Feature-specific tests
│   ├── basic_test.exs
│   ├── versioned_test.exs
│   ├── custom_test.exs
│   ├── integrity_test.exs
│   └── ...
└── _support/               # Test schemas and utilities
    ├── repo.ex             # Test Repo
    ├── event.ex            # Events table
    ├── basic.ex            # Basic test schema
    └── ...
```

**Test patterns:**
- Sandbox checkout in setup: `Sandbox.checkout(Repo)`
- Pattern match results: `assert {:ok, %{id: id}} = Spector.insert(...)`
- Preload events via `event_log/1`: `Repo.preload(record, :log)`

## Dependencies

| Package | Purpose |
|---------|---------|
| ecto, ecto_sql | ORM framework |
| uuidv7 | UUIDv7 generation for event IDs |
| postgrex | PostgreSQL adapter (test only) |
| stream_data | Property-based testing (test only) |
| credo | Linting (dev/test only) |