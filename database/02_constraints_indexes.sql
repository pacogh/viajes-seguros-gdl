-- Índices y restricciones de unicidad/ocupación.
-- Requiere database/00_extensions.sql y database/01_schema.sql.

CREATE UNIQUE INDEX IF NOT EXISTS users_email_normalized_uq
    ON viajes.users (email_normalized);

CREATE UNIQUE INDEX IF NOT EXISTS users_phone_e164_uq
    ON viajes.users (phone_e164);

CREATE UNIQUE INDEX IF NOT EXISTS users_single_admin_uq
    ON viajes.users ((role))
    WHERE role = 'admin';

CREATE INDEX IF NOT EXISTS auth_email_tokens_live_idx
    ON viajes.auth_email_tokens (user_id, purpose, expires_at)
    WHERE consumed_at IS NULL;

CREATE INDEX IF NOT EXISTS sessions_active_user_idx
    ON viajes.sessions (user_id, expires_at)
    WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS weekly_unavailability_active_idx
    ON viajes.weekly_unavailability (weekday, start_minute, end_minute)
    WHERE active;

CREATE INDEX IF NOT EXISTS date_unavailability_active_range_idx
    ON viajes.date_unavailability
    USING gist (tstzrange(starts_at, ends_at, '[)'))
    WHERE active;

CREATE INDEX IF NOT EXISTS trips_passenger_start_idx
    ON viajes.trips (passenger_id, starts_at DESC);

CREATE INDEX IF NOT EXISTS trips_status_start_idx
    ON viajes.trips (status, starts_at);

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'trips_one_driver_no_overlap'
          AND conrelid = 'viajes.trips'::regclass
    ) THEN
        ALTER TABLE viajes.trips
            ADD CONSTRAINT trips_one_driver_no_overlap
            EXCLUDE USING gist (
                resource_key WITH =,
                tstzrange(starts_at, ends_at, '[)') WITH &&
            )
            WHERE (slot_blocking);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS amg_municipalities_geom_gist_idx
    ON viajes.amg_municipalities USING gist (geom);

CREATE INDEX IF NOT EXISTS email_outbox_ready_idx
    ON viajes.email_outbox (available_at, queued_at)
    WHERE status IN ('queued', 'failed');

