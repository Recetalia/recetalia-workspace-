# Cadenas — Vista consolidada (Usuario Administrador) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que un usuario `ROLE_PHARMACY_ADMIN` vea en el app de farmacias las dispensaciones consolidadas de todas las sucursales de su cadena, filtrables por sucursal y fecha.

**Architecture:** Backend reutiliza `GET /api/dispensations/search?franchiseId=…` (ya existe) + un endpoint nuevo para listar las sucursales de una cadena, y habilita el scope amplio para `ROLE_PHARMACY_ADMIN`. Frontend: el `authGuard` acepta el rol admin, `AuthService` expone el `franchiseId`, y una pantalla "Cadenas" nueva (espeja `dispensation-list`) con selector de sucursal + fechas.

**Tech Stack:** Java 21 / Spring Boot 3.3 / Gradle · Angular 18.2 / PrimeNG 17.

**Diseño de referencia:** `doc/plans/2026-06-01-cadenas-vista-consolidada-design.md`

---

## Mapa de archivos

### Backend — recetalia-api-rest
- Modify `domain/repository/PharmacyRepository.java` — `findByFranchise_IdAndDeletedAtIsNull`.
- Modify `service/PharmacyService.java` — `getByFranchise(String)`.
- Modify `service/impl/PharmacyServiceImpl.java` — impl de `getByFranchise`.
- Modify `controller/PharmacyController.java` — `GET /api/pharmacies/by-franchise/{franchiseId}`.
- Modify `service/impl/DispensationServiceImpl.java` — abrir scope (pharmacyId blank → null) para `ROLE_PHARMACY_ADMIN`.

### security-api-recetalia
- Modify `src/main/resources/db/migration/V2__data.sql` — seed `ROLE_PHARMACY_ADMIN` (+ INSERT en la DB pre-prod, ver Task 1).

### Frontend — farmacias-recetalia-app
- Modify `src/app/app-routing.module.ts` — `data.roles` incluye `ROLE_PHARMACY_ADMIN`.
- Modify `src/app/services/auth.service.ts` — `getCurrentUser()` agrega `franchiseId`.
- Modify `src/app/services/pharmacy.service.ts` — `getByFranchise(franchiseId)`.
- Modify `src/app/services/dispensation.service.ts` — `search` acepta `franchiseId`.
- Create `src/app/pages/application/home/cadenas/cadenas.component.{ts,html}`.
- Modify `home.module.ts` (declarar), `home-routing.module.ts` (ruta `cadenas`), `components/sidebar/sidebar.component.{ts,html}` (ítem condicional).

### Comandos
- Backend: `cd recetalia-api-rest && ./gradlew build`
- Frontend: `cd farmacias-recetalia-app && npx ng build`

---

## FASE 1 — Backend (recetalia-api-rest) + seed

### Task 1: Seed del rol ROLE_PHARMACY_ADMIN

**Files:** Modify `security-api-recetalia/src/main/resources/db/migration/V2__data.sql`

> Flyway está deshabilitado, así que el seed del fuente es documental; el rol se inserta en la DB real durante el deploy/validación.

- [ ] **Step 1:** En `V2__data.sql`, donde están los `INSERT INTO roles ...`, agregar `ROLE_PHARMACY_ADMIN` siguiendo el formato existente (id consecutivo, p.ej. 10):
```sql
INSERT INTO roles (id, name) VALUES (10, 'ROLE_PHARMACY_ADMIN');
```
(Ajustar el id al siguiente libre según el archivo.)

- [ ] **Step 2: Commit**
```bash
git add src/main/resources/db/migration/V2__data.sql
git commit -m "feat(cadenas): seed rol ROLE_PHARMACY_ADMIN"
```

- [ ] **Step 3 (validación, no en CI):** Insertar el rol en la DB pre-prod (lo hace el controlador del deploy, no el subagente):
```sql
INSERT INTO securitydb.roles (id, name)
SELECT (SELECT COALESCE(MAX(id),0)+1 FROM securitydb.roles), 'ROLE_PHARMACY_ADMIN'
WHERE NOT EXISTS (SELECT 1 FROM securitydb.roles WHERE name='ROLE_PHARMACY_ADMIN');
```

---

### Task 2: Endpoint "sucursales de una cadena" (TDD del repo)

**Files:**
- Modify `domain/repository/PharmacyRepository.java`
- Modify `service/PharmacyService.java`
- Modify `service/impl/PharmacyServiceImpl.java`
- Modify `controller/PharmacyController.java`

`Pharmacy` tiene `@ManyToOne @JoinColumn(name="franchiseId") private Franchise franchise;` y `private Instant deletedAt;`. La query derivada navega `franchise.id`.

- [ ] **Step 1: Repositorio** — agregar a `PharmacyRepository`:
```java
    java.util.List<com.recetalia.api.application.domain.model.entities.Pharmacy>
        findByFranchise_IdAndDeletedAtIsNull(String franchiseId);
```

- [ ] **Step 2: Interface** — agregar a `PharmacyService`:
```java
    java.util.List<com.recetalia.api.application.dto.response.PharmacyResponse> getByFranchise(String franchiseId);
```

- [ ] **Step 3: Impl** — en `PharmacyServiceImpl` (usa `pharmacyMapper` y `pharmacyRepository`, ya inyectados):
```java
  @Override
  public java.util.List<com.recetalia.api.application.dto.response.PharmacyResponse> getByFranchise(String franchiseId) {
    return pharmacyRepository.findByFranchise_IdAndDeletedAtIsNull(franchiseId).stream()
        .map(pharmacyMapper::toDto)
        .collect(java.util.stream.Collectors.toList());
  }
```

- [ ] **Step 4: Controller** — en `PharmacyController` (mismo patrón `ResponseEntity<GenericResponse<...>>`; reusar imports existentes `GenericResponse`, `ResponseStatus`, `List`, `PharmacyResponse`):
```java
  @GetMapping("/by-franchise/{franchiseId}")
  public ResponseEntity<GenericResponse<List<PharmacyResponse>>> getByFranchise(@PathVariable String franchiseId) {
    List<PharmacyResponse> response = pharmacyService.getByFranchise(franchiseId);
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, response));
  }
```
> Verificar el nombre del enum/clase de status usado por los otros métodos del controller (suele ser `ResponseStatus.SUCCESS`).

- [ ] **Step 5: Build** — Run: `./gradlew build` · Expected: BUILD SUCCESSFUL. (Si falla solo por conectividad a la DB en el contextLoads, correr `./gradlew compileJava` y reportar.)

- [ ] **Step 6: Commit**
```bash
git add src/main/java/com/recetalia/api/application/domain/repository/PharmacyRepository.java \
        src/main/java/com/recetalia/api/application/service/PharmacyService.java \
        src/main/java/com/recetalia/api/application/service/impl/PharmacyServiceImpl.java \
        src/main/java/com/recetalia/api/application/controller/PharmacyController.java
git commit -m "feat(cadenas): GET /api/pharmacies/by-franchise/{id}"
```

---

### Task 3: Abrir scope de búsqueda para ROLE_PHARMACY_ADMIN

**Files:** Modify `service/impl/DispensationServiceImpl.java`

Hoy `search(...)` hace (aprox.):
```java
String currentRole = currentUserAuthenticatedService.getCurrentRole();
if ("ROLE_MANAGEMENT".equals(currentRole)) {
  if (pharmacyId == null || pharmacyId.isBlank()) { pharmacyId = null; }
  page = dispensationRepository.searchDispensations(pharmacyId, dispensedById, laboratoryId, patientId, localityId, medicId, franchiseId, medicalProviderId, contains, condvtaId, fromTs, toTs, pageable);
} else {
  page = dispensationRepository.searchDispensations(pharmacyId, dispensedById, laboratoryId, patientId, localityId, medicId, franchiseId, medicalProviderId, contains, condvtaId, fromTs, toTs, pageable);
}
```

- [ ] **Step 1:** Cambiar la condición para incluir `ROLE_PHARMACY_ADMIN` (un admin de cadena con `pharmacyId` en blanco busca por `franchiseId` en todas sus sucursales). Reemplazar el `if ("ROLE_MANAGEMENT".equals(currentRole))` por:
```java
if ("ROLE_MANAGEMENT".equals(currentRole) || "ROLE_PHARMACY_ADMIN".equals(currentRole)) {
  if (pharmacyId == null || pharmacyId.isBlank()) { pharmacyId = null; }
}
page = dispensationRepository.searchDispensations(
    pharmacyId, dispensedById, laboratoryId, patientId, localityId, medicId, franchiseId,
    medicalProviderId, contains, condvtaId, fromTs, toTs, pageable);
```
(Eliminar la rama `else` duplicada — ambas llamaban a lo mismo; queda una sola llamada después del `if`.)

- [ ] **Step 2: Build** — Run: `./gradlew build` · Expected: BUILD SUCCESSFUL.
- [ ] **Step 3: Commit**
```bash
git add src/main/java/com/recetalia/api/application/service/impl/DispensationServiceImpl.java
git commit -m "feat(cadenas): ROLE_PHARMACY_ADMIN busca dispensaciones por cadena (pharmacyId opcional)"
```

---

## FASE 2 — Frontend (farmacias-recetalia-app)

### Task 4: Guard + AuthService + services

**Files:**
- Modify `src/app/app-routing.module.ts`
- Modify `src/app/services/auth.service.ts`
- Modify `src/app/services/pharmacy.service.ts`
- Modify `src/app/services/dispensation.service.ts`

- [ ] **Step 1: app-routing** — permitir el rol admin en la ruta home:
```typescript
    data: { roles: ['ROLE_PHARMACY', 'ROLE_PHARMACY_ADMIN'] }
```

- [ ] **Step 2: AuthService.getCurrentUser** — agregar `franchiseId` al objeto devuelto. Reemplazar el método por:
```typescript
  getCurrentUser(): Observable<{ email: string; role: string; status: string; pharmacyId: string; franchiseId?: string } | null> {
    const token = this.getToken();
    if (token) {
      try {
        const decodedToken: any = jwtDecode(token);
        return this.pharmacyService.getByEmail(decodedToken.mail).pipe(
          map((data: PharmacyResponse) => ({
            email: decodedToken.mail,
            role: decodedToken.role,
            status: data.status,
            pharmacyId: data.id,
            franchiseId: data.franchiseId,
          }))
        );
      } catch (error) {
        console.error('Error decoding token', error);
        return new Observable(observer => observer.next(null));
      }
    }
    return new Observable(observer => observer.next(null));
  }
```

- [ ] **Step 3: PharmacyService.getByFranchise** — agregar:
```typescript
  getByFranchise(franchiseId: string): Observable<PharmacyResponse[]> {
    return this.http.get<ApiResponse<PharmacyResponse[]>>(`${this.baseUrl}/by-franchise/${franchiseId}`).pipe(
      map(response => {
        if (response.status === 'SUCCESS') { return response.answer; }
        throw new Error('API responded with error: ' + response.applicationProvider);
      }),
      catchError(error => {
        console.error('Failed to fetch pharmacies by franchise:', error);
        return throwError(() => new Error('Failed to fetch pharmacies by franchise'));
      })
    );
  }
```

- [ ] **Step 4: DispensationService.search** — agregar `franchiseId` a las options y setearlo en los params. En la firma de `options` agregar `franchiseId?: string;`, y junto a los otros `if (options.xxx)`:
```typescript
    if (options.franchiseId) params = params.set('franchiseId', options.franchiseId);
```
(El resto del método queda igual; `pharmacyId` ya se envía siempre — para "todas las sucursales" se pasará `''`.)

- [ ] **Step 5: Build** — Run: `npx ng build` · Expected: build OK.
- [ ] **Step 6: Commit**
```bash
git add src/app/app-routing.module.ts src/app/services/auth.service.ts src/app/services/pharmacy.service.ts src/app/services/dispensation.service.ts
git commit -m "feat(cadenas): guard admin + franchiseId en AuthService + getByFranchise + search por franchise"
```

---

### Task 5: CadenasComponent (vista consolidada)

**Files:**
- Create `src/app/pages/application/home/cadenas/cadenas.component.ts`
- Create `src/app/pages/application/home/cadenas/cadenas.component.html`

- [ ] **Step 1: Componente** (espeja `dispensation-list`, scope por cadena + selector de sucursal):
```typescript
import { Component, OnInit } from '@angular/core';
import { filter, take } from 'rxjs/operators';
import { AuthService } from '../../../../services/auth.service';
import { PharmacyService } from '../../../../services/pharmacy.service';
import { DispensationService } from '../../../../services/dispensation.service';
import { PharmacyResponse } from '../../../../model/response/pharmacy-response';
import { DispensationSearchRow } from '../../../../model/response/dispensation-search-row';
import { Page } from '../../../../model/page';

@Component({
  selector: 'app-cadenas',
  templateUrl: './cadenas.component.html',
  styleUrls: [],
})
export class CadenasComponent implements OnInit {
  franchiseId = '';
  branches: PharmacyResponse[] = [];
  branchOptions: { label: string; value: string | null }[] = [{ label: 'Todas las sucursales', value: null }];
  selectedBranchId: string | null = null;
  rangeDates: Date[] | undefined;

  rows: DispensationSearchRow[] = [];
  totalRecords = 0;
  loading = true;
  errorMessage: string | null = null;
  pageSize = 25;
  sort = 'dispensationCreatedAt,desc';

  constructor(
    private authService: AuthService,
    private pharmacyService: PharmacyService,
    private dispensationService: DispensationService,
  ) {}

  ngOnInit(): void {
    this.authService.getCurrentUser().pipe(filter(u => !!u), take(1)).subscribe({
      next: (user: any) => {
        if (!user?.franchiseId) {
          this.loading = false;
          this.errorMessage = 'Tu farmacia no pertenece a una cadena.';
          return;
        }
        this.franchiseId = user.franchiseId;
        this.loadBranches();
        this.refreshTable();
      },
      error: () => { this.loading = false; this.errorMessage = 'Error al obtener el usuario.'; },
    });
  }

  private loadBranches(): void {
    this.pharmacyService.getByFranchise(this.franchiseId).subscribe({
      next: list => {
        this.branches = list;
        this.branchOptions = [{ label: 'Todas las sucursales', value: null },
          ...list.map(p => ({ label: p.name, value: p.id }))];
      },
      error: () => { /* deja solo 'Todas' */ },
    });
  }

  onFilterChange(): void { this.refreshTable(); }

  refreshTable(): void {
    this.loadDispensations({ first: 0, rows: this.pageSize, sortField: null, sortOrder: 0 });
  }

  loadDispensations(event: any): void {
    if (!this.franchiseId) { this.loading = false; return; }
    this.loading = true;
    if (event.sortField) {
      this.sort = `${event.sortField},${event.sortOrder === 1 ? 'asc' : 'desc'}`;
    }
    const startDate = this.rangeDates?.length === 2 ? this.rangeDates[0] : undefined;
    const endDate = this.rangeDates?.length === 2 ? this.rangeDates[1] : undefined;

    const opts = {
      franchiseId: this.franchiseId,
      startDate, endDate,
      page: 0,
      size: event.rows ?? this.pageSize,
      sort: this.sort,
    };
    // pharmacyId: '' = todas las sucursales de la cadena; o la sucursal elegida
    this.dispensationService.search(this.selectedBranchId ?? '', opts).subscribe({
      next: (page: Page<DispensationSearchRow>) => {
        this.rows = page.content as DispensationSearchRow[];
        this.totalRecords = page.totalElements;
        this.loading = false;
      },
      error: () => { this.rows = []; this.totalRecords = 0; this.loading = false; },
    });
  }
}
```
> Verificar la ruta del modelo `Page` (en farmacias-app suele ser `src/app/model/page.ts`); ajustar el import si difiere. Si `DispensationService.search` tipa `options` estrictamente, `franchiseId` ya fue agregado en Task 4.

- [ ] **Step 2: Template** (p-table lazy + selector de sucursal + rango de fechas):
```html
<div class="content-table mt-3">
  <h2>Cadenas — Dispensaciones consolidadas</h2>

  <div *ngIf="errorMessage" class="alert alert-warning">{{ errorMessage }}</div>

  <div class="d-flex gap-3 mb-3 flex-wrap" *ngIf="!errorMessage">
    <span>
      <label class="me-2">Sucursal</label>
      <p-dropdown [options]="branchOptions" [(ngModel)]="selectedBranchId" optionLabel="label" optionValue="value"
        (onChange)="onFilterChange()" [style]="{ minWidth: '220px' }"></p-dropdown>
    </span>
    <span>
      <label class="me-2">Fechas</label>
      <p-calendar [(ngModel)]="rangeDates" selectionMode="range" dateFormat="dd/mm/yy"
        (onSelect)="onFilterChange()" placeholder="Rango"></p-calendar>
    </span>
  </div>

  <p-table [value]="rows" [loading]="loading" [lazy]="true" (onLazyLoad)="loadDispensations($event)"
           [paginator]="true" [rows]="pageSize" [totalRecords]="totalRecords" *ngIf="!errorMessage">
    <ng-template pTemplate="header">
      <tr>
        <th>Fecha</th><th>Sucursal</th><th>Medicamento</th><th>Paciente</th><th>Médico</th><th>Cant.</th>
      </tr>
    </ng-template>
    <ng-template pTemplate="body" let-r>
      <tr>
        <td>{{ r.dispensationCreatedAt | date:'short' }}</td>
        <td>{{ r.pharmacyName }}</td>
        <td>{{ r.dispensationProductName || r.dispensationProductId }}</td>
        <td>{{ r.patientName }} {{ r.patientLastName }}</td>
        <td>{{ r.medicName }} {{ r.medicLastname }}</td>
        <td>{{ r.dispensationQty }}</td>
      </tr>
    </ng-template>
    <ng-template pTemplate="emptymessage"><tr><td colspan="6">Sin dispensaciones para el filtro.</td></tr></ng-template>
  </p-table>
</div>
```
> `DispensationSearchRow` incluye `pharmacyName`? El backend lo proyecta (`ph.name AS pharmacyName`). Si el modelo TS no lo tiene, agregar `pharmacyName?: string;` a `dispensation-search-row.ts`. Verificar en implementación.

- [ ] **Step 3: Commit** (compila al declararlo en Task 6)
```bash
git add src/app/pages/application/home/cadenas
git commit -m "feat(cadenas): CadenasComponent (dispensaciones consolidadas + selector de sucursal)"
```

---

### Task 6: Wiring — módulo, ruta, menú condicional

**Files:**
- Modify `src/app/pages/application/home/home.module.ts`
- Modify `src/app/pages/application/home/home-routing.module.ts`
- Modify `src/app/pages/application/home/components/sidebar/sidebar.component.ts`
- Modify `src/app/pages/application/home/components/sidebar/sidebar.component.html`

- [ ] **Step 1: home.module.ts** — importar y declarar `CadenasComponent` (los módulos `TableModule`, `PaginatorModule`, `CalendarModule`, `DropdownModule`, `FormsModule` ya están importados):
```typescript
import { CadenasComponent } from './cadenas/cadenas.component';
```
Agregar `CadenasComponent` al array `declarations`.

- [ ] **Step 2: home-routing.module.ts** — importar y agregar la ruta hija:
```typescript
import { CadenasComponent } from './cadenas/cadenas.component';
```
Dentro de `children`:
```typescript
      { path: 'cadenas', component: CadenasComponent },
```

- [ ] **Step 3: sidebar.component.ts** — exponer el rol del usuario. Agregar la propiedad y cargarla en `ngOnInit` (después del `getByEmail`):
```typescript
  userRole: string | null = null;
```
```typescript
    this.authService.getCurrentUser().subscribe({
      next: (user: any) => { if (user) this.userRole = user.role; },
      error: () => { /* ignore */ },
    });
```
(`AuthService` ya está inyectado en el sidebar.)

- [ ] **Step 4: sidebar.component.html** — agregar el ítem condicional (dentro del `<ul class="nav flex-column">`, p.ej. después de "Dispensaciones"):
```html
        <li class="nav-item" *ngIf="userRole === 'ROLE_PHARMACY_ADMIN'">
            <a class="nav-link" routerLink="cadenas" routerLinkActive="active" (click)="closeSidebar()">
                <i class="fas fa-link"></i> <span>Cadenas</span>
            </a>
        </li>
```

- [ ] **Step 5: Build** — Run: `npx ng build` · Expected: build OK.
- [ ] **Step 6: Verificación manual** — `npm start`; login con un usuario `ROLE_PHARMACY_ADMIN` (rol asignado en la DB) cuya farmacia tenga cadena → aparece "Cadenas" → la tabla muestra dispensaciones de varias sucursales; el selector de sucursal y el rango de fechas filtran. Un `ROLE_PHARMACY` normal NO ve "Cadenas".
- [ ] **Step 7: Commit**
```bash
git add src/app/pages/application/home/home.module.ts \
        src/app/pages/application/home/home-routing.module.ts \
        src/app/pages/application/home/components/sidebar/sidebar.component.ts \
        src/app/pages/application/home/components/sidebar/sidebar.component.html
git commit -m "feat(cadenas): ruta + menú condicional por rol + wiring del módulo"
```

---

## Smoke test end-to-end (post-deploy)

- [ ] Asignar `ROLE_PHARMACY_ADMIN` a un usuario de farmacia de prueba cuya `Pharmacy` tenga `franchiseId` (p.ej. una sucursal de Pigalle). Confirmar que el rol exista en `securitydb.roles`.
- [ ] `GET /api/pharmacies/by-franchise/{franchiseId}` con un JWT válido → lista de sucursales de la cadena.
- [ ] `GET /api/dispensations/search?pharmacyId=&franchiseId={id}&startDate&endDate` con el JWT admin → dispensaciones de varias sucursales (no vacío).
- [ ] Login en farmacias con el admin → "Cadenas" visible → consolidado correcto; filtrar por una sucursal y por fechas funciona.

## Criterios de éxito (del spec)

- [ ] Existe `ROLE_PHARMACY_ADMIN`; un admin de prueba se loguea y ve "Cadenas" (un `ROLE_PHARMACY` no).
- [ ] La pantalla muestra el consolidado de la cadena con selector de sucursal (incl. "Todas") + fechas, funcionando.
- [ ] `GET /api/pharmacies/by-franchise/{id}` devuelve las sucursales (sin eliminadas).
- [ ] Backend `./gradlew build` y frontend `ng build` en verde.

## Self-review (hecho)

- **Cobertura del spec:** rol seed (Task 1), endpoint sucursales (Task 2), scope admin en search (Task 3), guard+franchiseId+services (Task 4), pantalla consolidada con selector+fechas (Task 5), menú condicional + ruta (Task 6). ✅
- **Sin placeholders:** código completo por step; las verificaciones inline (nombre de `ResponseStatus`, ruta del modelo `Page`, presencia de `pharmacyName` en el row TS) son chequeos rápidos contra archivos existentes. ✅
- **Consistencia:** `getByFranchise` igual en repo (`findByFranchise_IdAndDeletedAtIsNull`) → service → controller → frontend (`/by-franchise/{id}`); `franchiseId` agregado en `getCurrentUser` (Task 4) y consumido en CadenasComponent (Task 5); `search` con `franchiseId` agregado en Task 4 y usado en Task 5. ✅
- **Fuera de alcance respetado:** sin ABM del admin (seed manual), sin dashboard (A2 aparte), sin tabla/columna nueva. ✅
