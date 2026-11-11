# Sistema web para administrar viajes — Especificación SDD

**Estado:** aprobado para desarrollo.  
**Fecha:** 2026-11-06  
**Metodología:** Spec-Driven Development (SDD)

## 1. Propósito

Crear un sitio web para que pasajeros soliciten viajes en horarios disponibles y un administrador gestione la disponibilidad y confirme, rechace o cancele solicitudes. En esta primera versión opera un solo conductor.

## 2. Alcance de la primera versión

### Incluye

- Registro de pasajeros con nombre, correo y teléfono celular de 10 dígitos (sin prefijo +52).
- Validación de unicidad de correo y teléfono; el correo se verifica antes de activar la cuenta mediante un enlace, y el teléfono se valida como 10 dígitos/unicidad.
- Inicio de sesión de pasajeros con correo o teléfono mexicano y contraseña de al menos 8 caracteres. No se envían códigos por correo ni se integra SMS.
- Cuenta inicial de administrador permitida por correo configurado desde SQL, sin verificar acceso al buzón antes de asignar el rol; el administrador establece su contraseña al completar su registro con nombre, correo y teléfono.
- Calendario de disponibilidad y listado de horarios generados a partir de la duración del viaje.
- Solicitudes de viaje con estados pendiente, confirmado, rechazado, cancelado por pasajero y cancelado por administrador.
- Panel administrativo para solicitudes, configuración de duración, y administración de indisponibilidades semanales y por fecha.
- Origen y destino son campos de texto opcionales. Sin geocodificación, el administrador revisa manualmente que las direcciones estén dentro del AMG.
- Aviso por correo al pasajero cuando la solicitud cambia de estado.
- Recuperación de contraseña mediante enlace de un solo uso enviado por correo; no se envían códigos de recuperación.
- Persistencia en PostgreSQL, con restricciones y transacciones para proteger unicidad y evitar reservas simultáneas.
- Datos de prueba claramente sintéticos y separados de los datos de producción.

### No incluye

- Asignación de conductores (hay uno por ahora).
- Seguimiento del vehículo o del viaje.
- Tarifas, cobros, pagos o cálculos de precio. El modelo de tarifas se pospone hasta que se defina cómo se calcularán.
- Vista o cálculo de ruta, distancia, tiempo estimado, mapas y geocodificación; quedan pospuestos para evitar costos.
- Aplicación móvil nativa.
- Alta pública de administradores o administración de múltiples administradores.

## 3. Reglas de negocio acordadas

### Usuarios y acceso

1. El registro de pasajero solicita nombre, correo y teléfono celular mexicano de 10 dígitos, sin prefijo +52.
2. Correo y teléfono deben ser únicos después de normalizarlos. El correo se verifica mediante un enlace de un solo uso. El teléfono celular mexicano de 10 dígitos (sin +52) es obligatorio y único, pero no se verifica mediante SMS.
3. El registro de pasajero solicita una contraseña de al menos 8 caracteres. Para iniciar sesión, el pasajero introduce su correo o teléfono celular (10 dígitos, sin +52) y esa contraseña.
4. La cuenta administrativa inicial se habilita si el correo ingresado coincide con el correo preautorizado desde SQL. No se comprueba acceso a ese buzón durante el alta. No se almacena su contraseña en SQL; el administrador la crea durante el registro inicial.
5. El pasajero y el administrador podrán recuperar la contraseña mediante un enlace de un solo uso enviado a su correo; no se enviarán códigos.

### Disponibilidad y solicitudes

1. La zona horaria operativa es `America/Mexico_City`.
2. El calendario permite solicitar desde la fecha actual hasta el último día del mes que cae dos meses calendario adelante, inclusive. Las fechas anteriores al día actual y las horas pasadas del día actual no están disponibles.
3. La disponibilidad inicial es continua, 24 horas al día y 7 días a la semana. La duración inicial del viaje es una hora. El administrador puede cambiarla a cualquier cantidad entera positiva de minutos.
4. Las horas de salida se generan separadas por la duración vigente del viaje. El administrador configura indisponibilidades recurrentes por día de semana y excepciones por fecha y hora.
5. El primer envío pendiente bloquea ese horario y las solicitudes que se traslapen con el intervalo del viaje. No se permite más de un viaje confirmado para un intervalo ocupado.
6. El pasajero puede cancelar su solicitud mientras siga pendiente. Rechazar o cancelar una solicitud pendiente libera su intervalo de inmediato.
7. El administrador puede confirmar o rechazar solicitudes pendientes, y puede cancelar viajes confirmados.
8. Cancelar un viaje confirmado deja su intervalo bloqueado. El administrador puede habilitarlo manualmente después.
9. Cambiar indisponibilidades no elimina ni modifica solicitudes pendientes o viajes confirmados que ya existan.
10. Cambiar la duración recalcula solicitudes pendientes y viajes confirmados. Si el cambio produce conflictos de traslape, se rechaza hasta que el administrador resuelva esos conflictos.

### Ubicaciones

1. Origen y destino son opcionales, incluso ambos pueden omitirse.
2. Las direcciones se capturan como texto libre y no se geocodifican ni se validan automáticamente dentro del AMG; el administrador revisa manualmente la zona antes de confirmar.
3. El AMG oficial vigente está integrado por El Salto, Guadalajara, Ixtlahuacán de los Membrillos, Juanacatlán, San Pedro Tlaquepaque, Tlajomulco de Zúñiga, Tonalá, Zapopan y Zapotlanejo.
4. El sistema guarda el texto ingresado. Las coordenadas y polígonos se conservan para una posible integración futura, pero no se usan en este flujo.

## 4. Flujos principales

### Registro y acceso de pasajero

1. El pasajero proporciona nombre, correo, teléfono celular mexicano de 10 dígitos (sin +52) y contraseña de al menos 8 caracteres.
2. El sistema comprueba duplicados y envía un enlace de verificación al correo.
3. El pasajero abre el enlace y activa su cuenta. El teléfono se guarda como dato obligatorio y único, sin verificación por SMS.
4. En adelante inicia sesión con correo o teléfono celular de 10 dígitos (sin +52) y contraseña.
5. El pasajero puede consultar sus solicitudes y su estado.

### Solicitud de viaje

1. El pasajero abre el calendario y elige un día y horario visible.
2. Opcionalmente escribe origen y/o destino en campos de texto.
3. El sistema guarda las direcciones sin geocodificarlas; el administrador revisa manualmente si están dentro del AMG al gestionar la solicitud.
4. La solicitud queda pendiente y bloquea temporalmente su intervalo. Al guardarse correctamente, la interfaz conserva el aviso y muestra el mismo texto en una ventana de confirmación que el pasajero puede cerrar.
5. El pasajero recibe correo por el cambio de estado.

### Gestión administrativa

1. El administrador inicia sesión con su correo y contraseña.
2. Puede consultar solicitudes pendientes, confirmar o rechazar, y cancelar viajes confirmados. En la parte superior ve un calendario mensual con los días que tienen viajes confirmados marcados; al seleccionar una fecha consulta en una modal los horarios confirmados, junto con el nombre y teléfono del pasajero.
3. Puede establecer una nueva duración. El cambio se rechaza si causaría traslapes.
4. Puede definir bloques semanales recurrentes y excepciones de indisponibilidad por fecha/hora.
5. Al cancelar un confirmado, el horario permanece bloqueado hasta que el administrador lo habilite manualmente.

## 5. Criterios de aceptación

- Dos cuentas no pueden compartir el mismo correo normalizado ni el mismo teléfono mexicano normalizado.
- Ningún pasajero activa la cuenta sin abrir el enlace de verificación enviado a su correo.
- Los pasajeros pueden iniciar sesión con correo o teléfono mexicano y contraseña; ningún código se envía para iniciar sesión.
- La recuperación de contraseña usa un enlace de un solo uso enviado por correo, sin códigos.
- La cuenta administrativa inicial solo puede registrarse con el correo configurado en SQL; no se exige verificar acceso a ese buzón antes de asignar el rol.
- El rango visible incluye hoy y llega hasta el último día del mes dos meses adelante; no presenta fechas pasadas ni horarios pasados de hoy.
- Con duración de una hora y disponibilidad 24/7, las salidas se generan a intervalos de una hora; al aplicar indisponibilidades, sus intervalos dejan de ofrecerse.
- El administrador puede definir la duración como cualquier cantidad entera positiva de minutos.
- La primera solicitud pendiente bloquea el intervalo y cualquier solicitud que se traslape con él.
- Rechazar o cancelar una solicitud pendiente libera su intervalo inmediatamente.
- Cancelar un viaje confirmado no lo libera; una acción manual del administrador es necesaria para reabrirlo.
- Los cambios de indisponibilidad conservan sin cambios solicitudes pendientes y viajes confirmados preexistentes.
- El cambio de duración se aplica a solicitudes pendientes y viajes confirmados solo si no causa traslapes.
- Los puntos de origen y destino se validan de manera independiente. Cada punto ingresado debe pertenecer a uno de los nueve municipios; se permite omitir ambos.
- Los cambios de estado generan un correo al pasajero.

## 6. Fases de entrega

### Fase 1 — Base de datos

Crear `database/` con archivos SQL versionados y documentados, por ejemplo:

- extensiones requeridas y esquema;
- tablas, claves, restricciones e índices;
- funciones, procedimientos o triggers que sean necesarios para la integridad;
- inicialización del correo administrativo autorizado (sin contraseñas ni secretos);
- importación/configuración de los límites municipales del AMG;
- datos sintéticos de prueba en un script separado y opcional;
- instrucciones de instalación, orden de ejecución y respaldo.

La lógica crítica de unicidad, reserva concurrente, solapamiento, elegibilidad de horarios y validación geográfica deberá quedar cubierta por restricciones/transacciones SQL y no depender únicamente de la interfaz.

### Fase 2 — Aplicación

Implementar registro y acceso con contraseña, verificación y recuperación mediante enlaces de correo, calendario y selección de horarios, solicitudes del pasajero, panel administrativo, captura opcional de direcciones en texto, notificaciones por correo y configuración externa mediante variables de entorno. El código no contendrá claves de Google Maps/correo, contraseñas ni credenciales de base de datos.

## 7. Decisiones técnicas aprobadas

1. **Aplicación:** TypeScript con Next.js como aplicación web completa, ejecutándose sobre Node.js. El despliegue se hará en el servidor que definas.
2. **Acceso a PostgreSQL:** usar SQL explícito y el driver `pg`, sin ORM, para que los artefactos de `database/` sean la fuente de verdad.
3. **Direcciones:** en esta fase se guardan como texto libre sin geocodificación ni validación automática de zona. El administrador revisa que estén dentro del AMG antes de confirmar. Se conservan las columnas espaciales y los límites oficiales en PostGIS para una posible integración futura.
4. **Autenticación propia:** contraseñas con hash fuerte, sesiones revocables en cookies seguras y enlaces de un solo uso con vencimiento para verificar correos y recuperar contraseñas. No se enviarán códigos por correo ni se integrará SMS.
5. **Mapa:** Google Maps queda desactivado y no requiere clave ni genera llamadas. Puede evaluarse en una fase futura si se decide asumir su costo.
6. **Correo:** usar un proveedor con plan gratuito y detener envíos en el límite para impedir cobros. Como candidato actual, Brevo declara 300 envíos diarios gratuitos e incluye correo transaccional; al llegar al límite los correos pueden retrasarse o no entregarse. El proveedor/cuenta remitente se configurarán antes de producción, y sus planes y restricciones deberán verificarse nuevamente en ese momento. Fuente: [límites del plan gratuito de Brevo](https://help.brevo.com/hc/en-us/articles/208580669-FAQs-What-are-the-limits-of-the-Free-plan) y [planes de Brevo](https://help.brevo.com/hc/en-us/articles/208589409-About-Brevo-s-pricing-plans).
7. **Interfaz:** diseño adaptable para móvil y escritorio, textos en español, y una vista de pasajero y otra administrativa protegida por rol.

## 8. Dependencias externas y costos a considerar

- No se usa Google Maps ni geocodificación en esta fase, por lo que no se requiere una cuenta de facturación ni clave de API para las ubicaciones.
- No se enviarán SMS. Los enlaces de verificación/recuperación y las notificaciones de viajes usarán correo con un proveedor de plan gratuito; el sistema detendrá envíos antes de un límite que pueda generar cargos.
- El teléfono mexicano no se verifica por SMS. Aunque el número es único y puede usarse como identificador de inicio de sesión, el sistema no comprobará que el pasajero controla ese número; el acceso requiere además la contraseña.
- El rol administrativo inicial se asignará al registrarse con el correo coincidente con el configurado en SQL, sin demostrar acceso al buzón. Esta es una decisión explícita del propietario, pero permite que alguien que conozca ese correo reclame la cuenta y configure su propia contraseña. El proceso de recuperación posterior sí requerirá acceso al correo.
- Todavía no se ha seleccionado un servidor público ni base de datos administrada. El despliegue queda fuera de estas fases hasta que se defina ese destino.

## 9. Fuentes geográficas

- IMEPLAN, delimitación oficial actual del AMG y relación de nueve municipios: [Área Metropolitana de Guadalajara](https://www.imeplan.mx/area-metropolitana-de-guadalajara).
- IIEG Jalisco, límites municipales en formato geográfico: [Límite Municipal Jalisco IIEG](https://seijal.jalisco.gob.mx/datos-abiertos/es/dataset/limite-municipal-jalisco-iieg).

## 10. Configuraciones pendientes para producción

1. La integración de mapas queda pospuesta; no es necesaria para operar la versión actual.
2. Proveedor y remitente de correo autenticado, con topes configurados para impedir cargos. La cuota puede detener verificación, recuperación y notificaciones al alcanzarse.
3. Servidor público y base PostgreSQL/PostGIS compatibles; se configurarán cuando el propietario defina el destino.

## 11. Fuera del documento

La especificación fue aprobada por el propietario antes de iniciar la implementación. Las decisiones de producción del apartado 10 se requieren para desplegar y operar servicios externos, no para completar el desarrollo local.
