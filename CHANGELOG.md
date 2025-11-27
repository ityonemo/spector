# Changelog

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
