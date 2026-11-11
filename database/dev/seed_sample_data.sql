-- SOLO DESARROLLO. No ejecutar en producción: crea usuarios y viajes ficticios.
-- La contraseña hash es intencionalmente inválida como credencial de acceso.
BEGIN;

INSERT INTO viajes.users (user_id, full_name, email, phone_e164, password_hash, role, account_status, email_verified_at)
VALUES
 ('00000000-0000-4000-8000-000000000002', 'Pasajero Pendiente', 'pendiente@example.test', '+521000000002', 'DEV_ONLY_NOT_A_PASSWORD_HASH', 'passenger', 'active', now()),
 ('00000000-0000-4000-8000-000000000003', 'Pasajera Confirmada', 'confirmada@example.test', '+521000000003', 'DEV_ONLY_NOT_A_PASSWORD_HASH', 'passenger', 'active', now()),
 ('00000000-0000-4000-8000-000000000004', 'Pasajero Rechazado', 'rechazado@example.test', '+521000000004', 'DEV_ONLY_NOT_A_PASSWORD_HASH', 'passenger', 'active', now()),
 ('00000000-0000-4000-8000-000000000005', 'Pasajera Cancelada', 'cancelada@example.test', '+521000000005', 'DEV_ONLY_NOT_A_PASSWORD_HASH', 'passenger', 'active', now())
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO viajes.weekly_unavailability (weekday, start_minute, end_minute, reason, created_by)
VALUES (0, 0, 1440, 'Ejemplo: domingo sin atención', '00000000-0000-4000-8000-000000000002')
ON CONFLICT DO NOTHING;

INSERT INTO viajes.date_unavailability (starts_at, ends_at, reason, created_by)
VALUES (
    date_trunc('day', now() + interval '10 days'),
    date_trunc('day', now() + interval '10 days') + interval '2 hours',
    'Ejemplo de indisponibilidad por fecha',
    '00000000-0000-4000-8000-000000000002'
);

INSERT INTO viajes.trips (passenger_id, starts_at, ends_at, duration_minutes, status, slot_blocking, slot_released_at)
VALUES
 ('00000000-0000-4000-8000-000000000002', date_trunc('day', now() + interval '2 days') + interval '9 hours', date_trunc('day', now() + interval '2 days') + interval '10 hours', 60, 'pending', true, NULL),
 ('00000000-0000-4000-8000-000000000003', date_trunc('day', now() + interval '3 days') + interval '11 hours', date_trunc('day', now() + interval '3 days') + interval '12 hours', 60, 'confirmed', true, NULL),
 ('00000000-0000-4000-8000-000000000004', date_trunc('day', now() + interval '4 days') + interval '13 hours', date_trunc('day', now() + interval '4 days') + interval '14 hours', 60, 'rejected', false, NULL),
 ('00000000-0000-4000-8000-000000000005', date_trunc('day', now() + interval '5 days') + interval '15 hours', date_trunc('day', now() + interval '5 days') + interval '16 hours', 60, 'cancelled_by_admin', true, NULL);

COMMIT;

