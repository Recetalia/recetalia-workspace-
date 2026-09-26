# QF — Control de Recetas Verdes — Plan 3: Módulo Farmacias (Libro Negro)

> Ejecutar subagent-driven. Frontend en `farmacias-recetalia-app` (Angular 18.2, NgModule).

**Goal:** En la app de Farmacias, una pantalla "Libro Negro" (Medicamentos controlados) que lista las **recetas verdes dispensadas** de la farmacia, muestra el **estado de control del Químico Farmacéutico (D.T.)** por receta, y permite **exportar el Excel** con el formato "Informe de Medicamentos controlados por Farmacia" (endpoint ya existente en el backend, desplegado).

**Backend ya disponible (Plan 1, desplegado en PRE):**
- `GET /api/dispensations/search?pharmacyId=&condvtaId=11&startDate=&endDate=&page=&size=&sort=` → `Page<DispensationSearchRow>` que **ya incluye** `dtControlAt`, `dtControlName`, `dtControlCjp`, `medicalProviderName`, y el nombre del medicamento resuelto.
- `GET /api/dispensations/controlled-medications/excel?pharmacyId=&startDate=&endDate=` → devuelve el `.xlsx` (formato Libro Negro). Requiere token (cualquiera autenticado).

**Patrón existente a reusar:**
- `DispensationService.search(pharmacyId, { condvtaId, startDate, endDate, page, size, sort, franchiseId, ... })` (`src/app/services/dispensation.service.ts:120`).
- Resolución de usuario/rol y selector de sucursal (admin) en `dispensation-list.component.ts` (ROLE_PHARMACY = su farmacia; ROLE_PHARMACY_ADMIN = franquicia + dropdown de sucursales via `pharmacyService.getByFranchise`).
- Home routing hijos en `home-routing.module.ts`; sidebar en `components/sidebar/sidebar.component.html`.

---

## Task 1: Modelo — campos de control D.T.

**File:** `src/app/model/response/dispensation-search-row.ts`

Agregar al interface `DispensationSearchRow`:
```typescript
  // Control D.T. (Químico Farmacéutico)
  dtControlAt?: string | null;
  dtControlName?: string | null;
  dtControlCjp?: string | null;
  medicalProviderName?: string | null;
```
Commit: `feat(libro-negro): dtControl fields in DispensationSearchRow`.

## Task 2: Servicio — export Excel del Libro Negro

**File:** `src/app/services/dispensation-file.service.ts` (o `dispensation.service.ts`)

Agregar un método que descarga el `.xlsx` como blob y dispara el download (SSR-safe con `isPlatformBrowser`). Inyectar `HttpClient` si el archivo elegido no lo tiene.
```typescript
exportControlledMedications(pharmacyId: string, startDate?: string, endDate?: string): void {
  if (!isPlatformBrowser(this.platformId)) return;
  let params = new HttpParams().set('pharmacyId', pharmacyId);
  if (startDate) params = params.set('startDate', startDate);
  if (endDate) params = params.set('endDate', endDate);
  this.http.get(`${environment.apiUrl}/dispensations/controlled-medications/excel`,
      { params, responseType: 'blob', observe: 'response' })
    .subscribe((res) => {
      const blob = res.body as Blob;
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'medicamentos-controlados.xlsx';
      a.click();
      URL.revokeObjectURL(url);
    });
}
```
Verificar el nombre real del `HttpClient`/`environment` imports en el archivo elegido; si `dispensation-file.service.ts` no inyecta `HttpClient`, agregarlo al constructor. Commit: `feat(libro-negro): export controlled-medications Excel (download)`.

## Task 3: Componente "Libro Negro"

**Files (create):**
- `src/app/pages/application/home/libro-negro/libro-negro.component.ts`
- `src/app/pages/application/home/libro-negro/libro-negro.component.html`

**READ FIRST** `dispensation-list.component.ts` y reusar SU lógica de resolución de rol/sucursal (getCurrentUser → `pharmacyId` para ROLE_PHARMACY; para ROLE_PHARMACY_ADMIN carga `pharmacyService.getByFranchise(franchiseId)` y expone un dropdown de sucursales — obligatorio elegir una para poder listar/exportar, porque el Libro Negro y el Excel son por farmacia).

Comportamiento:
- Filtros: rango de fechas (p-calendar range) + (si admin) dropdown de sucursal.
- Al cargar / filtrar: `DispensationService.search(effectivePharmacyId, { condvtaId: 'GREEN', startDate, endDate, page, size, sort: 'dispensationCreatedAt,desc' })` (lazy p-table).
- Tabla (columnas): Código (`prescriptionCode`), Paciente (`patientName patientLastName`), Médico (`medicName medicLastname` + CJP), Medicamento (`dispensationProductName`), Fecha disp. (`dispensationUpdatedAt || dispensationCreatedAt`), **Control D.T.**: si `dtControlAt` → "Controlada {{dtControlAt|date}} — {{dtControlName}}"; si no → chip "Pendiente".
- Botón **"Exportar xls"** → `dispensationFileService.exportControlledMedications(effectivePharmacyId, startDate, endDate)`. Deshabilitado si no hay `effectivePharmacyId` (admin sin sucursal elegida).
- Fila con clase `back_green` (estilo verde ya existente en styles.scss).

Modelar el `.ts` sobre `dispensation-list.component.ts` (mismos imports de PrimeNG Table/Calendar/Dropdown, `AuthService`, `PharmacyService`, `DispensationService`). El `condvtaId` para verde: usar el string que el resto del código usa para GREEN (verificar en `dispensation-list` — es `'GREEN'`, que el backend normaliza a `'11'`).

Commit: `feat(libro-negro): controlled-medications screen (green dispensed + D.T. status + export)`.

## Task 4: Wiring — módulo, ruta, menú

**Files:**
- `src/app/pages/application/home/home.module.ts` — declarar `LibroNegroComponent`; asegurar imports PrimeNG (`TableModule`, `CalendarModule`, `DropdownModule`, `ButtonModule`, `FormsModule`) ya presentes por dispensation-list.
- `src/app/pages/application/home/home-routing.module.ts` — agregar ruta hija:
  ```typescript
  { path: 'libro-negro', component: LibroNegroComponent },
  ```
- `src/app/pages/application/home/components/sidebar/sidebar.component.html` — agregar link (después de "Dispensaciones"):
  ```html
  <li class="nav-item">
    <a class="nav-link" routerLink="libro-negro" routerLinkActive="active" (click)="closeSidebar()">
      <i class="fas fa-book"></i> <span>Libro Negro</span>
    </a>
  </li>
  ```
  (Respetar la estructura `<li>` real del sidebar de farmacias.)

Commit: `feat(libro-negro): route + sidebar link + module wiring`.

## Verificación
- `npm run build -- --configuration=preprod` → "Application bundle generation complete".
- Runtime (tras deploy a PRE): login farmacia con verdes dispensadas (p.ej. la farmacia "Test", `test@test.com`/`Recetalia2026!` o la que tenga verdes) → menú "Libro Negro" → lista las verdes con estado de control (la que firmó el QF aparece "Controlada"); botón Exportar xls baja el archivo con el formato correcto.

## Notas
- El Excel lo genera el backend (no el front) — el front solo dispara la descarga.
- Endurecer por rol el endpoint del Excel queda como mejora futura (hoy es `authenticated()`).
