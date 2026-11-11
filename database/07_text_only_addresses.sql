-- Permite guardar direcciones escritas sin coordenadas ni geocodificación.
-- Ejecutar una vez en bases ya instaladas; conserva compatibilidad con viajes que tengan geometrías.
BEGIN;

ALTER TABLE viajes.trips
    DROP CONSTRAINT IF EXISTS trips_origin_fields_together,
    DROP CONSTRAINT IF EXISTS trips_destination_fields_together;

ALTER TABLE viajes.trips
    ADD CONSTRAINT trips_origin_fields_together CHECK (
        (origin_address IS NULL AND origin_geom IS NULL AND origin_municipality_code IS NULL)
        OR (nullif(btrim(origin_address), '') IS NOT NULL
            AND ((origin_geom IS NULL AND origin_municipality_code IS NULL)
                 OR (origin_geom IS NOT NULL AND origin_municipality_code IS NOT NULL)))
    ),
    ADD CONSTRAINT trips_destination_fields_together CHECK (
        (destination_address IS NULL AND destination_geom IS NULL AND destination_municipality_code IS NULL)
        OR (nullif(btrim(destination_address), '') IS NOT NULL
            AND ((destination_geom IS NULL AND destination_municipality_code IS NULL)
                 OR (destination_geom IS NOT NULL AND destination_municipality_code IS NOT NULL)))
    );

COMMIT;
