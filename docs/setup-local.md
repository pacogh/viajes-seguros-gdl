# Instalación local

## Requisitos

- Node.js 20 o posterior.
- PostgreSQL 14 o posterior con PostGIS y `btree_gist` disponibles.
- `psql` para instalar los SQL de la Fase 1.

## Preparar base de datos

1. Crea una base PostgreSQL vacía y un rol de aplicación con los permisos necesarios.
2. Ejecuta en orden los scripts enumerados en [database/README.md](../database/README.md).
3. Antes de `database/05_admin_bootstrap.sql`, reemplaza el correo de ejemplo por el correo real autorizado.
4. En desarrollo, puedes ejecutar también `database/dev/seed_sample_data.sql`. Nunca lo ejecutes en producción.

## Ejecutar la aplicación

1. Copia `.env.example` como `.env.local` y completa `DATABASE_URL`, `APP_URL` y SMTP. No se requiere clave de Google Maps mientras las direcciones se capturen como texto.
2. Instala dependencias con `npm install`.
3. Inicia el modo local con `npm run dev` y abre `http://localhost:3000`.
4. El administrador usa `/claim-admin` una sola vez; los pasajeros se registran desde `/register`.

En modo local, si SMTP no está configurado, los enlaces de correo se imprimen en la salida del servidor. Esto solo se permite cuando `NODE_ENV=development`.

## Producción

Configura `NODE_ENV=production`, `APP_URL` HTTPS, base de datos accesible por TLS, cookies seguras, una clave aleatoria para `MAIL_WORKER_SECRET`, SMTP verificado y la configuración de correo. El mapa permanece desactivado hasta que se apruebe su reactivación y se configure un proveedor. Ejecuta `npm run build` y luego `npm run start`. El host público y el proveedor PostgreSQL no están seleccionados todavía; deben admitir Node.js, PostgreSQL y PostGIS.

