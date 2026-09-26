# Spec: Principio activo genérico en la receta — 2026-06-17

## Contexto y hallazgo

El medic app ya muestra el principio activo (sustancia, ej. "ketoprofeno") al prescribir,
pero NO aparece en la receta vista desde farmacias (Buscar Prescripción, Dispensaciones) ni
gestión. Hallazgos:

- La sustancia (`SUSTANCIA_DSC` en DNMA) **no se guarda** en la prescripción ni viaja en
  `PrescriptionResponse` / `DispensationSearchRow`.
- **Se puede derivar de DNMA por `productId`** sin tocar el alta de recetas: el join ya
  existe en `searchByProdMsp` (`DnmaDatabaseServiceImpl`):
  `amp a → vmp v (a.VMP_Id) → vmp_sustancia vs (vs.VMP_Id) → sustancia s (s.SUSTANCIA_ID = vs.SUSTANCIA_Id)`,
  campo `s.SUSTANCIA_DSC`.

## Decisión (tomada)

- **Derivar de DNMA on-read** (no migración de base, no tocar el alta de recetas; aplica a
  recetas viejas y nuevas). Mismo patrón que la resolución de nombres de AMP/AMPP.
- Mostrarlo en: **Farmacias > Buscar Prescripción**, **Farmacias > Dispensaciones (modal)**,
  **Gestión > Dispensaciones (modal)**, y los **exports PDF/Excel** de dispensaciones (farmacias
  y gestión).

## Backend (recetalia-api-rest) — branch `fix/ajustes-farmacias-2026-06-2`

Resolución de sustancia en lote vía DNMA (datasource pooled existente), con `GROUP_CONCAT`
para medicamentos con más de una sustancia (combos → "amoxicilina + ácido clavulánico"):

- Nuevo helper en `DnmaDatabaseService(Impl)`: `fetchSubstancesByAmpIds(List<String>) → Map<ampId, SUSTANCIA_DSC>`
  (`amp → vmp → vmp_sustancia → sustancia`, `GROUP BY AMP_Id`, `GROUP_CONCAT(DISTINCT s.SUSTANCIA_DSC SEPARATOR ' + ')`).
- Nuevo helper: `fetchSubstancesByAmppIds(List<String>) → Map<amppId, SUSTANCIA_DSC>`
  (`ampp → amp (ampp.AMP_Id) → vmp → vmp_sustancia → sustancia`, GROUP BY AMPP_Id, mismo GROUP_CONCAT).
- (VMP) `fetchSubstancesByVmpIds(List<String>) → Map<vmpId, SUSTANCIA_DSC>` para prescripciones
  con `productType = VMP` (`vmp_sustancia` por `VMP_Id`). Se incluye: en los genéricos (VMP) el
  principio activo es justamente lo más relevante.

Exposición:
- `PrescriptionResponse`: nuevo campo `String substanceName`. Poblar en
  `enrichPrescriptionsWithAmpDetails` (productos AMP → `fetchSubstancesByAmpIds`; VMP →
  `fetchSubstancesByVmpIds`). → cubre **Buscar Prescripción**.
- `DispensationSearchRow` (interface projection): nuevo getter `getPrescriptionSubstanceName()`
  poblado en el enriquecimiento de `DispensationServiceImpl.search()` resolviendo la sustancia
  desde el `dispensationProductId` (AMPP) con `fetchSubstancesByAmppIds` (en lote). Se devuelve
  vía `EnrichedDispensationRow` (agregar el campo al wrapper). → cubre **Dispensaciones** de
  farmacias y gestión (mismo endpoint).

Notas:
- Helpers nuevos y dedicados (no se modifica `fetchAmpDetails`/`fetchAmppDetails` para no
  alterar su semántica ni afectar otros consumidores).
- `null`/vacío si DNMA no resuelve (degradación: simplemente no se muestra).

## Frontend farmacias (branch `fix/ajustes-farmacias-2026-06-2`)

- Modelo `prescription-response.ts`: `substanceName?: string | null`.
- Modelo `dispensation-search-row.ts`: `prescriptionSubstanceName?: string | null`.
- **Buscar Prescripción** (`prescription-search.component.html`): mostrar la sustancia bajo el
  título/nombre del medicamento (estilo discreto, como el medic app: texto gris/itálico).
- **Dispensaciones modal** (`dispensations-info.component.html`): mostrar el principio activo
  en la sección MEDICAMENTO o PRESCRIPCIÓN (debajo del nombre).
- **Exports** (`dispensation-file.service.ts`): incluir el principio activo en Excel (columna)
  y PDF (línea), usando `prescriptionSubstanceName`.

## Frontend gestión (branch `fix/ajustes-gestion-2026-06`)

- Modelo `dispensation-search-row.ts`: `prescriptionSubstanceName?: string | null`.
- **Dispensaciones modal** (`dispensations-info.component.html`): mostrar el principio activo.
- **Exports** (`dispensation-file.service.ts`): incluir en Excel y PDF.

## Fuera de alcance

- Guardar la sustancia en la base / tocar el alta de recetas (se deriva on-read).
- Medic app (ya lo muestra).
- Gestión > Buscar Prescripción (gestión no dispensa; no aplica).

## Testing

- Backend: build OK; verificación por API en PRE — `search-available-Prescriptions-by-code`
  devuelve `substanceName`, y `dispensations/search` devuelve `prescriptionSubstanceName`.
  Caso de control: orudis (AMP) → "ketoprofeno".
- Frontend: build de farmacias y gestión OK; verificación visual en PRE (las 3 pantallas +
  exports).
- Datos de prueba: orudis `20200B` / dispensación `20200B-A` (ketoprofeno).

## Branches

- recetalia-api-rest + farmacias-recetalia-app: `fix/ajustes-farmacias-2026-06-2` (existente).
- gestion-recetadigital-app: `fix/ajustes-gestion-2026-06` (existente).
- NO mergear hasta OK de Pablo. Se despliega junto con el resto de los ajustes pendientes.
