# Spec: Dashboard en el app de Farmacias (scopeado) — 2026-06-01

> Workstream **A2** (de la tanda de cadenas). Complementa A1 (vista consolidada de cadena). Reutiliza el patrón del dashboard de Gestión (Layout A) pero **centrado en dispensaciones**.

## Objetivo

Agregar un **Dashboard** al `farmacias-recetalia-app`, centrado en **dispensaciones**, **scopeado por rol**:
- `ROLE_PHARMACY_ADMIN` → métricas de **toda su cadena**, con desglose por sucursal. Es su **pantalla por defecto** al ingresar.
- `ROLE_PHARMACY` → métricas de **su propia farmacia**. Disponible como **ítem de menú** (su landing actual `prescriptions/search` se mantiene).

## Alcance

### En alcance
1. Endpoint nuevo en `recetalia-api-rest`, dispensation-focused y scopeado: `GET /api/dashboard/pharmacy-summary?pharmacyId=&franchiseId=&startDate=&endDate=`.
2. `farmacias-recetalia-app`: dependencia `chart.js` + `ChartModule`; `DashboardComponent` (tarjetas + gráficos + barra de período); `DashboardService`; ítem de menú "Dashboard"; **landing por-rol** (admin → dashboard).
3. Resolución de nombres de medicamento vía DNMA (reusando el fix con fallback AMPP ya implementado en el dashboard de Gestión).

### Fuera de alcance (explícito)
- KPIs de prescripciones/médicos/pacientes (no aplican a una farmacia; eso es el dashboard de Gestión).
- Export del dashboard a PDF/Excel.
- Modificar el endpoint `/api/dashboard/summary` (Gestión) — queda intacto.
- Drill-down desde las tarjetas (se puede sumar después).

## KPIs (centrados en dispensaciones)

Todo acotado al **período** seleccionado (default últimos 30 días), con el mismo selector de presets + rango del dashboard de Gestión.

| Bloque | Contenido | Scope |
|---|---|---|
| **Tarjeta: Dispensaciones** | total del período **+ delta** (▲/▼ %) vs período anterior de igual duración | farmacia o cadena |
| **Tendencia** (líneas) | dispensaciones por día | farmacia o cadena |
| **Top medicamentos** (barras) | top 10 medicamentos más dispensados (nombre resuelto vía DNMA, fallback AMPP) | farmacia o cadena |
| **Por sucursal** (barras/dona) | dispensaciones por sucursal de la cadena | **solo admin** (cuando hay `franchiseId`) |

> Dispensaciones válidas: `status='DISPENSED' AND deletedAt IS NULL` (igual que el dashboard de Gestión).

## Diseño

### Backend — recetalia-api-rest (hexagonal, reutiliza el patrón del dashboard)

**Nuevo endpoint** en `DashboardController`:
```
GET /api/dashboard/pharmacy-summary?pharmacyId=<opt>&franchiseId=<opt>&startDate=<ISO>&endDate=<ISO>
```
- Reglas de scope: si viene `pharmacyId` → filtra esa farmacia; si viene `franchiseId` → filtra todas las sucursales de la cadena (`pharmacy.franchiseId = :franchiseId`). Al menos uno debe venir.
- Devuelve (en `GenericResponse<PharmacySummaryResponse>`):
  - `dispensations` (long) + `previousDispensations` (long, período anterior de igual duración) → el front calcula el delta.
  - `trend`: lista `{ date, dispensations }` (serie diaria, con relleno de días en cero).
  - `topMedicines`: top 10 `{ medicineId, medicineName, count }` (resolución DNMA con fallback AMPP, reutilizando la lógica del `DashboardServiceImpl`).
  - `byBranch`: lista `{ pharmacyId, pharmacyName, count }` (solo poblado cuando hay `franchiseId`; vacío para una sola farmacia).

**Implementación**: nuevo método en `DashboardService`/`Impl` (`getPharmacySummary(pharmacyId, franchiseId, startDate, endDate)`) + queries nativas en `DashboardRepository` análogas a las existentes pero **scopeadas** por `pharmacyId`/`franchiseId` (filtros `(:pharmacyId IS NULL OR d.pharmacyId = :pharmacyId)` y `(:franchiseId IS NULL OR ph.franchiseId = :franchiseId)`). Reusa el helper `buildTopMedicines` (DNMA + AMPP) y el relleno de tendencia ya escritos.

**Autorización**: endpoint `authenticated()` (cualquier farmacia/admin logueado). El front pasa el scope correcto; no se confía en datos cross-cadena más allá de lo que ya hace el endpoint de búsqueda.

**Sin cambios** en entidades ni en el endpoint de Gestión.

### Frontend — farmacias-recetalia-app (NgModule, PrimeNG)

- Agregar `chart.js` (dependencia) + `ChartModule` (`primeng/chart`) a `home.module.ts`.
- `services/dashboard.service.ts` (nuevo): `getPharmacySummary({ pharmacyId?, franchiseId?, startDate, endDate })` → `PharmacySummaryResponse`. Patrón `ApiResponse<T>` con `map`/`catchError`.
- `pages/application/home/dashboard/dashboard.component.{ts,html,scss}` (nuevo): 
  - En `ngOnInit`, `authService.getCurrentUser()` → si `role === 'ROLE_PHARMACY_ADMIN'` usa `franchiseId`; si no, usa `pharmacyId`.
  - Barra de período (presets + rango, default 30 días) reusando el patrón del dashboard de Gestión.
  - Tarjeta de dispensaciones con delta; gráfico de tendencia (líneas); top medicamentos (barras); **por sucursal** (barras/dona) visible solo si hay `franchiseId`.
  - Componente de tarjeta KPI reutilizable (o uno simple inline).
- **Landing por-rol**: como Angular no permite `redirectTo` dinámico, un componente chico `LandingRedirectComponent` en el path vacío (o un `CanActivate`) que en `ngOnInit` lee el rol y hace `router.navigate(['dashboard'])` para admin o `['prescriptions/search']` para el resto. La ruta `dashboard` queda disponible para ambos roles.
- Menú (sidebar): ítem **"Dashboard"** visible para ambos roles (`ROLE_PHARMACY` y `ROLE_PHARMACY_ADMIN`).

### Flujo

```
Login:
  ROLE_PHARMACY_ADMIN  → LandingRedirect → /dashboard (scope = franchiseId)
  ROLE_PHARMACY        → LandingRedirect → /prescriptions/search ; "Dashboard" en menú (scope = pharmacyId)

DashboardComponent:
  getCurrentUser() → { role, pharmacyId, franchiseId }
  scope = admin ? { franchiseId } : { pharmacyId }
  GET /api/dashboard/pharmacy-summary?<scope>&startDate&endDate
  render: tarjeta+delta, tendencia, top medicamentos, (por sucursal si admin)
```

## Testing

- **Backend (TDD sobre la lógica)**: test de `getPharmacySummary` con repo + DNMA mockeados — cálculo del delta (incl. previo 0), relleno de días en cero, `byBranch` vacío cuando no hay `franchiseId`. El SQL nativo scopeado se valida con smoke test (curl con un JWT de farmacia y de admin).
- **Frontend**: test del `DashboardService` (armado de params según scope) si Karma corre; si no, el build es el gate (como en Gestión).
- **Manual/E2E**: admin → cae en dashboard, ve consolidado de cadena + desglose por sucursal; farmacia normal → dashboard por menú con datos de su sucursal.

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Un `ROLE_PHARMACY` sin cadena no tiene `franchiseId` | Usa `pharmacyId`; `byBranch` queda vacío/oculto |
| Endpoint scopeado mal usado (cross-cadena) | El front pasa el scope del propio usuario; mismo nivel de confianza que el endpoint de búsqueda existente |
| TZ en agregación por día | Misma convención que el dashboard de Gestión (documentada en su spec) |
| `chart.js` peer-deps en farmacias-app | Instalar con `--legacy-peer-deps` como hace el proyecto |

## Criterios de éxito

- [ ] `GET /api/dashboard/pharmacy-summary` devuelve dispensaciones+delta, tendencia, top medicamentos y (con `franchiseId`) por sucursal.
- [ ] Admin cae por defecto en el dashboard con datos consolidados de su cadena + desglose por sucursal.
- [ ] Farmacia normal ve el dashboard (por menú) con datos de su sucursal; sin bloque "por sucursal".
- [ ] Nombres de medicamento resueltos (incl. casos AMPP).
- [ ] Backend `./gradlew build` y frontend `ng build` en verde; tests de la lógica del summary en verde.

## Decisiones tomadas

| # | Tema | Decisión |
|---|---|---|
| 1 | Foco | Dispensaciones (no prescripciones) |
| 2 | Scope | `pharmacyId` (farmacia) o `franchiseId` (cadena), según rol |
| 3 | Landing | Admin → dashboard por defecto; farmacia normal → landing actual + menú |
| 4 | KPIs | Dispensaciones+delta, tendencia, top medicamentos, por sucursal (admin) |
| 5 | Endpoint | Nuevo `/api/dashboard/pharmacy-summary` (no se toca `/summary`) |
| 6 | Reuso | Patrón de gráficos + período de Gestión; resolución DNMA con fallback AMPP |
