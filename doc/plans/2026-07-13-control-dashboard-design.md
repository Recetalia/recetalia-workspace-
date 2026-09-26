# Spec: Dashboard de Control en Gestión (WhatsApp + Infraestructura) — 2026-07-13

## Contexto

Gestión necesita un **dashboard de control** operativo con dos vistas:

- **A. Monitor de WhatsApp**: todos los mensajes enviados vía Twilio, su status de entrega, el destinatario y la **prescription vinculada**.
- **B. Monitor de infraestructura** (estilo sentinel): ¿está operativo el sistema?, recursos físicos del server de apps y de la DB, errores/latencia de las APIs y usuarios logueados por rol.

Hallazgos que condicionan el diseño (verificados 2026-07-13):

- El transversal envía WhatsApp por Twilio pero **descarta el SID** (solo lo imprime en el log) y la tabla `notification` **no tiene FK a prescription** → hoy no existe vínculo mensaje↔receta.
- La Messages API de Twilio permite listar mensajes históricos con status, destinatario y fecha (validado durante el debugging de notificaciones dobles).
- La DB de prod es DigitalOcean **managed** (sin SSH) y el server de apps es un droplet DO → la API de Monitoring de DO expone CPU/RAM/disco/conexiones sin instalar stack de monitoreo propio.
- Las 3 APIs son Spring Boot 3 (Micrometer incluido) → errores/latencia salen de Actuator interno.

## Decisiones de alcance (con Pablo, 2026-07-13)

1. **Solo producción**: el dashboard monitorea el ambiente prod (Twilio real, droplet `.217`, DB managed). En dev degrada con "no disponible".
2. **Vínculo receta solo de ahora en adelante**: los mensajes nuevos guardan SID + prescriptionId. Los ~8.700 históricos se listan desde Twilio sin vínculo (no se infiere por teléfono+fecha).
3. **Frescura on-open**: el status se consulta/refresca al abrir la pantalla y con botón refrescar. Sin webhooks ni alertas en v1.
4. **Enfoques elegidos**: A1 (registro propio + Twilio para status) y B1 (API de DO + health checks, sin agentes de terceros).
5. **Branching**: todo en branches nuevos desde `2.x.y` en cada repo; nunca se modifica `2.x.y` directo; merge solo con OK explícito.

## Modelo de datos (4 tablas nuevas)

### `whatsapp_message` (schema `recetali_receta`)

**Nota de cardinalidad (corregido tras explorar el código):** el transversal envía UN WhatsApp por *grupo* de recetas del mismo paciente (agrupa por prefijo de código). El vínculo es 1 mensaje → N prescriptions: se modela con **una fila por (twilioSid, prescriptionId)** y unique compuesto — el dashboard agrupa por SID al listar.

| Columna | Tipo | Notas |
|---|---|---|
| `id` | varchar(36) PK | UUID |
| `twilioSid` | varchar(40) | UNIQUE junto con prescriptionId |
| `prescriptionId` | varchar(36) FK → prescription | NOT NULL (siempre se envía por una receta) |
| `notificationId` | varchar(36) FK → notification | NULL (si aplica) |
| `phone` | varchar(50) | destinatario normalizado |
| `templateType` | varchar(30) | `PENDING` \| `REMINDER` (los dos templates actuales) |
| `status` | varchar(20) | `queued/sent/delivered/read/failed/undelivered` (valores Twilio) |
| `errorCode` | varchar(20) NULL | código Twilio si falló |
| `sentAt` | timestamp | momento del envío |
| `statusUpdatedAt` | timestamp NULL | último refresh de status |
| `createdAt`/`updatedAt` | timestamp | convención del schema |

### `login_event` (schema `securitydb`)

`id` (uuid), `userId`, `email`, `role`, `loginAt`. Insertada por security-api en cada login exitoso (`/login` y `/loginBack`). Índice por (`loginAt`, `role`).

### `user_activity` (schema `recetali_receta`)

`email` PK, `role`, `lastSeenAt`. Upsert desde un filter del api-rest en cada request autenticada (costo mínimo: un upsert por request; se puede throttlear a 1/min por usuario en memoria).

### `service_status_event` (schema `recetali_receta`)

`id` (uuid), `service`, `status` (`UP`/`DOWN`), `at`. Solo se inserta cuando un health check detecta una **transición** de estado — permite responder "caído/operativo desde cuándo" sin guardar cada check.

## Backend A — Monitor WhatsApp

### transversal-recetalia-api (branch nuevo desde 2.x.y)

- `WhatsAppServiceImpl.sendMessage` pasa de `Mono<Void>` a devolver el **SID**.
- El use case de notificaciones (que ya conoce la prescription en curso) persiste la fila `whatsapp_message` vía R2DBC tras el envío exitoso.
- Endpoint interno nuevo `GET /api/whatsapp/status?sids=a,b,c` → consulta Twilio por SID (fetch individual o paginado) y devuelve `{sid, status, errorCode}[]`. Solo accesible por red interna docker (no se expone en nginx).
- Endpoint interno nuevo `GET /api/whatsapp/historic?from&to&page` → pagina la Messages API de Twilio (mensajes previos a la feature, sin vínculo).

### recetalia-api-rest (branch nuevo desde 2.x.y)

Grupo nuevo `/api/control-dashboard/whatsapp/*`, todo con `@PreAuthorize ROLE_MANAGEMENT`:

- `GET /` — lista paginada desde `whatsapp_message` JOIN prescription/patient/medic: fecha, paciente (nombre + teléfono), tipo, receta (id + code), médico, status, error. Filtros: rango de fechas, status, texto (paciente/teléfono/código de receta).
- `POST /refresh-status` — body: lista de SIDs visibles; llama al transversal, actualiza `status`/`errorCode`/`statusUpdatedAt` y devuelve los valores nuevos.
- `GET /summary` — enviados hoy/semana, % entregados, cantidad de fallidos (para las cards).
- `GET /historic` — proxy al transversal (mensajes viejos de Twilio, sin vínculo).

## Backend B — Monitor de infraestructura

Grupo `/api/control-dashboard/infra/*` en api-rest (`ROLE_MANAGEMENT`):

- `GET /services` — health checks HTTP paralelos (timeout 3s) contra lista configurable en yml: 4 frontends, api-rest (self), security-api, transversal (interno), sitio. Devuelve `{name, url, status UP/DOWN, latencyMs, since}`. Las transiciones UP↔DOWN se persisten en una tabla mínima `service_status_event` (`service`, `status`, `at`) para poder responder "caído desde".
- `GET /server-metrics` — DigitalOcean Monitoring API del droplet de prod: CPU %, RAM %, disco % (últimas 6h para mini-gráfico). Requiere `do-agent` instalado en el droplet (one-liner oficial) y token DO **read-only** en env.
- `GET /db-metrics` — DO API de la DB managed: CPU, conexiones activas, storage usado/total.
- `GET /api-metrics` — agrega de las 3 APIs vía Actuator interno (`http.server.requests`): requests totales, tasa 5xx, p95 por API. Actuator se habilita SOLO en red interna (sin ruta nginx pública).
- `GET /active-users` — activos últimos 15 min (`user_activity`) y logins de hoy (`login_event`), separados por rol: médicos, farmacias, prestadores (+gestión).

### security-api-recetalia (branch nuevo desde 2.x.y)

- Insert de `login_event` en login exitoso.
- Habilitar Actuator interno (metrics).

## UI — Gestión (branch nuevo desde 2.x.y)

Nueva sección **"Control"** en el menú (visible solo para `ROLE_MANAGEMENT`), ruta `/control`, con dos tabs siguiendo el patrón del dashboard de KPIs existente:

- **Tab WhatsApp**: 3-4 cards resumen (enviados hoy, semana, % entregados, fallidos) + tabla paginada con chips de color por status (verde=delivered/read, amarillo=queued/sent, rojo=failed/undelivered) y link al detalle de la receta. Botón "Refrescar status" (llama refresh-status con los SIDs de la página visible). Toggle "ver históricos" (lista Twilio sin vínculo).
- **Tab Infraestructura**: fila de semáforos por servicio (con "desde"), gauges CPU/RAM/disco del server, cards de DB (CPU, conexiones, storage), card de usuarios activos/logins por rol, mini-tabla de errores/latencia por API. Auto-refresh cada 60s mientras la pantalla está montada (se corta al salir).

## Seguridad y secrets

- Todos los endpoints nuevos: `ROLE_MANAGEMENT`.
- Transversal y Actuator: solo red interna docker; nada nuevo en nginx público salvo los paths `/api/control-dashboard/*` que ya van por api-rest.
- Token DO (read-only Monitoring) y credenciales Twilio: env vars vía `.env` del server (no commiteadas). En dev no se configuran → degradación.

## Manejo de errores / degradación

- Timeouts de Twilio/DO/Actuator → la card correspondiente muestra "sin datos" con el motivo; la pantalla nunca se rompe ni bloquea las demás cards (llamadas independientes, no secuenciales).
- En dev: Twilio inválido y sin DO → tab WhatsApp funciona contra la tabla local (sembrable con datos de prueba); métricas de server/DB muestran "no disponible en este ambiente".

## Testing

- Unit: persistencia y mapeo de `whatsapp_message`; agregación de summary; health checks con servidores mock (UP/DOWN/timeout); parsing de respuestas DO y Actuator; conteos de usuarios activos por rol.
- E2E en dev: sembrar `whatsapp_message` con SIDs reales viejos de la cuenta Twilio (el refresh de status puede probarse en dev apuntando temporalmente el endpoint de status a las credenciales reales de solo-lectura, o mockeado).
- Validación en prod post-deploy: primer WhatsApp real → aparece con receta vinculada; semáforos en verde; métricas DO pobladas.

## Deploy

1. Dev primero: DDL de las 3 tablas en la MySQL dev, build/test completo del flujo.
2. Prod: DDL en la DB managed (3 CREATE TABLE aditivos, sin riesgo), rebuild+deploy de transversal, api-rest, security-api y gestión; instalar `do-agent` en el droplet; token DO al `.env`.

## Fuera de alcance (v1)

- Webhooks de status de Twilio y alertas (email/notificación) — evolución natural si se necesita tiempo real.
- Backfill/inferencia del vínculo para los 8.700 mensajes históricos.
- Stack Prometheus/Grafana (opción B2) y retención de métricas > la que da DO (14 días).
- Métricas de latencia de los frontends SSR.
