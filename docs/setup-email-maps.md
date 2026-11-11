# Correo y ubicaciones

## Correo

Configura `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASSWORD` y `MAIL_FROM`. El dominio remitente debe estar autenticado con SPF/DKIM según el proveedor.

`MAIL_DAILY_CAP` y `MAIL_MONTHLY_CAP` limitan las notificaciones antes de enviarlas. Sus valores deben ser iguales o menores que los límites gratuitos reales de la cuenta proveedora. El contador reserva cupo incluso si falla un envío, para evitar sobrepasar el límite.

Los cambios de estado dejan mensajes en `viajes.email_outbox`. Cada solicitud o decisión administrativa intenta enviar la cola. Para reintentar mensajes fallidos o procesar una cola detenida, configura un cron del servidor que haga `POST /api/internal/mail/flush` con `Authorization: Bearer <MAIL_WORKER_SECRET>`. El endpoint no queda abierto sin secreto.

Al alcanzar las cuotas o si SMTP no está disponible, los registros de cuenta y los viajes permanecen en la base; el correo requerido para verificar una cuenta o recuperar contraseña puede no llegar hasta que se restablezca el servicio.

## Direcciones de viaje

Por ahora no se carga Google Maps ni se requiere una clave de API. Origen y destino son campos de texto opcionales; el administrador revisa manualmente si las direcciones están dentro de la zona de servicio del AMG. Las columnas espaciales y sus polígonos se conservan para una posible integración cartográfica futura, pero no se consultan al crear una solicitud con texto libre.
