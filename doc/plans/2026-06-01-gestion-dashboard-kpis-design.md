# Spec: Dashboard de KPIs en Gestión — 2026-06-01

> Workstream **C** de la tanda de 4 features (ver descomposición en el historial de brainstorming).
> Features A (Cadenas/Usuario Administrador) y B (Prestadores: Usuario de Consulta/Conexión) van en specs separados.

## Objetivo

Agregar a **gestion-recetadigital-app** (rol `ROLE_MANAGEMENT`) un **Dashboard** con la vista resumida de KPIs de la plataforma, y hacerlo la **pantalla por defecto** al ingresar. Requiere endpoints de agregación nuevos en **recetalia-api-rest** (hoy no existen).

## Alcance

Dashboard **a nivel plataforma** (Gestión ve todo el sistema), filtrado por un **período** seleccionable. Layout aprobado: **A — tarjetas KPI arriba + gráficos apilados** (tendencia ancha al medio, rankings abajo).

### Fuera de alcance

- KPIs por cadena/sucursal a nivel de un usuario administrador (eso es Workstream A).
- Exportación del dashboard a PDF/Excel (ya existe export en las secciones de detalle; no se replica acá).
- Cache/materialización de agregados (se evalúa solo si la query agrupada se vuelve lenta).
- Comparación entre períodos (período actual vs anterior).

## KPIs y definiciones

Todo acotado al **período** seleccionado (default: últimos 30 días).

### Tarjetas (fila superior)

| Tarjeta | Definición | Fuente |
|---|---|---|
| Prescripciones | recetas emitidas en el período | `COUNT` sobre `prescription.created_at` en rango |
| Dispensaciones | dispensaciones en el período (status `DISPENSED`) | `COUNT` sobre `dispensation.created_at` en rango |
| Tasa de dispensación | `dispensaciones / prescripciones` del período (%) | derivado en backend |
| Médicos activos | médicos distintos que emitieron ≥1 receta en el período | `COUNT(DISTINCT prescription.medic_id)` |
| Farmacias activas | farmacias distintas con ≥1 dispensación en el período | `COUNT(DISTINCT dispensation.pharmacy_id)` |
| Pacientes | pacientes distintos con ≥1 receta en el período | `COUNT(DISTINCT prescription.patient_id)` |

> Decisión: **"activos" = actuaron en el período** (no totales históricos).

### Gráficos

- **Tendencia de actividad** (líneas): serie diaria `{ fecha, prescripciones, dispensaciones }` a lo largo del período.
- **Top medicamentos** (barras): top 10 medicamentos DNMA más **dispensados** en el período. (Decisión: por dispensación, no por prescripción.)
- **Dispensaciones por cadena** (dona): agrupadas por `Franchise`, con bucket **"Sin cadena"** para farmacias sin `franchise_id`.

## Interacción

- **Barra de período**: presets (Hoy, 7 días, 30 días, Mes actual, Rango personalizado) + default **últimos 30 días**. Cambiar el período re-consulta el backend.
- **Drill-down (tarjetas y elementos de gráfico clickeables)** — navegan a la sección de detalle llevando el período (y filtro puntual) como **query params**:

  | Click en | Destino | Query params |
  |---|---|---|
  | Prescripciones | `/prescriptions` | `startDate`, `endDate` |
  | Dispensaciones | `/dispensations` | `startDate`, `endDate` |
  | Médicos activos | `/medics` | `startDate`, `endDate` |
  | Farmacias activas | `/pharmacies` | `startDate`, `endDate` |
  | Pacientes | `/patients` | `startDate`, `endDate` |
  | Barra de un medicamento | `/dispensations` | `startDate`, `endDate`, `medicineId` |
  | Porción de una cadena | `/dispensations` | `startDate`, `endDate`, `franchiseId` |

  > **Caveat**: las listas destino reciben el filtro vía query params. `dispensations` ya soporta búsqueda por fecha/cadena; las listas que hoy **no** leen estos params necesitarán un ajuste menor (leer `ActivatedRoute.queryParams` al iniciar y auto-aplicar el filtro). Se detalla por lista en el plan de implementación.

- **Estados**: spinner durante la carga; mensaje de error con patrón `catchError` existente; "sin datos" cuando el período no tiene actividad.

## Arquitectura

### Backend — recetalia-api-rest (hexagonal, mismo patrón que `Dispensation`)

Capas (todo bajo `com.recetalia.api.application`):

- **Inbound adapter**: `controller/DashboardController.java`
  - `GET /api/dashboard/summary?startDate=<ISO>&endDate=<ISO>` → `ResponseEntity<ApiResponse<DashboardSummaryResponse>>`
- **Puerto de aplicación**: `service/DashboardService.java` (interface) + `service/impl/DashboardServiceImpl.java`
  - Orquesta las queries de agregación, calcula la tasa, arma el `DashboardSummaryResponse`.
- **Puerto de salida (persistencia)**: `domain/repository/DashboardRepository.java`
  - Spring Data JPA con **queries nativas** de agregación (mismo estilo que `DispensationRepository`), devolviendo **projections** (interfaces de Spring Data) por bloque:
    - counts base (prescripciones, dispensaciones, distinct médicos/farmacias/pacientes)
    - serie diaria (`GROUP BY DATE(...)`)
    - top medicamentos (`GROUP BY` medicamento `ORDER BY COUNT DESC LIMIT 10`)
    - por cadena (`LEFT JOIN franchise ... GROUP BY franchise`)
  - Se ancla a una entidad existente para satisfacer Spring Data (p.ej. `Dispensation`), o repo `@Repository` dedicado con `@Query(nativeQuery=true)`.
- **DTOs (salida)**: `dto/response/`
  - `DashboardSummaryResponse` { `counts`, `activityTrend[]`, `topMedicines[]`, `byChain[]` }
  - `DashboardCounts` { prescriptions, dispensations, dispensationRate, activeMedics, activePharmacies, patients }
  - `ActivityTrendRow` { date, prescriptions, dispensations }
  - `MedicineCountRow` { medicineId, medicineName, count }
  - `ChainCountRow` { franchiseId (nullable), franchiseName ("Sin cadena" si null), count }
  - Mapeo de projections → DTOs en el service (o `dto/mapper/DashboardMapper` MapStruct si aplica).
- **Sin cambios en entidades** existentes.

**Autorización**: endpoint autenticado. Restringir a `ROLE_MANAGEMENT` si la config de seguridad lo permite sin romper el patrón actual (verificar en implementación: hoy varios endpoints están solo `authenticated()`).

**Validación**: `startDate`/`endDate` requeridos, `startDate <= endDate`; si falta, default a últimos 30 días (decidir en impl: default en backend o siempre enviado por el front). Recomendado: el front siempre envía ambos.

### Frontend — gestion-recetadigital-app (NgModule, lazy `HomeModule`, PrimeNG 17)

Nuevo feature folder `src/app/pages/application/home/dashboard/`:

- `dashboard.component.{ts,html,scss}` — contenedor: barra de período + grid de tarjetas + 3 gráficos. Carga vía `DashboardService`, re-fetch al cambiar período.
- `kpi-card/` — componente de presentación reutilizable (label, valor, ícono, opcional `routerLink`/click).
- Gráficos con **PrimeNG Chart** (`p-chart`, envuelve **Chart.js**) — se agrega dependencia `chart.js`. Sin segunda librería de UI.

Servicio: `services/dashboard.service.ts` — un `GET` al endpoint agrupado pasando `startDate`/`endDate`; desenvuelve `ApiResponse<DashboardSummaryResponse>` con el patrón `map`/`catchError` existente. Modelos en `model/response/dashboard-*.ts`.

Routing y navegación:
- Nueva ruta hija `dashboard` en `home-routing.module.ts`.
- **Cambiar el redirect por defecto** de `dnma-medicines` → `dashboard`.
- Agregar ítem **"Dashboard"** como **primero** en `sidebar.component.html` (con ícono).
- Declarar los componentes nuevos en `home.module.ts`; importar `ChartModule` de PrimeNG.

## Flujo de datos

```
[Sidebar] --(default)--> /dashboard
DashboardComponent
  -> on init / on period change:
       DashboardService.getSummary(startDate, endDate)
         -> GET /api/dashboard/summary
             DashboardController -> DashboardService(impl) -> DashboardRepository (native aggregate queries)
         <- ApiResponse<DashboardSummaryResponse>
  -> render tarjetas + p-chart (tendencia, top medicamentos, por cadena)
  -> click tarjeta/elemento -> router.navigate(destino, { queryParams: {startDate, endDate, ...} })
```

## Testing

- **Backend (TDD)**: foco en las queries de agregación (lo más propenso a error). Tests de repositorio con dataset conocido verificando counts, distinct, serie diaria (incl. días sin actividad), top-N y agrupación por cadena (incl. "Sin cadena"). Test de service para el cálculo de la tasa (incl. división por cero → 0%).
- **Frontend**: test del `DashboardService` (mapeo de la respuesta) y del armado de queryParams de drill-down. Componentes de gráfico con datos mínimos (la app hoy mayormente omite tests de UI; mantener al menos el service).

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Query agrupada lenta con mucho volumen | Empezar agrupada; si tarda, separar por bloque y/o índices en `created_at` |
| Listas destino que no leen query params | Ajuste menor por lista (leer `queryParams` al iniciar); enumerar en el plan |
| `ROLE_MANAGEMENT` no enforced hoy (deuda conocida) | No se resuelve acá; endpoint queda al menos `authenticated()` |
| Zona horaria en agregación por día | Definir TZ de `DATE(created_at)` en impl (UTC vs local) y documentarlo |

## Criterios de éxito

- [ ] `GET /api/dashboard/summary?startDate&endDate` devuelve counts, serie diaria, top 10 medicamentos y agrupación por cadena, en `ApiResponse`.
- [ ] La tasa de dispensación se calcula correctamente (y 0% si no hay prescripciones).
- [ ] El dashboard renderiza tarjetas + 3 gráficos y re-consulta al cambiar el período.
- [ ] `/dashboard` es la ruta por defecto y aparece primero en el menú.
- [ ] Las tarjetas/elementos navegan al detalle con el período (y filtro) como query params.
- [ ] Las queries de agregación tienen tests que pasan.

## Decisiones tomadas

| # | Tema | Decisión |
|---|---|---|
| 1 | KPIs | Actividad + tasa + adopción + rankings (los 4 grupos) |
| 2 | Período | Selector presets + rango custom, default últimos 30 días |
| 3 | "Activos" | Actuaron en el período (no totales históricos) |
| 4 | Top medicamentos | Por dispensación |
| 5 | Layout | A — tarjetas arriba + gráficos apilados |
| 6 | Tarjetas clickeables | Sí, drill-down al detalle con período como query params |
| 7 | Charts lib | PrimeNG Chart (Chart.js) |
| 8 | Backend API | Un endpoint agrupado (`/api/dashboard/summary`) |
| 9 | Arquitectura backend | Hexagonal, mismo patrón que `Dispensation` (controller → service iface+impl → domain/repository, DTOs/projections) |
