-- CONFIGURACIÓN REQUERIDA: reemplaza admin-inicial@example.com antes de ejecutar.
-- No almacena contraseñas. La cuenta reclamará el rol al registrarse con este correo.
DO $$
DECLARE
    v_initial_admin_email text := 'fcoj.villalba@gmail.com';
BEGIN
    IF v_initial_admin_email = 'admin-inicial@example.com'
       OR v_initial_admin_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' THEN
        RAISE EXCEPTION 'Edita database/05_admin_bootstrap.sql y configura el correo inicial real';
    END IF;

    IF EXISTS (
        SELECT 1 FROM viajes.users
        WHERE email_normalized = lower(btrim(v_initial_admin_email))
    ) THEN
        RAISE EXCEPTION 'El correo ya está registrado. Resuelve la cuenta existente antes de habilitar el bootstrap administrativo.';
    END IF;

    UPDATE viajes.app_settings
    SET initial_admin_email = lower(btrim(v_initial_admin_email)), updated_at = now()
    WHERE singleton AND admin_claimed_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se pudo configurar el correo: bootstrap ya fue reclamado o falta app_settings';
    END IF;
END $$;

