-- Esquema relacional del sistema de viajes.
-- Requiere database/00_extensions.sql.

CREATE SCHEMA IF NOT EXISTS viajes;

DO $$ BEGIN
    CREATE TYPE viajes.account_role AS ENUM ('passenger', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE viajes.account_status AS ENUM ('pending_email', 'active', 'disabled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE viajes.trip_status AS ENUM (
        'pending', 'confirmed', 'rejected', 'cancelled_by_passenger', 'cancelled_by_admin'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE viajes.email_token_purpose AS ENUM ('verify_email', 'reset_password');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE viajes.email_outbox_status AS ENUM ('queued', 'sending', 'sent', 'failed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS viajes.app_settings (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    local_timezone text NOT NULL DEFAULT 'America/Mexico_City',
    booking_months_ahead integer NOT NULL DEFAULT 2 CHECK (booking_months_ahead = 2),
    trip_duration_minutes integer NOT NULL DEFAULT 60 CHECK (trip_duration_minutes > 0),
    initial_admin_email text,
    admin_claimed_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT app_settings_admin_email_normalized CHECK (
        initial_admin_email IS NULL OR initial_admin_email = lower(btrim(initial_admin_email))
    )
);

INSERT INTO viajes.app_settings (singleton)
VALUES (true)
ON CONFLICT (singleton) DO NOTHING;

CREATE TABLE IF NOT EXISTS viajes.users (
    user_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name text NOT NULL CHECK (length(btrim(full_name)) BETWEEN 1 AND 160),
    email text NOT NULL CHECK (length(btrim(email)) BETWEEN 3 AND 320),
    email_normalized text GENERATED ALWAYS AS (lower(btrim(email))) STORED,
    phone_e164 text NOT NULL CHECK (phone_e164 ~ '^\+52[0-9]{10}$'),
    password_hash text NOT NULL,
    role viajes.account_role NOT NULL DEFAULT 'passenger',
    account_status viajes.account_status NOT NULL DEFAULT 'pending_email',
    email_verified_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    disabled_at timestamptz,
    CONSTRAINT users_admin_email_unverified_ok CHECK (
        role = 'passenger' OR account_status <> 'pending_email'
    )
);

CREATE TABLE IF NOT EXISTS viajes.auth_email_tokens (
    token_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES viajes.users(user_id) ON DELETE CASCADE,
    token_hash char(64) NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    purpose viajes.email_token_purpose NOT NULL,
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS viajes.sessions (
    session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES viajes.users(user_id) ON DELETE CASCADE,
    token_hash char(64) NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    last_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS viajes.auth_login_attempts (
    identifier_hash char(64) PRIMARY KEY CHECK (identifier_hash ~ '^[0-9a-f]{64}$'),
    failed_count integer NOT NULL DEFAULT 0 CHECK (failed_count >= 0),
    window_started_at timestamptz NOT NULL DEFAULT now(),
    blocked_until timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Unavailability is expressed as local minutes after midnight; a block spanning
-- midnight is represented by two rules, one for each weekday.
CREATE TABLE IF NOT EXISTS viajes.weekly_unavailability (
    rule_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    weekday smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
    start_minute smallint NOT NULL DEFAULT 0 CHECK (start_minute BETWEEN 0 AND 1439),
    end_minute smallint NOT NULL DEFAULT 1440 CHECK (end_minute BETWEEN 1 AND 1440),
    effective_from date,
    effective_through date,
    reason text,
    active boolean NOT NULL DEFAULT true,
    created_by uuid NOT NULL REFERENCES viajes.users(user_id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT weekly_unavailability_valid_range CHECK (start_minute < end_minute),
    CONSTRAINT weekly_unavailability_effective_range CHECK (
        effective_from IS NULL OR effective_through IS NULL OR effective_from <= effective_through
    )
);

CREATE TABLE IF NOT EXISTS viajes.date_unavailability (
    unavailability_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    reason text,
    active boolean NOT NULL DEFAULT true,
    created_by uuid NOT NULL REFERENCES viajes.users(user_id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT date_unavailability_valid_range CHECK (starts_at < ends_at)
);

CREATE TABLE IF NOT EXISTS viajes.amg_municipalities (
    municipality_code text PRIMARY KEY CHECK (municipality_code ~ '^14[0-9]{3}$'),
    municipality_name text NOT NULL UNIQUE,
    geom geometry(MultiPolygon, 4326) NOT NULL,
    source_name text NOT NULL DEFAULT 'IIEG Jalisco — Límite Municipal Jalisco IIEG',
    source_srid integer NOT NULL DEFAULT 6368,
    source_updated_at date,
    imported_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT amg_municipalities_valid_geom CHECK (ST_IsValid(geom))
);

CREATE TABLE IF NOT EXISTS viajes.trips (
    trip_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_key smallint NOT NULL DEFAULT 1 CHECK (resource_key = 1),
    passenger_id uuid NOT NULL REFERENCES viajes.users(user_id),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    duration_minutes integer NOT NULL CHECK (duration_minutes > 0),
    status viajes.trip_status NOT NULL DEFAULT 'pending',
    slot_blocking boolean NOT NULL DEFAULT true,
    slot_released_at timestamptz,
    origin_address text,
    origin_geom geometry(Point, 4326),
    origin_municipality_code text REFERENCES viajes.amg_municipalities(municipality_code),
    destination_address text,
    destination_geom geometry(Point, 4326),
    destination_municipality_code text REFERENCES viajes.amg_municipalities(municipality_code),
    admin_note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    decided_at timestamptz,
    cancelled_at timestamptz,
    CONSTRAINT trips_duration_matches_range CHECK (
        ends_at = starts_at + make_interval(mins => duration_minutes)
    ),
    CONSTRAINT trips_origin_fields_together CHECK (
        (origin_address IS NULL AND origin_geom IS NULL AND origin_municipality_code IS NULL)
        OR (nullif(btrim(origin_address), '') IS NOT NULL AND ((origin_geom IS NULL AND origin_municipality_code IS NULL) OR (origin_geom IS NOT NULL AND origin_municipality_code IS NOT NULL)))
    ),
    CONSTRAINT trips_destination_fields_together CHECK (
        (destination_address IS NULL AND destination_geom IS NULL AND destination_municipality_code IS NULL)
        OR (nullif(btrim(destination_address), '') IS NOT NULL AND ((destination_geom IS NULL AND destination_municipality_code IS NULL) OR (destination_geom IS NOT NULL AND destination_municipality_code IS NOT NULL)))
    ),
    CONSTRAINT trips_origin_geom_srid CHECK (origin_geom IS NULL OR ST_SRID(origin_geom) = 4326),
    CONSTRAINT trips_destination_geom_srid CHECK (destination_geom IS NULL OR ST_SRID(destination_geom) = 4326),
    CONSTRAINT trips_slot_state_matches_status CHECK (
        (status IN ('pending', 'confirmed') AND slot_blocking AND slot_released_at IS NULL)
        OR (status IN ('rejected', 'cancelled_by_passenger') AND NOT slot_blocking AND slot_released_at IS NULL)
        OR (status = 'cancelled_by_admin' AND (
            (slot_blocking AND slot_released_at IS NULL)
            OR (NOT slot_blocking AND slot_released_at IS NOT NULL)
        ))
    )
);

CREATE TABLE IF NOT EXISTS viajes.email_outbox (
    email_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id uuid REFERENCES viajes.trips(trip_id) ON DELETE SET NULL,
    user_id uuid REFERENCES viajes.users(user_id) ON DELETE SET NULL,
    recipient text NOT NULL,
    template_key text NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    status viajes.email_outbox_status NOT NULL DEFAULT 'queued',
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    last_error text,
    queued_at timestamptz NOT NULL DEFAULT now(),
    available_at timestamptz NOT NULL DEFAULT now(),
    sent_at timestamptz
);

CREATE TABLE IF NOT EXISTS viajes.email_quota_usage (
    window_kind text NOT NULL CHECK (window_kind IN ('day', 'month')),
    window_start timestamptz NOT NULL,
    send_count integer NOT NULL DEFAULT 0 CHECK (send_count >= 0),
    send_cap integer NOT NULL CHECK (send_cap > 0),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (window_kind, window_start)
);

