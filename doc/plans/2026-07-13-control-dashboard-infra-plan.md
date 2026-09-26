# Monitor de Infraestructura (Dashboard de Control) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tab "Infraestructura" del dashboard de Control en Gestión: salud de servicios de PROD, recursos del server de apps y de la DB (API de DigitalOcean), errores/latencia de las APIs y usuarios activos por rol.

**Architecture:** api-rest agrega `/api/control-dashboard/infra/*` (ya protegido por el matcher `ROLE_ROLE_MANAGEMENT` existente): health checks HTTP paralelos a URLs configurables (apuntan a PROD), cliente de la API de Monitoring de DO (droplet + DB managed, token read-only por env), agregación de Actuator interno de las 3 APIs, y usuarios activos (tabla `user_activity` + endpoint interno de `login_event` en security-api). Spec: [2026-07-13-control-dashboard-design.md](2026-07-13-control-dashboard-design.md) sección B.

**Decisión de targets (Pablo, 2026-07-13):** los TARGETS monitoreados son los de **producción** aunque el código corra en dev — health checks a `*.recetalia.com` prod, droplet `.217`, DB managed de DO. Excepción inherente: métricas Actuator y usuarios logueados miden el ambiente donde corre el código (dev mide dev; miden prod cuando se deployee a prod). Las URLs/IDs van en config para poder cambiarlas por ambiente si algún día se quiere.

**Tech Stack:** Spring MVC + JPA (api-rest, security-api), API DigitalOcean v2 (Bearer token), Spring Boot Actuator, Angular 18 + PrimeNG.

**Branching:** mismo branch `feat/control-dashboard` (ya existe en api-rest y gestion; crearlo desde `2.x.y` en security-api-recetalia). NUNCA tocar `2.x.y`; merge solo con OK de Pablo.

**Prerequisitos externos (Pablo):** (a) token DO **read-only** → va al `.env` de LOCAL como `DO_API_TOKEN`; (b) OK para instalar `do-agent` en el droplet prod `.217` (necesario para métricas de RAM/disco del droplet; CPU/bandwidth salen sin agent).

---

### Task 0: Branch security-api + DDL en dev

- [ ] **0.1** `cd security-api-recetalia && git checkout 2.x.y && git pull && git checkout -b feat/control-dashboard`
- [ ] **0.2** DDL en MySQL dev (LOCAL):

```sql
-- schema recetali_receta
CREATE TABLE IF NOT EXISTS service_status_event (
  id varchar(36) NOT NULL,
  service varchar(60) NOT NULL,
  status varchar(10) NOT NULL, -- UP | DOWN
  at timestamp NOT NULL,
  PRIMARY KEY (id),
  KEY idx_sse_service_at (service, at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_activity (
  email varchar(200) NOT NULL,
  role varchar(60) NOT NULL,
  lastSeenAt timestamp NOT NULL,
  PRIMARY KEY (email),
  KEY idx_ua_lastSeen (lastSeenAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- schema securitydb
CREATE TABLE IF NOT EXISTS login_event (
  id varchar(36) NOT NULL,
  userId bigint NOT NULL,
  email varchar(200) NOT NULL,
  role varchar(60) NOT NULL,
  loginAt timestamp NOT NULL,
  PRIMARY KEY (id),
  KEY idx_le_loginAt_role (loginAt, role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

- [ ] **0.3** Verificar con DESCRIBE las 3 tablas.

---

### Task 1: api-rest — cliente DigitalOcean Monitoring

**Files:** Create `infrastructure/adapter/digitalocean/DoMonitoringClient.java` (interface) + `impl/DoMonitoringClientImp.java` + DTOs `DoMetricSeries.java`; Test `DoMonitoringClientImpTest.java`.

- Config por properties (con env override): `monitoring.do.token` (`DO_API_TOKEN`), `monitoring.do.droplet-id` (`DO_DROPLET_ID`), `monitoring.do.db-cluster-uuid` (`DO_DB_CLUSTER_UUID`).
- Endpoints DO v2 (verificar contra docs oficiales al implementar — WebFetch a https://docs.digitalocean.com/reference/api/digitalocean/ sección monitoring):
  - Droplet: `GET /v2/monitoring/metrics/droplet/cpu|memory_utilization_percent|filesystem_free?host_id={dropletId}&start={unix}&end={unix}` (memory/filesystem requieren do-agent).
  - DB managed: `GET /v2/databases/{uuid}` (estado/conexiones/size según payload) y/o endpoints de métricas de DB si existen — el implementador verifica y adapta; si DO no expone una métrica, se devuelve null y la card muestra "sin datos".
- `RestTemplate` con el bean existente (ya tiene timeouts 3s/10s); header `Authorization: Bearer ${token}`.
- Devuelve series simplificadas: `{metric, points: [{ts, value}], latest}` para las últimas 6h.
- **Degradación**: token vacío o error HTTP → devolver `null`/lista vacía SIN excepción (el service arma la card "no disponible"). Tests: parseo de JSON de ejemplo de DO (fixture hardcodeada) + degradación con token vacío.

---

### Task 2: api-rest — health checks + transiciones

**Files:** Create entity `ServiceStatusEvent` + repo (JPA, tabla `service_status_event`), `HealthCheckService` + impl, DTO `ServiceHealth {name, url, status, latencyMs, since}`. Test `HealthCheckServiceImplTest`.

- Lista de targets en `application.yml` (override por env en compose):

```yaml
monitoring:
  services:
    - name: medicos
      url: https://medicos.recetalia.com/
    - name: farmacias
      url: https://farmacias.recetalia.com/
    - name: prestadores
      url: https://prestadores.recetalia.com/
    - name: gestion
      url: https://gestion.recetalia.com/
    - name: sitio
      url: https://recetalia.com/
    - name: api-rest
      url: https://api.recetalia.com/recetalia-api-rest/api/actuator/health
    - name: security-api
      url: https://api.recetalia.com/security-api-recetalia/api/actuator/health
```

(⚠️ los dos últimos: si los paths de actuator públicos no existen en prod aún, usar cualquier endpoint liviano que devuelva <500 — p.ej. el 401 de un endpoint autenticado CUENTA como UP: el check considera UP todo status HTTP < 500 recibido en <3s. Documentarlo.)
- Checks en paralelo (ExecutorService o CompletableFuture, timeout 3s por check, `HttpClient` de Java 11+ para no compartir el RestTemplate).
- Transiciones: comparar contra el último estado conocido (query del último evento por service); si cambió → INSERT `service_status_event`. `since` = timestamp del último cambio (o del primer check si no hay eventos).
- Tests: mock del checker HTTP — UP/DOWN/timeout; verifica que solo las transiciones insertan evento.

---

### Task 3: security-api — login_event + endpoint interno + actuator

**Files:** entity `LoginEvent` + repo; insert en `UserService.authenticate` tras generar el JWT (best-effort: try/catch con log, un fallo de auditoría NO rompe el login); endpoint interno `GET /api/auth/login-stats?sinceHours=24` → `[{role, count}]` (agrupado por rol) — **sin auth adicional** pero verificar cómo la security config del security-api trata sus endpoints (si todo /api/auth/* es público, ok — lo consume api-rest por red interna); habilitar Actuator (dependencia `spring-boot-starter-actuator` si falta + `management.endpoints.web.exposure.include=health,metrics` en yml). Test: insert de login_event en authenticate exitoso (mock repo), no-insert en credenciales inválidas, login-stats agrupa por rol.

---

### Task 4: api-rest — user_activity + actuator propio + agregación de métricas de APIs

**Files:**
- Entity `UserActivity` + repo (upsert nativo `INSERT ... ON DUPLICATE KEY UPDATE`), filter `UserActivityFilter extends OncePerRequestFilter` (package `infrastructure/filter/`): en requests autenticadas extrae email+role del JWT (SecurityContext), throttle en memoria (ConcurrentHashMap email→lastWrite, min 60s entre upserts). Registrarlo en la security chain o como `@Component`.
- Actuator en api-rest: dependencia + `management.endpoints.web.exposure.include=health,metrics`. ⚠️ ¡El matcher de security debe permitir `/actuator/health` interno pero NO exponer metrics públicamente! Verificar qué rutas publica nginx: `/recetalia-api-rest/api/*` — actuator queda en `/actuator` (fuera del path público) → inaccesible desde afuera, accesible por red interna docker. Confirmarlo y documentarlo.
- `ApiMetricsService`: consulta `http://localhost:{port}/actuator/metrics/http.server.requests` (propio), `http://security-api-recetalia:8091/actuator/metrics/http.server.requests` y `http://transversal-recetalia-api:8093/actuator/metrics/http.server.requests`.
- **Transversal — actuator (única modificación permitida al transversal en este plan):** en su branch `feat/control-dashboard`, agregar `spring-boot-starter-actuator` (módulo app-service) + `management.endpoints.web.exposure.include=health,metrics` en su yml. Para WebFlux las métricas HTTP son `http.server.requests` igual. Nada más se toca. Parsear measurements: COUNT, TOTAL_TIME, MAX + tag `status` 5xx (segunda query con `?tag=status:500` etc. — simplificar: count total, mean = total/count, max, y 5xx sumando counts de tags outcome:SERVER_ERROR). Degradación por API caída → "sin datos".
- Endpoint interno de logins: consumer REST a security-api (`${external.api.security-api-recetalia}/api/auth/login-stats`).
- Tests: upsert throttle (2 requests seguidas → 1 upsert), agregación con fixtures JSON de actuator, degradación.

---

### Task 5: api-rest — controller `/api/control-dashboard/infra/*`

**Files:** `ControlInfraController` + `ControlInfraService` + DTOs respuesta. Test del service.

- `GET /services` → List<ServiceHealth> (Task 2).
- `GET /server-metrics` → CPU/RAM/disco del droplet (Task 1), últimas 6h + latest.
- `GET /db-metrics` → métricas DB managed (Task 1).
- `GET /api-metrics` → agregación Actuator (Task 4).
- `GET /active-users` → `{active15m: [{role, count}] (user_activity), loginsToday: [{role, count}] (security-api)}` — roles normalizados a MEDIC/PHARMACY/MEDICAL_PROVIDER/MANAGEMENT.
- Cada endpoint con try/catch de degradación → campos null + `available:false` por card, NUNCA 500 por una dependencia caída. Mismo envoltorio GenericResponse. El matcher `/api/control-dashboard/**` YA cubre esto.

---

### Task 6: gestion — service + componente Infra + sidebar

**Files:** ampliar `control-dashboard.service.ts` (5 métodos infra + modelos en `infra-monitor-response.ts` + specs), crear `home/control/infra-monitor/infra-monitor.component.{ts,html,scss}`, ruta `control/infra`, item "Infraestructura" en la sección Control del sidebar.

- UI: fila de semáforos (verde/rojo + latencia + "desde"), cards de server (CPU/RAM/disco con latest + mini indicación de tendencia), cards de DB, tabla chica de APIs (requests, 5xx, media, max), card de usuarios (activos 15min y logins hoy por rol). Card con `available:false` → "Sin datos".
- Auto-refresh cada 60s con `interval` de RxJS + `takeUntil(destroy$)` y `OnDestroy` (acá SÍ hay suscripción persistente — no olvidar limpieza).
- Specs del service (params + unwrap). Build verde.

---

### Task 7: Deploy + validación en dev (targets prod)

- Requiere `DO_API_TOKEN` en el `.env` de LOCAL + `DO_DROPLET_ID`/`DO_DB_CLUSTER_UUID` (obtenibles vía API con el token: `GET /v2/droplets` y `GET /v2/databases`) + `do-agent` instalado en `.217` (con OK de Pablo: `curl -sSL https://repos.insights.digitalocean.com/install.sh | sudo bash` en el droplet).
- compose dev98: agregar envs `DO_API_TOKEN`, `DO_DROPLET_ID`, `DO_DB_CLUSTER_UUID` al servicio api-rest (+ los `monitoring.services` targets ya van en el yml commiteado apuntando a prod).
- Deploy: security-api + api-rest + gestion a LOCAL (build serial).
- Validación por curl con token gestión: `/infra/services` (semáforos de prod en UP), `/server-metrics` (CPU real del .217), `/db-metrics`, `/api-metrics` (datos del stack dev), `/active-users` (tras un login de prueba), 403 con rol farmacia.
- Nota anti-sorpresa: los health checks salen del `.98` hacia URLs prod tras Cloudflare — tráfico GET mínimo cada carga del dashboard (no hay polling server-side en v1; solo se chequea cuando el dashboard lo pide).

---

## Notas para el ejecutor

- Reglas de siempre: nunca `2.x.y`, imágenes solo `:dev`, no tocar el transversal en este plan, no "arreglar" el Twilio/schedulers de dev.
- El matcher `hasAuthority("ROLE_ROLE_MANAGEMENT")` ya protege `/api/control-dashboard/**` — no duplicar seguridad.
- El token DO es secreto: solo `.env` del server (gitignored) y `@Value` con default vacío → degradación limpia sin token.
- Si la API de DO no expone alguna métrica esperada (p.ej. RAM sin do-agent), la card correspondiente muestra "sin datos" — no bloquear el resto.
