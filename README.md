# Viaje Seguro GDL

Aplicación web en español para solicitudes de viajes, con un panel administrativo, calendario de disponibilidad y captura opcional de direcciones en texto.

## Stack

- Next.js, React y TypeScript sobre Node.js.
- PostgreSQL + PostGIS; acceso mediante `pg` y SQL explícito.
- Autenticación propia con contraseñas, cookies seguras y tokens de correo de un solo uso.

## Fases SDD

- **Fase 1:** los scripts SQL están en [database/](database/README.md).
- **Fase 2:** aplicación en `src/`, con instrucciones locales en [docs/setup-local.md](docs/setup-local.md).
- Especificación aprobada: [specs/viajes-sdd-spec.md](specs/viajes-sdd-spec.md).

## Inicio rápido

1. Instala los scripts de la base en el orden indicado en `database/README.md`.
2. Copia `.env.example` a `.env.local` y completa la configuración de conexión y correo.
3. Ejecuta `npm install`.
4. Inicia con `npm run dev`.
5. Reclama la cuenta administrativa inicial en `/claim-admin`; pasajeros se registran en `/register`.

La puesta en producción requiere que el propietario elija un servidor público compatible con Node.js y PostgreSQL/PostGIS. Revisa [configuración de correo y ubicaciones](docs/setup-email-maps.md). El mapa está desactivado por ahora; las direcciones se capturan como texto opcional.
## Promoción

El plan de promoción local está en [promoción/plan-promocional.md](promoción/plan-promocional.md), con briefs visuales y prompts en [promoción/creativos/](promoción/creativos/).
