# macSteam Management Suite

## Product contract

macSteam serves a macOS Steam user who wants one native place to understand library state, protect local saves, diagnose installation problems, and move configuration safely.

The product should let that user see what is installed, understand installation health and compatibility, create and restore local save backups safely, inspect privacy-safe logs, and export or import validated settings.

## Principles

- Discover first and keep discovery read-only.
- Make writes reversible and create a safety backup before overwriting data.
- Show explicit healthy, needs repair, unsupported, and missing states.
- Keep diagnostics and logs free of account data, credentials, and personal paths.
- Follow native macOS interaction and accessibility conventions.
- Remain useful as a library and support utility without the restricted core.

## Non-goals

This management suite does not implement or improve ownership spoofing, license injection, DRM removal, DLC unlocking, access-control bypasses, depot-key acquisition, manifests for unowned software, or any related circumvention.

## Success measures

- A fresh clone can build the config app using the documented dependency bootstrap.
- Health reports classify actionable states and export only redacted data.
- Installed-library discovery is read-only and tolerates partial or malformed Steam data.
- Every restore creates a safety backup and rejects unsafe paths and links.
- Operational logs are bounded, searchable, and redacted.
- Configuration import validates and previews changes before atomic replacement.
- Tests cover parsers, classification, redaction, path safety, backup recovery, retention, and configuration validation.

## Delivery order and verified status

1. Installation health and diagnostics: complete. Verified by unit tests, a clean release app build, and native accessibility smoke inspection on 2026-09-07.
2. Installed-game library: planned.
3. Local save backup and restore: planned.
4. Operational logging: planned.
5. Configuration portability: planned.

Only items explicitly marked complete after tests and a clean config-app build are implemented product behavior.
