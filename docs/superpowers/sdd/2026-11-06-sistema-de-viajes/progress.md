# SDD ledger — plan: docs/superpowers/plans/2026-11-06-sistema-de-viajes.md

## Setup

- Spec: `specs/viajes-sdd-spec.md` is present and approved.
- Plan: `docs/superpowers/plans/2026-11-06-sistema-de-viajes.md` is approved for Native execution.
- Workspace preflight: directory is not a Git repository; `git rev-parse --show-toplevel` and the SDD workspace script fail. No worktree or commits are available. Work remains inside the user-authorized project directory.
- Scope ruling: no automated tests will be added or run; the current developer instruction prohibits tests unless the user explicitly asks for testing/verification. The requested SQL sample data is still in scope.

## Pre-flight shared interfaces

- Task 1 → Task 2: schema must expose normalized user identifiers, trip start/end timestamps, trip status and release flag; Task 2 adds unique and overlap constraints to those columns. Found compatible; implement those field names consistently.
- Task 1 → Task 3: schema must expose settings, weekly/date unavailability, trips, and geographic boundary tables. Task 3 functions consume those. Found compatible; choose and document exact field names in SQL README.
- Task 2 → Task 3: exclusion constraint handles blocking intervals while SQL functions make all transitions transactional. Found compatible; keep both as defense in depth.
- Task 1/3 → Task 4: Task 3's geofence function reads the municipality boundary table created in Task 1 and loaded by Task 4. Found compatible; define function before boundary seed execution.
- Task 1 → Task 5: sample data depends on final table constraints and status values. Found compatible; keep the seed optional and development-only.
- Task 1–5 → Task 6–11: application data access depends on completed schema/functions. Found compatible; do not scaffold the app before Fase 1 SQL artifacts are complete.

## Rulings

- Ruling: work in the authorized project directory without a Git worktree — the workspace has no Git repository and the worktree script cannot run; cost if wrong: less isolation and no commit-based rollback.
- Ruling: no test files or test commands — higher-priority collaboration instructions prohibit adding/running tests unless explicitly requested; cost if wrong: SQL and app behavior will have less automated verification.
- Ruling: generate a continuous sequence of candidate starts from local midnight at the current window's first date, spaced by the configured duration, then filter any start whose trip interval overlaps a blocked interval — this honors exact spacing for any positive integer-minute duration; cost if wrong: for durations that do not divide 24 hours, the displayed start times shift across dates and advance when the rolling window's first date changes.
- Ruling: represent the sole driver's capacity with a fixed internal `resource_key = 1` in trip rows — `btree_gist` exclusion uses a key plus the time range to serialize the one-driver schedule without introducing a user-facing driver assignment feature; cost if wrong: future multi-driver support will require replacing the singleton constraint and reservation model.

## Task status

Tasks 1–11: implemented in the approved Native workspace.

## Implementation record

- Phase 1: created ordered SQL scripts for extensions, schema, indexes/exclusion, domain/auth/availability/quota functions, status email trigger, admin email bootstrap, nine official AMG municipal polygons, and synthetic development data. Added the standard-library SHP/DBF converter and data attribution.
- Phase 2: created the Next.js/TypeScript app, PostgreSQL pool, authentication and role checks, passenger registration/email verification/password login and reset, admin bootstrap, monthly calendar and booking, optional Google Maps location selection with server-side AMG validation, admin trip state actions, recurring/date unavailability editor, duration configuration, email outbox, quota controls, and authenticated queue worker endpoint.
- Added setup, SMTP/Google Maps, backup, and operation documentation; updated the approved SDD specification state and implementation checklist.
- The SQL has not been installed against a project PostgreSQL instance and the app has not been started because no target database/server credentials are configured. No automated tests/build commands were run, in line with the active instruction not to add/run tests unless requested.

- Cambio posterior aprobado: mapas/geocodificación desactivados por costos; origen/destino se capturan como texto opcional y el administrador revisa manualmente la zona AMG. Añadidos API/SQL y migración `database/07_text_only_addresses.sql`.
