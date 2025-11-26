# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## IMPORTANT: Git Best Practices

When working in this repository, follow these git guidelines:

- **Feature branches**: Create a new branch for each feature or significant change (e.g., `git checkout -b feature/semantic-search`)
- **Commit messages**: Write clear, descriptive commit messages in imperative mood (e.g., "Add vector search tool", not "Added vector search tool")
- **Commit summaries**: Include a brief summary line (50 chars max), followed by a blank line and detailed description if needed
- **Logical commits**: Group related changes into single commits (e.g., all files for one tool in one commit, not mixing unrelated changes)
- **Atomic commits**: Each commit should represent a single, complete change that builds successfully

Example workflow:
```bash
git checkout -b feature/ast-parser
# Make changes...
git add lib/codicil/parser.ex test/codicil/parser_test.exs
git commit -m "Add Elixir AST parser for function extraction

- Parse def/defp/defmacro definitions
- Extract function signatures and line numbers
- Handle multi-clause functions
- Add comprehensive test coverage"
```

## IMPORTANT: Test-Driven Development (TDD) Workflow

**CRITICAL:** All development MUST follow strict Test-Driven Development (TDD):

### Microfeature Development Cycle

1. **Write the test FIRST**
   - Identify a small, focused microfeature to implement
   - Write a failing test that describes the expected behavior
   - Run the test to confirm it fails (red)

2. **Make the test pass**
   - Implement the minimal code necessary to make the test pass
   - Run the test to confirm it passes (green)
   - Refactor if needed while keeping tests green

3. **Commit immediately**
   - Commit both the test and implementation together
   - Each commit should contain ONE microfeature (test + code)
   - Never commit code without its corresponding test
   - Never commit multiple microfeatures in a single commit

### What is a Microfeature?

A microfeature is a small, atomic piece of functionality that:
- Can be tested independently
- Takes minutes, not hours, to implement
- Has a clear, single responsibility
- Represents one behavior or capability

### Examples of Microfeatures

**Good microfeatures (one commit each):**
- "Add Function schema with basic fields"
- "Add function name validation to changeset"
- "Add database connection configuration"
- "Add query to find function by name and path"
- "Add index on functions (name, path) columns"

**Too large (should be split):**
- ❌ "Add complete database layer" (split into schema, repo, migrations, queries)
- ❌ "Implement AST parser" (split into parse file, extract functions, detect calls, etc.)

### TDD Workflow Example

```bash
# 1. Write failing test
# Create test/codicil_db/function_test.exs
mix test  # Confirm it fails (RED)

# 2. Implement minimal code to pass
# Create lib/codicil_db/function.ex with schema
mix test  # Confirm it passes (GREEN)

# 3. Commit immediately
git add test/codicil_db/function_test.exs lib/codicil_db/function.ex
git commit -m "Add Function schema with basic fields

- Define Ecto schema for functions table
- Include id, name, path, start_line, end_line fields
- Add test verifying schema struct creation"

# 4. Repeat for next microfeature
```

### Why This Matters

- **Prevents scope creep**: Forces you to think in small increments
- **Better git history**: Each commit is self-contained and understandable
- **Easier debugging**: Small commits make it easy to identify when bugs were introduced
- **Confidence**: Every commit has passing tests, so main branch is always working
- **Reviewability**: Small, focused commits are easier to review and understand

### Red-Green-Refactor Discipline

1. **RED**: Write a failing test
2. **GREEN**: Make it pass with minimal code
3. **REFACTOR**: Clean up while keeping tests green
4. **COMMIT**: Save your work

Never skip the RED step - always verify your test fails before implementing!

## CRITICAL: Avoid Overarchitecting

**Build only what is needed now, not what might be needed later.**

### Rules:
- **DO NOT** create infrastructure for future features that don't exist yet
- **DO NOT** add configuration options that aren't currently used
- **DO NOT** write helper functions before you have at least 2-3 call sites
- **DO** remove unused code immediately - don't keep it "just in case"
- **DO** wait until you have a concrete use case before adding abstractions

### Examples of Overarchitecting:

**Bad (infrastructure without users):**
```elixir
# These functions aren't used anywhere - delete them!
def root, do: Application.fetch_env!(:codicil, :root)
def git_root, do: Application.fetch_env!(:codicil, :git_root)
def project_name, do: Application.fetch_env!(:codicil, :project_name)

# Complex init_config setting up values that nothing reads
defp init_config do
  Application.put_env(:codicil, :root, File.cwd!())
  # ... more unused setup
end
```

**Good (minimal, focused code):**
```elixir
# Only add functions when you have actual callers
# Only add config when features need it
# Wait for concrete requirements before building infrastructure
```

### Why This Matters

- **Unused code is technical debt** - it must be maintained, understood, and kept working even though it provides no value
- **YAGNI (You Aren't Gonna Need It)** - most "future-proofing" code is never actually used
- **Requirements change** - when you do need the feature, your upfront infrastructure is often wrong anyway
- **Simplicity is valuable** - less code means less to understand, debug, and maintain

**Rule of thumb:** If removing code wouldn't break any tests, remove it.

## CRITICAL: Mix Module Usage

**NEVER call Mix functions at runtime.** The Mix module is only available during compilation and development, not in production releases.

### Rules:
- **DO NOT** call `Mix.env()` at runtime in function bodies
- **DO** use conditional compilation with `if Mix.env() == :test do` at module level to define different function implementations
- **DO NOT** call `Mix.Project.config()` or `Mix.Project.get()` at runtime
- **DO** capture Mix values at compile time using module attributes: `@version Mix.Project.config()[:version]`

### Why Runtime Mix Calls Fail

Mix is a **build tool**, not a runtime library. When you create a production release with `mix release`, Mix is not included in the release. Any runtime calls to Mix functions will crash your application in production.

### Examples:

**Bad (runtime Mix call):**
```elixir
def start(_type, _args) do
  if Mix.env() == :test do  # ❌ WRONG - Mix.env() called at runtime
    configure_test()
  end
  # ...
end
```

**Good (conditional compilation for different function implementations):**
```elixir
# Compile-time conditional: no-op in test, full logic in dev/prod
if Mix.env() == :test do
  defp configure_providers, do: :ok
else
  defp configure_providers do
    # Full configuration logic here
    llm_provider = System.fetch_env!("CODICIL_LLM_PROVIDER")
    # ...
  end
end

def start(_type, _args) do
  configure_providers()  # ✅ Calls the appropriate version based on compile-time env
  # ...
end
```

**Good (module attribute for version):**
```elixir
@version Mix.Project.config()[:version]  # ✅ Captured at compile time

def version, do: @version  # ✅ Returns compile-time value
```

### When to Use Each Pattern

1. **Conditional compilation** (`if Mix.env() == :test do ... end` at module level):
   - Use when you need **completely different implementations** in different environments
   - Example: No-op function in test, full logic in production
   - The condition is evaluated once at compile time, generating only the relevant code

2. **Module attributes** (`@version Mix.Project.config()[:version]`):
   - Use when you need a **compile-time constant** from Mix
   - Example: Application version, project config values
   - The value is captured once at compile time and embedded in the bytecode

3. **Application config** (from `config/*.exs` files):
   - **DO NOT USE for library code** - libraries don't have config files!
   - Only use in the host application that depends on the library
   - Libraries should use conditional compilation or module attributes instead

## Project Goal

**Spector** is an Elixir/Ecto based Event log system

**Key Features:**
- defines an eventlog

## Development Commands

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run a specific test file
mix test test/codicil_test.exs

# Run a specific test by line number
mix test test/codicil_test.exs:42

# Format code
mix format
```

## IMPORTANT: Library Configuration and Migrations

**This is a library, NOT an application - special rules apply:**

### Config Files (DO NOT CREATE)
- **NEVER** create `config/config.exs` or any config files in this project
- Libraries should not have runtime configuration files checked into source control
- Users configure Codicil in their own application's config
- If runtime configuration is needed, use application environment: `Application.get_env(:codicil, :key)`

### Testing with Database
- Tests handle Repo startup in `test/test_helper.exs`
- Use `Ecto.Adapters.SQL.Sandbox` for test isolation
- Each test gets its own transaction that rolls back automatically
- Migrations run automatically in test setup`
