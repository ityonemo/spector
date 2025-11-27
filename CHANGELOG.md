# Changelog

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
