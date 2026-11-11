-- ver todas las bases de datos
SELECT * FROM pg_database WHERE datallowconn ORDER BY datname;


-- ver todas la tablas
SELECT * FROM pg_catalog.pg_tables WHERE schemaname = 'viajes' ORDER BY tablename;
SELECT schemaname AS esquema, tablename AS tabla FROM pg_catalog.pg_tables WHERE schemaname = 'viajes' ORDER BY tablename;

SELECT * FROM viajes.amg_municipalities;
SELECT count(*) AS municipios FROM viajes.amg_municipalities;
