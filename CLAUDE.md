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
