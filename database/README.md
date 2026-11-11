# Base de datos del sistema de viajes

## Requisitos

- PostgreSQL 14 o posterior.
- Extensiones instalables: PostGIS y `btree_gist`.
- Un rol propietario de la base o con permiso para crear las extensiones y el esquema `viajes`.
- Zona horaria de operación: `America/Mexico_City`.

El servidor de producción todavía no está definido. Antes de elegirlo, comprobar que soporte PostgreSQL y PostGIS.

## Orden de instalación

Ejecutar desde la raíz del proyecto, con `psql` apuntando a una base vacía:

1. `database/00_extensions.sql`
2. `database/01_schema.sql`
3. `database/02_constraints_indexes.sql`
4. `database/03_functions.sql`
5. `database/04_triggers.sql`
6. `database/05_admin_bootstrap.sql` después de reemplazar el correo de ejemplo por el correo real del administrador inicial.
7. `database/06_amg_boundaries.sql`
8. `database/07_text_only_addresses.sql` (solo necesario al actualizar una base ya instalada; en instalaciones nuevas también es seguro ejecutarlo).

El seed `database/dev/seed_sample_data.sql` es opcional y solo para entornos de desarrollo. No ejecutarlo en producción.

Los objetos se crean en el esquema PostgreSQL `viajes`. La aplicación debe invocar
las funciones de dominio documentadas abajo dentro de conexiones con `search_path`
controlado o referenciarlas con su nombre calificado.

## Funciones de dominio

- `viajes.get_available_slots(from, through, now)` calcula salidas futuras dentro de la ventana de dos meses, la duración configurada y los bloques de indisponibilidad.
- `viajes.register_passenger(name, email, phone, password_hash)` crea pasajeros pendientes y protege el correo reservado para el administrador inicial.
- `viajes.create_trip_request(...)` vuelve a validar cuenta, ventana, puntos AMG e intervalo; la restricción de exclusión resuelve carreras concurrentes.
- `viajes.confirm_trip`, `reject_trip`, `cancel_pending_trip`, `cancel_confirmed_trip` y `release_admin_cancelled_trip` controlan transiciones válidas.
- `viajes.set_trip_duration(minutes, admin_id)` recalcula pendientes/confirmados en una subtransacción y revierte todo ante cualquier traslape.
- Las funciones `add_*_unavailability` y `disable_*_unavailability` requieren un administrador activo.
- `viajes.claim_initial_admin(...)` reclama una sola vez el rol inicial por coincidencia de correo SQL.
- `viajes.is_point_in_amg(point)` aplica `ST_Covers`, incluidos bordes municipales.
- `viajes.reserve_email_quota(at, daily_cap, monthly_cap)` reserva transaccionalmente cupo diario y mensual antes del envío.

`get_available_slots` genera una secuencia continua de salidas desde la medianoche
local del primer día de la ventana vigente, separadas por la duración configurada.
Para duraciones que no dividen 24 horas, los horarios se desplazan gradualmente
entre días; esta regla es intencional y está registrada en la bitácora SDD.

## Archivo de inicialización administrativa

`05_admin_bootstrap.sql` solo registra el correo autorizado; no incluye contraseña ni otros secretos. El acceso inicial se habilita por coincidencia de ese correo, de acuerdo con la regla aprobada. Debe ejecutarse una sola vez al preparar la base.

## Geometrías del AMG

Los límites provienen del conjunto municipal del Instituto de Información Estadística y Geográfica de Jalisco (IIEG), con licencia Creative Commons Attribution 4.0. La capa se publica en `Mexico_ITRF2008_UTM_Zone_13N` (EPSG:6368); el seed transforma sus geometrías a EPSG:4326 para conservarlas como referencia de una posible validación cartográfica futura. Las direcciones de la versión actual son texto libre y el administrador revisa manualmente la zona.

Fuente: [Límite Municipal Jalisco IIEG](https://seijal.jalisco.gob.mx/datos-abiertos/es/dataset/limite-municipal-jalisco-iieg). La zona de servicio usa los nueve municipios oficiales del AMG: El Salto, Guadalajara, Ixtlahuacán de los Membrillos, Juanacatlán, San Pedro Tlaquepaque, Tlajomulco de Zúñiga, Tonalá, Zapopan y Zapotlanejo.

## Respaldo y datos personales

La base contiene nombres, correos, teléfonos, ubicaciones y solicitudes de viaje. Restringir el acceso a roles de aplicación y administración, usar TLS en conexiones remotas, conservar copias cifradas y nunca versionar datos reales o contraseñas.

Genera un respaldo lógico fuera del servidor de producción con
`pg_dump --format=custom --file=viajes.dump "$DATABASE_URL"`. Restaura en una base
vacía compatible con PostGIS mediante `pg_restore --dbname="$DATABASE_URL" viajes.dump`.

