# Sistema de administración de viajes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Entregar una aplicación web para solicitudes de viaje con una cuenta administrativa, disponibilidad configurable, mapa limitado al AMG y autenticación con contraseña.

**Architecture:** Aplicación completa Next.js/TypeScript sobre Node.js, con PostgreSQL + PostGIS como autoridad para disponibilidad, reservas y validación geográfica. El acceso a PostgreSQL usará SQL explícito con `pg`; los archivos de `database/` se ejecutan antes de crear el código de aplicación.

**Tech Stack:** TypeScript, Next.js, Node.js, PostgreSQL, PostGIS, `pg`, correo SMTP configurable, Google Maps JavaScript API.

**Spec:** `specs/viajes-sdd-spec.md`

## Global Constraints

- La operación usa `America/Mexico_City`.
- Disponibilidad inicial 24/7; duración inicial 60 minutos; el administrador puede configurar cualquier cantidad entera positiva de minutos.
- El rango llega desde hoy hasta el último día del mes que cae dos meses adelante, inclusive.
- El teléfono mexicano es obligatorio y único, pero no verificado; el pasajero puede iniciar sesión con correo o teléfono y contraseña.
- El correo del pasajero se verifica y las recuperaciones de contraseña usan enlaces de un solo uso. No se envían códigos por correo ni se usan SMS.
- El correo administrativo inicial se configura en SQL; se le asigna rol por coincidencia sin verificar acceso al buzón.
- Solo se permite origen/destino dentro de los nueve municipios oficiales del AMG, si el usuario los proporciona.
- Los cargos por Google Maps se deben impedir con cuotas duras dentro de las cuotas gratuitas; al llegar al límite, el servicio de mapa se detiene.
- El proveedor de correo debe permanecer dentro de un plan gratuito y el sistema debe detener envíos antes de un exceso que pueda generar cargos.
- No incluir conductor adicional, seguimiento, ruta, tarifas ni pagos.
- `database/dev/seed_sample_data.sql` debe contener datos sintéticos, ser opcional y advertir que es solo para desarrollo.

## Review Focus

- **Dos usuarios reservan simultáneamente intervalos coincidentes:** la base debe aceptar como máximo una solicitud activa para el intervalo.
- **Cambio de duración crea traslapes:** se rechaza el cambio y los viajes existentes conservan sus datos.
- **Cancelación de viaje confirmado:** el intervalo sigue bloqueado hasta que el administrador lo libere manualmente.
- **Punto de mapa en borde municipal o fuera de AMG:** validar con la geometría PostGIS de servidor, no solo con el texto devuelto por Google.
- **Límite gratuito de correo o Google Maps alcanzado:** dejar de enviar/consultar el servicio y conservar disponibles las funciones que no dependen de él.

---

## Fase 1 — Base de datos

### Task 1: Extensiones y esquema relacional

**Files:**
- Create: `database/00_extensions.sql`
- Create: `database/01_schema.sql`
- Create: `database/README.md`

**Interfaces:**
- Produce tablas para usuarios, configuración administrativa inicial, sesiones, enlaces de verificación/restablecimiento, duración/configuración, indisponibilidades semanales y por fecha, solicitudes, geometrías AMG, cola de correo y contadores de cuotas gratuitas.
- Las fechas/horas de viaje se almacenan como `timestamptz`; los intervalos guardan inicio y fin calculado.
- Las extensiones requeridas son PostGIS y `btree_gist`.

- [x] Crear las extensiones con instrucciones claras de los permisos que necesita el rol SQL.
- [x] Crear las tablas con claves UUID, marcas de tiempo, restricciones de estado y borrado lógico donde aplique.
- [x] Definir la forma de representar sesiones revocables, enlace de correo de un solo uso, duración en minutos y bloqueo/liberación explícita de intervalos cancelados.
- [x] Documentar en `database/README.md` el orden de ejecución y requisitos del servidor PostgreSQL.

### Task 2: Restricciones, índices y exclusión de intervalos

**Files:**
- Create: `database/02_constraints_indexes.sql`

**Interfaces:**
- Correo normalizado único y teléfono mexicano normalizado único.
- Restricción de exclusión GiST para intervalos no liberados con estado pendiente, confirmado o cancelado por administrador.

- [x] Añadir restricciones e índices para unicidad y consultas por dueño/fecha/estado.
- [x] Definir una restricción GiST de no traslape para rangos `tstzrange(start_at, end_at, '[)')` de reservas no liberadas, usando `btree_gist`.
- [x] Permitir que liberar manualmente una cancelación administrativa quite su intervalo del conjunto bloqueante sin borrar el historial.

### Task 3: Funciones SQL de disponibilidad y solicitudes

**Files:**
- Create: `database/03_functions.sql`
- Create: `database/04_triggers.sql`

**Interfaces:**
- `get_available_slots(p_from date, p_through date, p_now timestamptz) RETURNS TABLE(slot_start timestamptz, slot_end timestamptz)` devuelve horarios disponibles en `America/Mexico_City`.
- `create_trip_request(p_user_id uuid, p_start timestamptz, p_origin geography, p_destination geography) RETURNS TABLE(trip_id uuid, status text)` crea una solicitud pendiente dentro de una transacción.
- `set_trip_duration(p_minutes integer)` aplica la duración y falla si genera intervalos activos traslapados.
- `confirm_trip(p_trip_id uuid, p_admin_id uuid)` y `reject_trip(p_trip_id uuid, p_admin_id uuid)` cambian solicitudes pendientes.
- `cancel_pending_trip(p_trip_id uuid, p_user_id uuid)` libera un pendiente; `cancel_confirmed_trip(p_trip_id uuid, p_admin_id uuid)` conserva el bloqueo hasta liberación explícita.
- `release_admin_cancelled_trip(p_trip_id uuid, p_admin_id uuid)` libera manualmente un intervalo cancelado.
- `is_point_in_amg(p_point geography) RETURNS TABLE(is_allowed boolean, municipality_name text)` valida inclusión en cualquiera de los nueve polígonos con `ST_Covers`, incluyendo sus límites.

- [x] Implementar el cálculo de ventana desde hoy hasta el último día del mes situado dos meses adelante.
- [x] Generar oportunidades de salida por duración configurada, aplicar indisponibilidades y retirar fechas/horas pasadas.
- [x] Bloquear intervalos activos mediante transacciones y la restricción de exclusión; rechazar solicitudes fuera de ventana, indisponibles o traslapadas.
- [x] Implementar transiciones de estado, liberación y retención de intervalos según la especificación.
- [x] Al cambiar duración, recalcular `ends_at` de pendientes/confirmados de manera atómica; rechazar la operación completa si se detecta cualquier conflicto.
- [x] Añadir triggers solo donde sean necesarios para auditoría o consistencia, sin duplicar reglas de las funciones.

### Task 4: Bootstrap administrativo y datos geográficos AMG

**Files:**
- Create: `database/05_admin_bootstrap.sql`
- Create: `database/06_amg_boundaries.sql`
- Create: `database/data/README.md`

**Interfaces:**
- El script de bootstrap define un único correo permitido para reclamar la primera cuenta administrativa; no contiene contraseña.
- El script geográfico instala los polígonos oficiales de El Salto, Guadalajara, Ixtlahuacán de los Membrillos, Juanacatlán, San Pedro Tlaquepaque, Tlajomulco de Zúñiga, Tonalá, Zapopan y Zapotlanejo.

- [x] Dejar el correo administrativo como valor de configuración que el propietario reemplaza antes de ejecutar el script.
- [x] Obtener y documentar la fuente IIEG de límites municipales, registrar su fecha/atribución e importar polígonos al SRID esperado por PostGIS.
- [x] Añadir función SQL que determine el municipio del punto y valide que pertenece al AMG.

### Task 5: Datos sintéticos e instrucciones de la Fase 1

**Files:**
- Create: `database/dev/seed_sample_data.sql`
- Modify: `database/README.md`

**Interfaces:**
- Script opcional de desarrollo con usuarios sintéticos, horarios/indisponibilidades y solicitudes de ejemplo; nunca se ejecuta automáticamente en producción.

- [x] Crear filas sintéticas que permitan ver estados pendientes, confirmados, rechazados y cancelados sin datos personales reales.
- [x] Documentar advertencias de desarrollo, orden exacto de scripts, ejemplo de conexión y cómo omitir el seed al instalar producción.

---

## Fase 2 — Aplicación

### Task 6: Base Next.js y acceso a PostgreSQL

**Files:**
- Create: `package.json`, `tsconfig.json`, `next.config.ts`, `.env.example`
- Create: `src/lib/db/pool.ts`, `src/lib/db/queries.ts`, `src/app/layout.tsx`, `src/app/globals.css`

**Interfaces:**
- `getPool(): Pool` crea una sola conexión reutilizable desde `DATABASE_URL`.
- `withTransaction<T>(work: (client: PoolClient) => Promise<T>): Promise<T>` encapsula BEGIN/COMMIT/ROLLBACK.
- Variables de entorno documentadas para DB, sesiones, correo y Google Maps.

- [x] Crear la aplicación TypeScript con runtime Node y dependencias mínimas para SQL, hash de contraseñas, correo SMTP y carga del SDK Google Maps.
- [x] Implementar pool PostgreSQL y transacciones; ninguna consulta sensible se ejecuta desde el navegador.
- [x] Añadir configuración local y documentación de variables sin credenciales reales.

### Task 7: Autenticación y perfiles

**Files:**
- Create: `src/lib/auth/passwords.ts`, `src/lib/auth/sessions.ts`, `src/lib/auth/email-tokens.ts`, `src/lib/mail/sender.ts`
- Create: `src/app/api/auth/register/route.ts`, `src/app/api/auth/verify/route.ts`, `src/app/api/auth/login/route.ts`, `src/app/api/auth/logout/route.ts`, `src/app/api/auth/forgot-password/route.ts`, `src/app/api/auth/reset-password/route.ts`, `src/app/api/auth/admin-claim/route.ts`

**Interfaces:**
- `hashPassword(plain: string): Promise<string>` y `verifyPassword(plain: string, hash: string): Promise<boolean>`.
- `createSession(userId: string): Promise<string>` y `revokeSession(sessionId: string): Promise<void>`.
- `sendEmail(message: EmailMessage): Promise<void>` usa SMTP configurable; un modo local de desarrollo muestra enlaces solo en consola, nunca en producción.

- [x] Implementar alta de pasajero con correo, teléfono MX y contraseña; enviar un enlace de verificación al correo.
- [x] Implementar login con correo o teléfono más contraseña y cookie HttpOnly/Secure/SameSite.
- [x] Limitar intentos fallidos por identificador e IP y verificar CSRF/origen para operaciones con sesión.
- [x] Implementar verificación y recuperación de contraseña con tokens aleatorios almacenados como hash, de un solo uso y con vencimiento.
- [x] Implementar reclamación inicial del rol administrador por coincidencia exacta normalizada con el correo SQL, sin comprobación del buzón, y bloquear nuevas reclamaciones tras consumir bootstrap.
- [x] Enforzar cuotas gratuitas de envío de correo antes de llamar al proveedor; cuando se alcance el límite, rechazar nuevos envíos sin cobrar.
- [x] Proteger páginas mediante layouts de servidor y comprobar roles en cada endpoint de pasajero y administración.

### Task 8: Calendario y solicitud de viaje

**Files:**
- Create: `src/app/(passenger)/calendar/page.tsx`, `src/app/(passenger)/requests/page.tsx`
- Create: `src/components/calendar/booking-calendar.tsx`, `src/components/calendar/slot-list.tsx`, `src/components/requests/trip-request-form.tsx`
- Create: `src/app/api/availability/route.ts`, `src/app/api/trips/route.ts`, `src/app/api/trips/[id]/cancel/route.ts`

**Interfaces:**
- `GET /api/availability?from=YYYY-MM-DD&through=YYYY-MM-DD` devuelve días y horarios libres.
- `POST /api/trips` recibe `{ startsAt, origin?, destination? }` y devuelve solicitud `pending` o error de conflicto.
- `GET /api/trips` devuelve solo solicitudes del pasajero autenticado.

- [x] Mostrar calendario desde hoy hasta fin del segundo mes adelante y no mostrar horas pasadas.
- [x] Mostrar intervalos generados por SQL y permitir selección de un solo horario por solicitud.
- [x] Capturar ubicación opcional y enviarla para validación de servidor; reconsultar disponibilidad al crear.
- [x] Mostrar estado de solicitudes y permitir cancelar solo mientras estén pendientes.
- [x] Mostrar mensajes claros al usuario si el intervalo fue ocupado o está indisponible.

### Task 9: Mapa, geocodificación y validación AMG

**Files:**
- Create: `src/components/map/location-picker.tsx`, `src/lib/maps/google-maps.ts`, `src/app/api/locations/validate/route.ts`

**Interfaces:**
- `LocationValue = { address: string; latitude: number; longitude: number }`.
- `POST /api/locations/validate` valida cada punto proporcionado con `is_point_in_amg`.

- [x] Integrar búsqueda/autocompletado Google Maps y marcador ajustable para origen y destino opcionales.
- [x] Restringir la clave del navegador a los dominios previstos y documentar APIs necesarias.
- [x] Documentar cuotas duras de Cloud Console por cada API/SKU usada, en valores no superiores a sus cuotas gratuitas publicadas.
- [x] Deshabilitar selección y mostrar aviso cuando el mapa/geocodificación no esté configurado o llegue a cuota; permitir seguir sin ubicaciones porque son opcionales.
- [x] Validar ubicaciones de nuevo en backend y no confiar en la validación del cliente.

### Task 10: Panel administrativo y estados

**Files:**
- Create: `src/app/(admin)/admin/page.tsx`, `src/app/(admin)/admin/availability/page.tsx`, `src/app/(admin)/admin/settings/page.tsx`
- Create: `src/components/admin/trip-requests-table.tsx`, `src/components/admin/unavailability-editor.tsx`, `src/components/admin/duration-form.tsx`
- Create: `src/app/api/admin/trips/route.ts`, `src/app/api/admin/trips/[id]/confirm/route.ts`, `src/app/api/admin/trips/[id]/reject/route.ts`, `src/app/api/admin/trips/[id]/cancel/route.ts`, `src/app/api/admin/trips/[id]/release/route.ts`, `src/app/api/admin/availability/route.ts`, `src/app/api/admin/duration/route.ts`

**Interfaces:**
- Admin endpoints require session role `admin`.
- Admin can confirm/reject pending, cancel confirmed, release admin-cancelled intervals, change duration, add/remove recurring weekly and one-off unavailable periods.

- [x] Crear vistas de solicitudes con filtros por estado y datos de horario/ubicaciones disponibles.
- [x] Conectar acciones administrativas a las funciones SQL correspondientes; no reimplementar transacciones en cliente.
- [x] Crear editor semanal y por fecha para indisponibilidades.
- [x] Al cambiar duración, informar al administrador de conflictos y conservar el valor anterior si SQL rechaza el cambio.
- [x] Mantener el intervalo bloqueado tras cancelar un confirmado hasta que admin use la acción de liberación.

### Task 11: Correos de estado y documentación de ejecución

**Files:**
- Create: `src/lib/mail/templates.ts`, `src/lib/mail/quota.ts`, `docs/setup-local.md`, `docs/setup-email-maps.md`
- Modify: `README.md`

**Interfaces:**
- `sendTripStatusEmail(to: string, trip: TripSummary): Promise<SendResult>` entrega correo en estados pendiente, confirmado, rechazado y cancelado.
- Los límites del plan gratuito son configuración explícita; no se habilitan complementos ni upgrades automáticos.

- [x] Enviar notificaciones de cambio de estado al correo del pasajero usando plantillas en español.
- [x] Aplicar contador diario y mensual de envíos en base de datos antes del proveedor para no sobrepasar el límite configurado.
- [x] Documentar límites actuales de proveedor gratuito como dato que debe verificarse al desplegar.
- [x] Documentar migraciones SQL, modo de correo de desarrollo, configuración de Google Maps/cuotas, y secretos requeridos para ejecutar la aplicación.

## Cierre de implementación

- Fase 1 termina con `database/` y su README; no se inicia Fase 2 antes de que los scripts de base de datos estén completos.
- Fase 2 termina con la aplicación desplegable de forma portable y sin credenciales incrustadas.
- No incluye despliegue público, ya que el usuario definirá servidor y base alojada después.
