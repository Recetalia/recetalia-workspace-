# Spec: Pacientes por sexo y edad en el Dashboard de Gestión — 2026-07-21

## Objetivo

Agregar al dashboard de **gestion-recetadigital-app** una sección **"Pacientes por sexo y edad"**: pirámide poblacional de los pacientes con actividad en el período seleccionado. Extiende el endpoint agrupado existente de **recetalia-api-rest**.

## Alcance

- **Población**: pacientes **distintos** con ≥1 receta (`prescription`) en el rango `startDate`/`endDate` del dashboard. Se recalcula al cambiar el período.
- **Visualización**: pirámide poblacional — barras horizontales espejadas, Hombres (izquierda, valores negativos) vs Mujeres (derecha), franjas etarias en Y.
- **Franjas etarias**: `0-17`, `18-30`, `31-45`, `46-60`, `61-75`, `76+`.
- **Sin dato (visible)**: leyenda bajo el chart: "N pacientes sin dato de sexo o edad".

### Fuera de alcance
- Drill-down desde la pirámide a la lista de pacientes.
- Endpoint nuevo o filtros propios de la sección.

## Realidad de los datos (verificado en DB PRE 2026-07-21)

| Campo | Situación |
|---|---|
| `patient.sex` (VARCHAR) | `UNKNOWN` 731, `FEMALE` 688, `MALE` 584, `NO_APPLY` 3, `NULL` 5 → ~37% sin sexo útil |
| `patient.birthdate` (VARCHAR) | 1269 `YYYY-MM-DD` válidos; **736 con el string literal `"Invalid date"`**; 4 fallback `Instant.now()` (fecha de alta); 2 ISO datetime |

**Reglas de limpieza (en la query):**
- Sexo ∉ {`MALE`, `FEMALE`} → sin dato.
- `birthdate` que no matchea `^[0-9]{4}-[0-9]{2}-[0-9]{2}` → sin dato.
- Edad calculada `TIMESTAMPDIFF(YEAR, STR_TO_DATE(LEFT(birthdate,10),'%Y-%m-%d'), CURDATE())`; fuera de 0–110 → sin dato.
- Un paciente cuenta en `noDataCount` si le falta **cualquiera** de los dos datos.

## Backend — recetalia-api-rest

- **Sin endpoint nuevo**: se extiende `GET /api/dashboard/summary`.
- `DashboardSummaryResponse` suma `patientDemographics`:
  ```json
  { "rows": [ { "ageRange": "0-17", "male": 12, "female": 15 }, ... ],
    "noDataCount": 37 }
  ```
  `rows` siempre trae las 6 franjas en orden (0 si vacía).
- `DashboardRepository`: query nativa nueva (mismo patrón que las existentes): `JOIN prescription → patient` en el rango, `deletedAt IS NULL` en ambas, `COUNT(DISTINCT patient.id)` agrupado por franja (CASE) y sexo; más un count de "sin dato".
- El `@Cacheable` del summary cubre el campo nuevo sin cambios.

## Frontend — gestion-recetadigital-app

- Modelo `PatientDemographics` en `dashboard-summary-response.ts`.
- Nueva sección en `dashboard.component.{ts,html}` (mismo patrón que los charts existentes, sin componente nuevo): `p-chart` tipo `bar`, `indexAxis: 'y'`, dataset Hombres en negativo, tooltips/ticks con `Math.abs`.
- Ubicación: después de "Tipo de receta", antes de "Distribución Geográfica".
- Leyenda "sin dato" bajo el chart.

## Testing

- Backend: test de service (armado del DTO, franjas vacías en 0) siguiendo el patrón de tests existente del dashboard.
- Frontend: patrón actual (mapeo del service); build SSR verde.

## Git y deploy

1. Rama `feat/dashboard-pacientes-2026-07-21` en ambos repos.
2. Merge a la línea principal de cada repo (api-rest: `main`; gestion-app: `2.x.y` — verificar dónde viven los tags), push.
3. Tag **`2.1.2`** en ambos repos.
4. Deploy con `deploy-recetalia` a **PRE y PROD** (stacks del `.217`).
5. Smoke test: `gestionpre.recetalia.com/dashboard` y `gestion.recetalia.com/dashboard`.

## Decisiones

| # | Tema | Decisión |
|---|---|---|
| 1 | Población | Activos en el período (≥1 receta), no todos los registrados |
| 2 | Visualización | Pirámide poblacional única |
| 3 | Franjas | 0-17 / 18-30 / 31-45 / 46-60 / 61-75 / 76+ |
| 4 | Datos sucios | Excluir a "sin dato" con contador visible (no inventar buckets) |
| 5 | API | Extender `/api/dashboard/summary`, sin endpoint nuevo |
| 6 | Release | Merge + tag 2.1.2 + deploy PRE y PROD |
