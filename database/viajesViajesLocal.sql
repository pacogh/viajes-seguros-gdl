SELECT t.tablename AS tabla, p.privilegio
FROM pg_catalog.pg_tables AS t
CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) AS p(privilegio)
WHERE t.schemaname = 'viajes'
  AND NOT has_table_privilege(
      current_user,
      format('%I.%I', t.schemaname, t.tablename),
      p.privilegio
  )
ORDER BY t.tablename, p.privilegio;

GRANT CONNECT ON DATABASE viajes TO viajes_app;
GRANT USAGE ON SCHEMA viajes TO viajes_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA viajes TO viajes_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA viajes TO viajes_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA viajes TO viajes_app;

SELECT current_database() AS base_actual, current_user AS usuario_actual;

SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'viajes';

SELECT tablename
FROM pg_catalog.pg_tables
WHERE schemaname = 'viajes'
ORDER BY tablename;

SELECT t.tablename AS tabla, p.privilegio
FROM pg_catalog.pg_tables AS t
CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) AS p(privilegio)
WHERE t.schemaname = 'viajes'
  AND NOT has_table_privilege(
      current_user,
      format('%I.%I', t.schemaname, t.tablename),
      p.privilegio
  )
ORDER BY t.tablename, p.privilegio;

