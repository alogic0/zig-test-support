# Changelog

## 0.2.0

- Pin zig-process 0.6.1 to a GitHub revision and verified package hash.
- File-backed command reports with shared launch/execution deadlines and separate
  primary/cleanup failures; explicit append-safe Linux log creation.
- Atomic file/JSON writes with explicit replacement and failure cleanup.
- Streaming SHA-256, permissive JSON text extraction, explicit nonempty validation,
  sorted-key serialization and allocation-free structural equality.
- Preserve existing capture, workspace, readiness and string helper semantics.
- Check package consumption from an isolated source directory with a fresh cache.

## 0.1.0

- Bounded command reports, optional stdin and asynchronous joined capture owners.
- Bounded readiness lines/files retaining process/result ownership across races.
- Private workspaces with explicit cleanup and failure retention.
- Owned diagnostic excerpts preserving primary and secondary cleanup errors.
- Independent file, JSON, PNG-header and Linux resource helpers.
- Compiler 0.17.0; Linux provider support. Consumer adoption tracked separately.
