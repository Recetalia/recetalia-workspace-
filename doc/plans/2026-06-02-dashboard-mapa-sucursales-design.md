# Dashboard — Mapa selector de sucursales (cluster 03c)

**Fecha:** 2026-06-02
**Rama:** `feature/dashboard-kpis` (gestion-recetadigital-app + recetalia-api-rest)
**Origen:** docx "RC - Ajustes DEV - 02_06_25.docx", punto 03c.

## Objetivo

Reemplazar el bloque "Por localidad" (bar chart) del dashboard de gestión por un
**mapa SVG selector de sucursales**: localiza geográficamente las sucursales de
farmacia y permite seleccionar una. Las dispensaciones se siguen viendo en el
**listado** (no en el mapa). Seleccionar una sucursal navega a Dispensaciones
filtrado por esa farmacia.

## Decisiones (validadas con el usuario)

- **Un mapa con drill-down** (no dos mapas ni tabs).
- **SVG + GeoJSON inline, sin librería externa** (SSR-safe, sin tiles).
- Sectores con 0 sucursales: **clickeables igual** (gris claro).
- Click en departamento: **aplica filtro a nivel departamento** (zoom + lista de
  sucursales del depto). Montevideo además dibuja sus barrios como contexto.
- Datos: **sucursales ubicadas por la lat/lng de su localidad** (`addressLocalityId`).
- Selección de sucursal → `/dispensations?pharmacyId=…`.

## Datos (verificados en pre-prod)

- `regions` = los 19 departamentos de Uruguay; nombres idénticos al GeoJSON.
- `localities` = sub-localidades por departamento (Montevideo: 68); con lat/lng reales.
- 335 farmacias, **100% con `addressLocalityId`** → join limpio a localidad/depto.
- Los pins se ubican por lat/lng de la localidad (no por match de nombre), por lo
  que **no** hace falta casar nombres localidad↔barrio (que no calzan 1:1). El
  match por nombre solo se usa a nivel departamento, donde sí coinciden.

## Backend (recetalia-api-rest)

Nuevo endpoint `GET /api/dashboard/pharmacy-locations?startDate&endDate`:
- `PharmacyLocationProjection` / `PharmacyLocationRow`:
  `{ pharmacyId, pharmacyName, franchiseId, franchiseName, localityName,
     regionSlug, regionName, lat, lng, dispensations }`
- Query nativa: `pharmacy LEFT JOIN localities LEFT JOIN regions LEFT JOIN franchise`
  + subquery de conteo de dispensaciones DISPENSED del período. Filtra a las que
  tienen lat/lng. Sin cambios de schema.

## Frontend (gestion-recetadigital-app)

- `BranchMapComponent` (NgModule, en `HomeModule`) — SVG inline.
  - Proyección equirectangular con corrección `cos(latitud media)`, ajustada al
    bounding box del nivel (país / departamento / Montevideo).
  - Nivel país: 19 departamentos sombreados por densidad de sucursales + pins +
    panel lista de departamentos. Nivel departamento: zoom, lista de sucursales,
    botón "← Uruguay"; Montevideo dibuja barrios.
  - Pins solapados (misma localidad) se separan con un pequeño espiral.
  - `@Output() selectBranch` → el dashboard navega a `/dispensations?pharmacyId`.
  - Render solo en browser (`isPlatformBrowser`).
- Assets: `src/assets/geo/uruguay-departamentos.geo.json` (geoBoundaries URY ADM1,
  simplificado Douglas-Peucker → ~41KB) y `montevideo-barrios.geo.json`
  (vierja/geojson_montevideo, simplificado → ~38KB).
- Servicio: `DashboardService.getPharmacyLocations(...)`.

## Fuera de alcance (esta iteración)

- Drill-down de barrios para departamentos que no sean Montevideo (no hay
  polígonos de localidades de los otros 18 deptos; quedan a nivel departamento).
