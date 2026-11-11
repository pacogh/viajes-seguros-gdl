-- Funciones transaccionales y de dominio.
-- Requiere database/00_extensions.sql, 01_schema.sql y 02_constraints_indexes.sql.

CREATE OR REPLACE FUNCTION viajes.is_point_in_amg(p_point geometry(Point, 4326))
RETURNS TABLE (is_allowed boolean, municipality_name text, municipality_code text)
LANGUAGE sql
STABLE
AS $$
    SELECT
        EXISTS (
            SELECT 1
            FROM viajes.amg_municipalities m
            WHERE ST_Covers(m.geom, p_point)
        ),
        (
            SELECT m.municipality_name
            FROM viajes.amg_municipalities m
            WHERE ST_Covers(m.geom, p_point)
            ORDER BY m.municipality_name
            LIMIT 1
        ),
        (
            SELECT m.municipality_code
            FROM viajes.amg_municipalities m
            WHERE ST_Covers(m.geom, p_point)
            ORDER BY m.municipality_name
            LIMIT 1
        );
$$;

CREATE OR REPLACE FUNCTION viajes.register_passenger(
    p_name text, p_email text, p_phone_e164 text, p_password_hash text
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_admin_email text;
BEGIN
    SELECT initial_admin_email INTO v_admin_email
    FROM viajes.app_settings WHERE singleton FOR SHARE;
    IF lower(btrim(p_email)) = v_admin_email THEN
        RAISE EXCEPTION 'Email is reserved for the initial administrator';
    END IF;
    INSERT INTO viajes.users(full_name,email,phone_e164,password_hash,role,account_status)
    VALUES(p_name,p_email,p_phone_e164,p_password_hash,'passenger','pending_email')
    RETURNING user_id INTO v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.get_available_slots(
    p_from date,
    p_through date,
    p_now timestamptz DEFAULT now()
)
RETURNS TABLE (slot_start timestamptz, slot_end timestamptz)
LANGUAGE sql
STABLE
AS $$
    WITH cfg AS (
        SELECT
            s.local_timezone,
            s.trip_duration_minutes,
            (p_now AT TIME ZONE s.local_timezone)::date AS today_local,
            (
                date_trunc('month', (p_now AT TIME ZONE s.local_timezone) + interval '2 months')
                + interval '1 month - 1 day'
            )::date AS last_bookable_day
        FROM viajes.app_settings s
        WHERE s.singleton
    ), bounds AS (
        SELECT
            c.*,
            GREATEST(p_from, c.today_local) AS first_day,
            LEAST(p_through, c.last_bookable_day) AS last_day,
            ((c.today_local)::timestamp AT TIME ZONE c.local_timezone) AS grid_anchor
        FROM cfg c
    ), candidates AS (
        SELECT
            g.slot_start,
            g.slot_start + make_interval(mins => b.trip_duration_minutes) AS slot_end,
            b.local_timezone
        FROM bounds b
        CROSS JOIN LATERAL generate_series(
            b.grid_anchor,
            (((b.last_day + 1)::timestamp AT TIME ZONE b.local_timezone) - interval '1 microsecond'),
            make_interval(mins => b.trip_duration_minutes)
        ) AS g(slot_start)
        WHERE b.first_day <= b.last_day
          AND g.slot_start > p_now
          AND (g.slot_start AT TIME ZONE b.local_timezone)::date BETWEEN b.first_day AND b.last_day
    )
    SELECT c.slot_start, c.slot_end
    FROM candidates c
    WHERE NOT EXISTS (
        SELECT 1
        FROM viajes.trips t
        WHERE t.slot_blocking
          AND tstzrange(t.starts_at, t.ends_at, '[)') && tstzrange(c.slot_start, c.slot_end, '[)')
    )
    AND NOT EXISTS (
        SELECT 1
        FROM viajes.date_unavailability u
        WHERE u.active
          AND tstzrange(u.starts_at, u.ends_at, '[)') && tstzrange(c.slot_start, c.slot_end, '[)')
    )
    AND NOT EXISTS (
        SELECT 1
        FROM generate_series(
            (c.slot_start AT TIME ZONE c.local_timezone)::date::timestamp,
            ((c.slot_end - interval '1 microsecond') AT TIME ZONE c.local_timezone)::date::timestamp,
            interval '1 day'
        ) AS local_days(local_day)
        JOIN viajes.weekly_unavailability u
          ON u.active
         AND u.weekday = extract(dow FROM local_days.local_day)::smallint
         AND (u.effective_from IS NULL OR local_days.local_day::date >= u.effective_from)
         AND (u.effective_through IS NULL OR local_days.local_day::date <= u.effective_through)
        WHERE tstzrange(c.slot_start, c.slot_end, '[)') && tstzrange(
            ((local_days.local_day::date::timestamp + make_interval(mins => u.start_minute)) AT TIME ZONE c.local_timezone),
            ((local_days.local_day::date::timestamp + make_interval(mins => u.end_minute)) AT TIME ZONE c.local_timezone),
            '[)'
        )
    )
    ORDER BY c.slot_start;
$$;

CREATE OR REPLACE FUNCTION viajes.create_trip_request(
    p_user_id uuid,
    p_start timestamptz,
    p_origin_address text DEFAULT NULL,
    p_origin geometry(Point, 4326) DEFAULT NULL,
    p_destination_address text DEFAULT NULL,
    p_destination geometry(Point, 4326) DEFAULT NULL
)
RETURNS TABLE (trip_id uuid, status text)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user viajes.users%ROWTYPE;
    v_duration integer;
    v_end timestamptz;
    v_start_municipality text;
    v_start_code text;
    v_end_municipality text;
    v_end_code text;
    v_origin_address text;
    v_destination_address text;
    v_trip_id uuid;
BEGIN
    SELECT * INTO v_user
    FROM viajes.users u
    WHERE u.user_id = p_user_id
      AND u.role = 'passenger'
      AND u.account_status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Passenger account is not active';
    END IF;

    IF p_start IS NULL THEN
        RAISE EXCEPTION 'Trip start is required';
    END IF;

    v_origin_address := nullif(btrim(p_origin_address), '');
    v_destination_address := nullif(btrim(p_destination_address), '');

    IF p_origin IS NOT NULL AND v_origin_address IS NULL THEN
        RAISE EXCEPTION 'Origin address is required when a map point is supplied';
    END IF;
    IF p_destination IS NOT NULL AND v_destination_address IS NULL THEN
        RAISE EXCEPTION 'Destination address is required when a map point is supplied';
    END IF;

    IF p_origin IS NOT NULL THEN
        SELECT g.municipality_name, g.municipality_code
        INTO v_start_municipality, v_start_code
        FROM viajes.is_point_in_amg(p_origin) g
        WHERE g.is_allowed;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Origin is outside the approved service area';
        END IF;
    END IF;

    IF p_destination IS NOT NULL THEN
        SELECT g.municipality_name, g.municipality_code
        INTO v_end_municipality, v_end_code
        FROM viajes.is_point_in_amg(p_destination) g
        WHERE g.is_allowed;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Destination is outside the approved service area';
        END IF;
    END IF;

    -- Serializa la creación frente a un cambio de duración del administrador.
    PERFORM 1 FROM viajes.app_settings WHERE singleton FOR SHARE;
    SELECT s.trip_duration_minutes INTO v_duration
    FROM viajes.app_settings s
    WHERE s.singleton;
    v_end := p_start + make_interval(mins => v_duration);

    IF NOT EXISTS (
        SELECT 1
        FROM viajes.get_available_slots(
            (p_start AT TIME ZONE 'America/Mexico_City')::date,
            (p_start AT TIME ZONE 'America/Mexico_City')::date,
            now()
        ) a
        WHERE a.slot_start = p_start
          AND a.slot_end = v_end
    ) THEN
        RAISE EXCEPTION 'Selected trip interval is unavailable';
    END IF;

    INSERT INTO viajes.trips AS t (
        passenger_id,
        starts_at,
        ends_at,
        duration_minutes,
        status,
        slot_blocking,
        origin_address,
        origin_geom,
        origin_municipality_code,
        destination_address,
        destination_geom,
        destination_municipality_code
    )
    VALUES (
        p_user_id,
        p_start,
        v_end,
        v_duration,
        'pending',
        true,
        v_origin_address,
        p_origin,
        v_start_code,
        v_destination_address,
        p_destination,
        v_end_code
    )
    RETURNING t.trip_id INTO v_trip_id;

    RETURN QUERY SELECT v_trip_id, 'pending'::text;
EXCEPTION WHEN exclusion_violation THEN
    RAISE EXCEPTION 'Selected trip interval was just reserved by another request'
        USING ERRCODE = '23P01';
END;
$$;

CREATE OR REPLACE FUNCTION viajes.set_trip_duration(p_minutes integer, p_admin_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin viajes.users%ROWTYPE;
BEGIN
    IF p_minutes IS NULL OR p_minutes <= 0 THEN
        RAISE EXCEPTION 'Duration must be a positive whole number of minutes';
    END IF;

    SELECT * INTO v_admin
    FROM viajes.users u
    WHERE u.user_id = p_admin_id
      AND u.role = 'admin'
      AND u.account_status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Administrator account is not active';
    END IF;

    PERFORM 1 FROM viajes.app_settings WHERE singleton FOR UPDATE;

    BEGIN
        UPDATE viajes.trips
        SET duration_minutes = p_minutes,
            ends_at = starts_at + make_interval(mins => p_minutes),
            updated_at = now()
        WHERE status IN ('pending', 'confirmed');

        UPDATE viajes.app_settings
        SET trip_duration_minutes = p_minutes,
            updated_at = now()
        WHERE singleton;
    EXCEPTION WHEN exclusion_violation THEN
        RAISE EXCEPTION 'Duration change would create overlapping trips; resolve conflicts first'
            USING ERRCODE = '23P01';
    END;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.confirm_trip(p_trip_id uuid, p_admin_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM viajes.users
        WHERE user_id = p_admin_id AND role = 'admin' AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'Administrator account is not active';
    END IF;

    UPDATE viajes.trips
    SET status = 'confirmed', decided_at = now(), updated_at = now()
    WHERE trip_id = p_trip_id AND status = 'pending' AND slot_blocking;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Only a pending trip can be confirmed';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.reject_trip(p_trip_id uuid, p_admin_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM viajes.users
        WHERE user_id = p_admin_id AND role = 'admin' AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'Administrator account is not active';
    END IF;

    UPDATE viajes.trips
    SET status = 'rejected', slot_blocking = false, decided_at = now(), updated_at = now()
    WHERE trip_id = p_trip_id AND status = 'pending' AND slot_blocking;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Only a pending trip can be rejected';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.cancel_pending_trip(p_trip_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE viajes.trips
    SET status = 'cancelled_by_passenger', slot_blocking = false,
        cancelled_at = now(), updated_at = now()
    WHERE trip_id = p_trip_id
      AND passenger_id = p_user_id
      AND status = 'pending'
      AND slot_blocking;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Only the passenger can cancel their own pending trip';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.cancel_confirmed_trip(p_trip_id uuid, p_admin_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM viajes.users
        WHERE user_id = p_admin_id AND role = 'admin' AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'Administrator account is not active';
    END IF;

    UPDATE viajes.trips
    SET status = 'cancelled_by_admin', slot_blocking = true,
        cancelled_at = now(), updated_at = now()
    WHERE trip_id = p_trip_id AND status = 'confirmed' AND slot_blocking;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Only a confirmed trip can be cancelled by the administrator';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.release_admin_cancelled_trip(p_trip_id uuid, p_admin_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM viajes.users
        WHERE user_id = p_admin_id AND role = 'admin' AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'Administrator account is not active';
    END IF;

    UPDATE viajes.trips
    SET slot_blocking = false, slot_released_at = now(), updated_at = now()
    WHERE trip_id = p_trip_id AND status = 'cancelled_by_admin' AND slot_blocking;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Only a blocked administrator-cancelled trip can be released';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.claim_initial_admin(
    p_name text,
    p_email text,
    p_phone_e164 text,
    p_password_hash text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_settings viajes.app_settings%ROWTYPE;
    v_user_id uuid;
BEGIN
    SELECT * INTO v_settings
    FROM viajes.app_settings
    WHERE singleton
    FOR UPDATE;

    IF v_settings.initial_admin_email IS NULL THEN
        RAISE EXCEPTION 'Initial administrator email is not configured';
    END IF;
    IF v_settings.admin_claimed_at IS NOT NULL OR EXISTS (
        SELECT 1 FROM viajes.users WHERE role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Initial administrator has already been claimed';
    END IF;
    IF lower(btrim(p_email)) <> v_settings.initial_admin_email THEN
        RAISE EXCEPTION 'Email does not match the configured initial administrator';
    END IF;
    IF p_phone_e164 !~ '^\+52[0-9]{10}$' THEN
        RAISE EXCEPTION 'Phone must be a Mexican E.164 number';
    END IF;

    INSERT INTO viajes.users (
        full_name, email, phone_e164, password_hash, role, account_status
    ) VALUES (
        p_name, p_email, p_phone_e164, p_password_hash, 'admin', 'active'
    ) RETURNING user_id INTO v_user_id;

    UPDATE viajes.app_settings
    SET admin_claimed_at = now(), updated_at = now()
    WHERE singleton;

    RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.add_weekly_unavailability(
    p_weekday smallint,
    p_start_minute smallint,
    p_end_minute smallint,
    p_admin_id uuid,
    p_reason text DEFAULT NULL,
    p_effective_from date DEFAULT NULL,
    p_effective_through date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_rule_id uuid;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM viajes.users
        WHERE user_id = p_admin_id AND role = 'admin' AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'Administrator account is not active';
    END IF;

    INSERT INTO viajes.weekly_unavailability (
        weekday, start_minute, end_minute, reason, effective_from, effective_through, created_by
    ) VALUES (
        p_weekday, p_start_minute, p_end_minute, nullif(btrim(p_reason), ''),
        p_effective_from, p_effective_through, p_admin_id
    ) RETURNING rule_id INTO v_rule_id;

    RETURN v_rule_id;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.disable_weekly_unavailability(p_rule_id uuid, p_admin_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM viajes.users
        WHERE user_id = p_admin_id AND role = 'admin' AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'Administrator account is not active';
    END IF;

    UPDATE viajes.weekly_unavailability
    SET active = false, updated_at = now()
    WHERE rule_id = p_rule_id AND active;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Weekly unavailability rule was not found or is already disabled';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.add_date_unavailability(
    p_starts_at timestamptz,
    p_ends_at timestamptz,
    p_admin_id uuid,
    p_reason text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_unavailability_id uuid;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM viajes.users
        WHERE user_id = p_admin_id AND role = 'admin' AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'Administrator account is not active';
    END IF;

    INSERT INTO viajes.date_unavailability (starts_at, ends_at, reason, created_by)
    VALUES (p_starts_at, p_ends_at, nullif(btrim(p_reason), ''), p_admin_id)
    RETURNING unavailability_id INTO v_unavailability_id;

    RETURN v_unavailability_id;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.disable_date_unavailability(p_id uuid, p_admin_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM viajes.users
        WHERE user_id = p_admin_id AND role = 'admin' AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'Administrator account is not active';
    END IF;

    UPDATE viajes.date_unavailability
    SET active = false, updated_at = now()
    WHERE unavailability_id = p_id AND active;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Date unavailability was not found or is already disabled';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.reserve_email_quota(
    p_at timestamptz,
    p_daily_cap integer,
    p_monthly_cap integer
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_tz text;
    v_day_start timestamptz;
    v_month_start timestamptz;
    v_day_count integer;
    v_month_count integer;
BEGIN
    IF p_daily_cap <= 0 OR p_monthly_cap <= 0 THEN
        RAISE EXCEPTION 'Email quota caps must be positive';
    END IF;

    SELECT local_timezone INTO v_tz
    FROM viajes.app_settings WHERE singleton;

    v_day_start := ((p_at AT TIME ZONE v_tz)::date::timestamp AT TIME ZONE v_tz);
    v_month_start := (date_trunc('month', p_at AT TIME ZONE v_tz) AT TIME ZONE v_tz);

    INSERT INTO viajes.email_quota_usage (window_kind, window_start, send_count, send_cap)
    VALUES ('day', v_day_start, 0, p_daily_cap), ('month', v_month_start, 0, p_monthly_cap)
    ON CONFLICT (window_kind, window_start) DO NOTHING;

    SELECT send_count INTO v_day_count
    FROM viajes.email_quota_usage
    WHERE window_kind = 'day' AND window_start = v_day_start
    FOR UPDATE;

    SELECT send_count INTO v_month_count
    FROM viajes.email_quota_usage
    WHERE window_kind = 'month' AND window_start = v_month_start
    FOR UPDATE;

    IF v_day_count >= p_daily_cap OR v_month_count >= p_monthly_cap THEN
        RETURN false;
    END IF;

    UPDATE viajes.email_quota_usage
    SET send_count = send_count + 1, send_cap = LEAST(send_cap, p_daily_cap), updated_at = now()
    WHERE window_kind = 'day' AND window_start = v_day_start;

    UPDATE viajes.email_quota_usage
    SET send_count = send_count + 1, send_cap = LEAST(send_cap, p_monthly_cap), updated_at = now()
    WHERE window_kind = 'month' AND window_start = v_month_start;

    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION viajes.is_login_allowed(p_identifier_hash char(64))
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT NOT EXISTS (
        SELECT 1 FROM viajes.auth_login_attempts a
        WHERE a.identifier_hash = p_identifier_hash AND a.blocked_until > now()
    );
$$;

CREATE OR REPLACE FUNCTION viajes.record_login_failure(
    p_identifier_hash char(64), p_limit integer, p_window_minutes integer
)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE v_attempt viajes.auth_login_attempts%ROWTYPE;
BEGIN
    IF p_limit < 1 OR p_window_minutes < 1 THEN RAISE EXCEPTION 'Rate limit configuration must be positive'; END IF;
    INSERT INTO viajes.auth_login_attempts(identifier_hash, failed_count, window_started_at, updated_at)
    VALUES (p_identifier_hash, 1, now(), now())
    ON CONFLICT (identifier_hash) DO UPDATE SET
        failed_count = CASE WHEN viajes.auth_login_attempts.window_started_at < now() - make_interval(mins => p_window_minutes) THEN 1 ELSE viajes.auth_login_attempts.failed_count + 1 END,
        window_started_at = CASE WHEN viajes.auth_login_attempts.window_started_at < now() - make_interval(mins => p_window_minutes) THEN now() ELSE viajes.auth_login_attempts.window_started_at END,
        blocked_until = CASE WHEN (CASE WHEN viajes.auth_login_attempts.window_started_at < now() - make_interval(mins => p_window_minutes) THEN 1 ELSE viajes.auth_login_attempts.failed_count + 1 END) >= p_limit THEN now() + make_interval(mins => p_window_minutes) ELSE NULL END,
        updated_at = now();
    SELECT * INTO v_attempt FROM viajes.auth_login_attempts WHERE identifier_hash = p_identifier_hash;
    RETURN v_attempt.blocked_until IS NOT NULL AND v_attempt.blocked_until > now();
END;
$$;

CREATE OR REPLACE FUNCTION viajes.clear_login_failures(p_identifier_hash char(64))
RETURNS void LANGUAGE sql AS $$
    DELETE FROM viajes.auth_login_attempts WHERE identifier_hash = p_identifier_hash;
$$;

