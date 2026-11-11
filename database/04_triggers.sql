-- Encola notificaciones de viajes dentro de la misma transacción que el cambio.
-- El envío real ocurre fuera de PostgreSQL mediante el proceso de aplicación.
CREATE OR REPLACE FUNCTION viajes.enqueue_trip_status_email()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_template text;
    v_user_id uuid;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'pending' THEN RETURN NEW; END IF;
        v_template := 'trip_pending';
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        v_template := CASE NEW.status
            WHEN 'confirmed' THEN 'trip_confirmed'
            WHEN 'rejected' THEN 'trip_rejected'
            WHEN 'cancelled_by_passenger' THEN 'trip_cancelled_by_passenger'
            WHEN 'cancelled_by_admin' THEN 'trip_cancelled_by_admin'
            ELSE NULL
        END;
    ELSE
        RETURN NEW;
    END IF;

    IF v_template IS NOT NULL THEN
        SELECT user_id INTO v_user_id FROM viajes.users WHERE user_id = NEW.passenger_id;
        INSERT INTO viajes.email_outbox (trip_id, user_id, recipient, template_key, payload)
        SELECT NEW.trip_id, u.user_id, u.email, v_template,
            jsonb_build_object(
                'tripId', NEW.trip_id,
                'startsAt', NEW.starts_at,
                'endsAt', NEW.ends_at,
                'status', NEW.status,
                'origin', NEW.origin_address,
                'destination', NEW.destination_address
            )
        FROM viajes.users u
        WHERE u.user_id = v_user_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trips_enqueue_status_email ON viajes.trips;
CREATE TRIGGER trips_enqueue_status_email
AFTER INSERT OR UPDATE OF status ON viajes.trips
FOR EACH ROW EXECUTE FUNCTION viajes.enqueue_trip_status_email();

