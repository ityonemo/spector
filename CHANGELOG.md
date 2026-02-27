# Changelog

## 0.8.0

### New Features
- `prepare_materialization/1` optional callback - runs on the final changeset just before `Repo.insert/update`, useful for setting associations via `put_assoc`
- Added `telemetry` as an explicit dependency

### Fixes
- `materialize/2` now raises `ArgumentError` if called with an embedded schema

## 0.7.0

### New Features
- `Spector.materialize/2` - takes events module and parent_id, replays events and inserts the resulting record into the database

### Fixes
- Fixed `verify_hash_chain/1` docstring to correctly state ordering is by `inserted_at` (not `id`)

## 0.6.0

### Savepoints
- `savepoint/2` callback for capturing full record state at a point in time
- `Spector.savepoint/1` and `Spector.savepoint/2` to create savepoint events
- Replay optimization: starts from most recent savepoint instead of beginning
- `Spector.Integrity.verify_savepoints/2` to verify savepoint correctness

### Integrity Verification
- `Spector.Integrity` module for event log verification
- `Spector.Integrity.verify_hash_chain/1` to verify hash chain integrity
- Deterministic JSON encoding with sorted keys for consistent hashing

### Link Tables
- Typed link tables with schema module support for custom fields on links
- Sharding support for link tables
- Database trigger to enforce `parent_id` constraint on links

### API Improvements
- `Spector.get_attr/2`, `Spector.fetch_attr/2`, `Spector.fetch_attr!/2` helpers for accessing attrs
- Moved `all_events/2` and `all_record_ids/1` from Events module to `Spector`
- Events table now has `updated_at: false` (events are immutable)
- Insert sets both `inserted_at` and `updated_at`; execute/update sets `updated_at`
- Added index on `events.inserted_at` for ordering queries

## 0.5.0

- `Spector.bringup/2` now accepts keyword options instead of positional arguments
  - `:action` - The action to use for events (default: `:insert`)
  - `:attr_fn` - Function to transform record attributes
  - `:transfer` - Function to update associations before old record deletion
- Added typespecs to all public Spector functions

## 0.4.0

- `Spector.bringup/3` to import existing database records into event log
- `event_log/1` macro to create has_many association for accessing record events
- Custom primary key support for Evented schemas (override `@primary_key`)
- Compile-time validation that Evented schema primary keys are binary type

## 0.3.0

- `__event_id__` reserved attribute passed to changesets for tracking event IDs
- `Spector.changeset_put_event_id/3` helper to assign event ID to a changeset field
- Documentation for reserved attributes (`__version__` and `__event_id__`)
- Fixed event ordering to use `inserted_at` timestamp for reliable chronological order
- Added guides for building chat applications (AI chat with branching, basic chat with edit history)

## 0.2.0

- Event links for many-to-many relationships between events (e.g., tree/ancestry tracking)
- `prepare_event/3` optional callback for modifying events before insertion
- Embedded schema support (schemas without database tables)
- `Spector.get/2` to retrieve current state by parent ID
- Table sharding support for event logs
- Renamed version field to `__version__` in attrs

## 0.1.0

- Event sourcing for Ecto schemas with full audit trail
- Event log table using UUIDv7 for ordering and uniqueness
- Roll-forward state reconstruction from event history
- Custom actions beyond insert/update/delete
- Schema versioning with `version_is/2` and `version_in/2` guards
- Hash chain integrity for tamper-evident event logs
- Action aliases for backwards-compatible refactoring
- Explicit schema indexing for stable storage
- Per-schema repo configuration
- Migration helpers via `Spector.Migration`
