# QF — Control de Recetas Verdes — Plan 2: App QF (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Crear la app frontend `qf-recetalia-app` (Angular 18.2, clonada de `farmacias-recetalia-app`) para el Químico Farmacéutico: login por CJP, cambio de contraseña forzado en el primer ingreso, listado de sus farmacias, y por farmacia el listado de recetas verdes dispensadas con un check de control ("firma").

**Architecture:** Se clona la app de farmacias (mismo scaffolding SSR/NgModule, PrimeNG, AES login) y se reduce a las pantallas del QF. El login toma un **CJP** y arma el email sintético `{cjp}@qf.recetalia.com` que ya usa el backend (Plan 1). El JWT trae `role='ROLE_PHARMACEUTICAL_DIRECTOR'` (prefijo simple en el front) y `mustChangePassword`. La app consume los endpoints `/api/pharmaceutical-director/*` y `/api/auth/renew-password`. Se sirve como SPA estática por nginx (igual que farmacias).

**Tech Stack:** Angular 18.2, PrimeNG 17, Bootstrap 5, crypto-js (AES-ECB/PKCS7), jwt-decode, TypeScript strict. Build: `npm run build -- --configuration=preprod`.

**Design de referencia:** `doc/plans/2026-07-22-qf-control-recetas-verdes-design.md`. **Backend (Plan 1):** endpoints `/api/pharmaceutical-director/{pharmacies, green-dispensations, dispensations/{id}/control}`, `/api/auth/{login, renew-password}`, `TokenResponse.mustChangePassword`.

**Prerequisitos:** Plan 1 mergeado o desplegado en el ambiente donde se pruebe (los endpoints deben existir). Para pruebas locales/dev, apuntar el environment al host que tenga el backend del Plan 1.

**Repo/rama:** `qf-recetalia-app` es un **repo nuevo** (su propio `.git`), rama inicial `feat/qf-app` (o `main` con commits; el resto del workspace usa `2.x.y` → acá al ser repo nuevo, `main`). **Sin push a remoto hasta OK de Pablo** (aún no hay remoto asignado).

**Convención verificada del scaffold farmacias:**
- `package.json`: name `farmacias-recetalia-app`, script `serve:ssr:farmacias-recetalia-app`.
- `angular.json`: project `farmacias-recetalia-app`, `outputPath: dist/farmacias-recetalia-app`; configs `production`(default), `preprod`(fileReplacements → `environment.preprod.ts`), `dev`, `development`.
- Login AES: key = `('ahjsdfhjbqer56243' + dynamicInfo)` padded a 32 bytes, `AES/ECB/PKCS7`; `dynamicInfo` = primeros 10 chars de un UUID v4. `AuthService.login(email, encPassword, info)` → `POST {authUrl}/login`.
- `authGuard` decodifica el JWT (`mail`, `role`) y valida `route.data['roles']`.
- Modelos: `ApiResponse<T>` (`{status, answer}`), `Page<T>` (`{content,totalElements,totalPages,size,number,...}`), `DispensationSearchRow`.
- Dockerfile: build Node 20 → nginx alpine estático (SPA fallback a `index.html`), puerto 80, build-arg `CONFIGURATION`.

---

## File Structure (en `qf-recetalia-app/`)

- Clonado del scaffold farmacias (renombrado): `package.json`, `angular.json`, `Dockerfile`, `default.conf`, `server.ts`, `src/main*.ts`, `src/app/app*.module.ts`, `src/styles.scss`, assets.
- `src/environments/environment.ts` + `environment.preprod.ts` — API `apipre.recetalia.com` + `qfEmailDomain`.
- `src/app/services/auth.service.ts` — reusado, con `getCurrentUser` simplificado (sin resolver farmacia por email).
- `src/app/services/pharmaceutical-director.service.ts` — NUEVO: farmacias del QF, verdes dispensadas, control.
- `src/app/interceptors/auth.guard.ts` — adaptado: valida rol QF sin resolver farmacia.
- `src/app/interceptors/auth.interceptor.ts` — reusado tal cual.
- `src/app/pages/application/login/login.component.{ts,html}` — input CJP → email sintético; ruteo a change-password si `mustChangePassword`.
- `src/app/pages/application/change-password/` — NUEVO: cambio de contraseña obligatorio.
- `src/app/pages/application/home/` — shell reducido: sidebar QF + 2 rutas.
- `src/app/pages/application/home/pharmacies/pharmacy-list/` — NUEVO: farmacias del QF.
- `src/app/pages/application/home/green-dispensations/green-dispensations-list/` — NUEVO: verdes dispensadas + control.
- `src/app/model/response/dispensation-search-row.ts` — + `dtControlAt/dtControlName/dtControlCjp/medicalProviderName`.
- Rutas: `app-routing.module.ts`, `home-routing.module.ts` — reducidas a QF.

---

## Task 1: Clonar el scaffold y renombrar a `qf-recetalia-app`

**Files:** todo el árbol nuevo `qf-recetalia-app/`.

- [ ] **Step 1: Copiar el árbol (sin artefactos)**

Run (desde el workspace root `/Users/pablo/iwtg/recetalia-workspace`):
```bash
rsync -a --exclude node_modules --exclude dist --exclude .git --exclude .angular \
  farmacias-recetalia-app/ qf-recetalia-app/
cd qf-recetalia-app && git init -q && git add -A && git commit -q -m "chore: scaffold qf-recetalia-app cloned from farmacias-recetalia-app"
```

- [ ] **Step 2: Renombrar el proyecto en `package.json`**

En `qf-recetalia-app/package.json`: `"name": "farmacias-recetalia-app"` → `"qf-recetalia-app"`; script `"serve:ssr:farmacias-recetalia-app"` → `"serve:ssr:qf-recetalia-app"` y su valor `node dist/farmacias-recetalia-app/server/server.mjs` → `node dist/qf-recetalia-app/server/server.mjs`.

- [ ] **Step 3: Renombrar el proyecto en `angular.json`**

Reemplazar la clave de proyecto `"farmacias-recetalia-app"` por `"qf-recetalia-app"` y todos los `outputPath`/rutas `dist/farmacias-recetalia-app` → `dist/qf-recetalia-app`. Verificar que no queden referencias:
Run: `grep -rn "farmacias-recetalia-app" angular.json package.json`
Expected: sin resultados tras el renombrado.

- [ ] **Step 4: Instalar y buildear el clon tal cual (base sana)**

Run:
```bash
cd /Users/pablo/iwtg/recetalia-workspace/qf-recetalia-app
npm install
npm run build -- --configuration=preprod
```
Expected: `Application bundle generation complete` (build OK). Si falla por memoria/prerender, reintentar; el objetivo es confirmar que el clon compila antes de tocarlo.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore(qf-app): rename project to qf-recetalia-app; base build green"
```

---

## Task 2: Environments (API pre + dominio del email QF)

**Files:**
- Modify: `qf-recetalia-app/src/environments/environment.ts`
- Modify: `qf-recetalia-app/src/environments/environment.preprod.ts`

- [ ] **Step 1: Agregar `qfEmailDomain` a los environments**

En `environment.preprod.ts` (mantener las URLs `apipre.recetalia.com` heredadas del clon) agregar el campo:
```typescript
export const environment = {
  production: false,
  apiUrl: 'https://apipre.recetalia.com/recetalia-api-rest/api',
  securityApiRecetaliaUrl: 'https://apipre.recetalia.com/security-api-recetalia/api/auth',
  qfEmailDomain: 'qf.recetalia.com',
};
```
En `environment.ts` (prod) agregar `qfEmailDomain: 'qf.recetalia.com'` respetando sus URLs `api.recetalia.com`. Mantener exactamente las demás claves que ya tenga el archivo (no borrar campos existentes).

- [ ] **Step 2: Verificar tipos (strict)**

Run: `cd qf-recetalia-app && npx tsc --noEmit -p tsconfig.app.json`
Expected: sin errores por `qfEmailDomain` faltante donde se use (se usará en Task 4).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(qf-app): environments with qfEmailDomain"
```

---

## Task 3: `AuthResponse` + `AuthService` (flag mustChangePassword, getCurrentUser simplificado)

**Files:**
- Modify: `qf-recetalia-app/src/app/model/response/auth-response.ts` (o el nombre real; el clon tenía `Auth-response.ts`)
- Modify: `qf-recetalia-app/src/app/services/auth.service.ts`

- [ ] **Step 1: Agregar `mustChangePassword` al modelo de respuesta**

En el DTO `AuthResponse`, dentro de `answer`, agregar el campo:
```typescript
answer: {
  token: string;
  refreshToken?: string;
  username: string;
  role: string;
  mustChangePassword?: boolean;
};
```
(Ajustar a la forma real del archivo; si `answer` está tipado aparte, agregar ahí.)

- [ ] **Step 2: Exponer `mustChangePassword` desde `AuthService.login`**

`AuthService.login(email, password, info)` ya hace `POST {securityApiRecetaliaUrl}/login` y guarda token+role. Asegurar que el `Observable` resuelto exponga el `answer` completo (incluido `mustChangePassword`) para que el login component pueda rutear. Si hoy `login` mapea sólo a `{token, role}`, cambiarlo para devolver el `answer` completo (o agregar el flag). No romper `setToken/setRole`.

- [ ] **Step 3: Simplificar `getCurrentUser()` para el QF**

El `getCurrentUser()` heredado resuelve una farmacia por email (no aplica al QF, cuyo email es sintético). Reemplazar su cuerpo por una resolución basada sólo en el JWT:
```typescript
getCurrentUser(): { email: string; role: string; cjp: string } | null {
  const token = this.getToken();
  if (!token) return null;
  const decoded: any = jwtDecode(token);
  const mail: string = decoded?.mail ?? '';
  const cjp = mail.includes('@') ? mail.substring(0, mail.indexOf('@')) : mail;
  return { email: mail, role: decoded?.role ?? '', cjp };
}
```
(Quitar las dependencias a `PharmacyService`/`FranchiseService` en este service si quedaban sólo para esto; si se usan en otros lados que se borran en Task 8, se limpian ahí.)

- [ ] **Step 4: Verificar compilación**

Run: `cd qf-recetalia-app && npx tsc --noEmit -p tsconfig.app.json`
Expected: sin errores (o sólo los de componentes que se tocan en tareas siguientes; si aparecen por imports rotos de módulos que se eliminarán, anotarlos y resolver en Task 8).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(qf-app): auth carries mustChangePassword; getCurrentUser from JWT (cjp)"
```

---

## Task 4: Login por CJP (+ ruteo a cambio de contraseña forzado)

**Files:**
- Modify: `qf-recetalia-app/src/app/pages/application/login/login.component.ts`
- Modify: `qf-recetalia-app/src/app/pages/application/login/login.component.html`

- [ ] **Step 1: Adaptar el formulario a CJP**

En `login.component.ts`: renombrar el control `username`/`email` a `cjp` (o mantener el control y reinterpretarlo). En `onSubmit()`, construir el email sintético antes de encriptar:
```typescript
const cjp = (this.form.value.cjp ?? '').toString().trim();
const email = `${cjp}@${environment.qfEmailDomain}`;
const dynamicInfo = this.generateDynamicInfo();
const encrypted = this.encryptPassword(this.form.value.password, dynamicInfo);
this.authService.login(email, encrypted, dynamicInfo).subscribe({
  next: (answer) => {
    if (answer?.mustChangePassword) {
      // guardar el email sintético para el cambio de contraseña
      localStorage.setItem('qf_email', email);
      this.router.navigate(['/change-password']);
    } else {
      this.router.navigate(['/']);
    }
  },
  error: () => { this.errorMessage = 'CJP o contraseña incorrectos'; }
});
```
Conservar intactos `generateDynamicInfo()` y `encryptPassword()` (AES-ECB/PKCS7, key `ahjsdfhjbqer56243`+info padded 32). Importar `environment` desde `src/environments/environment`.

- [ ] **Step 2: Adaptar el HTML**

En `login.component.html`: cambiar el input de email por uno de **CJP** (`formControlName="cjp"`, placeholder "Ingrese su CJP", `inputmode="text"`). Quitar los links a `/register` y `/forgot-password` (el QF no se auto-registra; su alta es por Gestión). Mantener el input de contraseña y el botón "Ingresar".

- [ ] **Step 3: Verificar build**

Run: `cd qf-recetalia-app && npm run build -- --configuration=preprod`
Expected: build OK (puede fallar si Task 8 aún no limpió rutas rotas; si el error es sólo del login, arreglarlo acá).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(qf-app): login by CJP → synthetic email; route to change-password when forced"
```

---

## Task 5: Pantalla de cambio de contraseña obligatorio

**Files:**
- Create: `qf-recetalia-app/src/app/pages/application/change-password/change-password.component.ts`
- Create: `qf-recetalia-app/src/app/pages/application/change-password/change-password.component.html`
- Create: `qf-recetalia-app/src/app/pages/application/change-password/change-password.module.ts`
- Modify: `qf-recetalia-app/src/app/services/auth.service.ts` — método `renewPassword`.

- [ ] **Step 1: Método `renewPassword` en `AuthService`**

```typescript
renewPassword(email: string, encryptedPassword: string, info: string): Observable<any> {
  return this.http.post(`${environment.securityApiRecetaliaUrl}/renew-password`,
    { email, password: encryptedPassword, info });
}
```
(El backend `/renew-password` descifra el password con AES+info, igual que `/login`.)

- [ ] **Step 2: Componente de cambio**

`change-password.component.ts`: form con `password` + `confirm` (validar iguales, mínimo 6). Al submit: leer `localStorage.getItem('qf_email')`, generar `dynamicInfo`, encriptar con el mismo `encryptPassword` (extraer el helper a un util compartido `src/app/shared/utils/crypto.util.ts` y usarlo tanto en login como acá para no duplicar), llamar `authService.renewPassword(email, enc, info)`. En éxito: `authService.clearToken()`, limpiar `qf_email`, `router.navigate(['/login'])` con un mensaje "Contraseña actualizada, ingresá de nuevo".
```typescript
onSubmit() {
  if (this.form.invalid || this.form.value.password !== this.form.value.confirm) {
    this.error = 'Las contraseñas no coinciden'; return;
  }
  const email = localStorage.getItem('qf_email') ?? '';
  const info = generateDynamicInfo();
  const enc = encryptPassword(this.form.value.password, info);
  this.authService.renewPassword(email, enc, info).subscribe({
    next: () => { this.authService.clearToken(); localStorage.removeItem('qf_email');
                  this.router.navigate(['/login'], { queryParams: { changed: 1 } }); },
    error: () => { this.error = 'No se pudo cambiar la contraseña'; }
  });
}
```

- [ ] **Step 3: Extraer el helper AES a `shared/utils/crypto.util.ts`**

```typescript
import * as CryptoJS from 'crypto-js';
export function generateDynamicInfo(): string {
  return (crypto.randomUUID?.() ?? `${Math.random()}`).replace(/-/g, '').substring(0, 10);
}
export function encryptPassword(password: string, dynamicInfo: string): string {
  const finalKey = ('ahjsdfhjbqer56243' + dynamicInfo).padEnd(32, '0').substring(0, 32);
  return CryptoJS.AES.encrypt(password, CryptoJS.enc.Utf8.parse(finalKey),
    { mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.Pkcs7 }).toString();
}
```
> Verificar contra el `login.component.ts` original el padding exacto (padEnd con `'0'` o espacios) y replicarlo idéntico — el backend descifra con la misma convención. Actualizar `login.component.ts` para usar este util (DRY).

- [ ] **Step 4: Módulo + build**

`change-password.module.ts` con `ReactiveFormsModule` + ruta propia (se enruta en Task 8). Run: `npm run build -- --configuration=preprod`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(qf-app): forced password change screen via /renew-password"
```

---

## Task 6: Servicio Angular `PharmaceuticalDirectorService` + modelos

**Files:**
- Modify: `qf-recetalia-app/src/app/model/response/dispensation-search-row.ts` — campos de control.
- Create: `qf-recetalia-app/src/app/services/pharmaceutical-director.service.ts`

- [ ] **Step 1: Ampliar el modelo `DispensationSearchRow`**

Agregar los campos que ahora devuelve el backend:
```typescript
dtControlAt?: string;
dtControlName?: string;
dtControlCjp?: string;
medicalProviderName?: string;
```

- [ ] **Step 2: Servicio**

```typescript
import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, map } from 'rxjs';
import { environment } from '../../environments/environment';
import { ApiResponse } from '../model/response/api-response';
import { Page } from '../model/page';
import { PharmacyResponse } from '../model/response/pharmacy-response';
import { DispensationSearchRow } from '../model/response/dispensation-search-row';

@Injectable({ providedIn: 'root' })
export class PharmaceuticalDirectorService {
  private base = `${environment.apiUrl}/pharmaceutical-director`;
  constructor(private http: HttpClient) {}

  getMyPharmacies(): Observable<PharmacyResponse[]> {
    return this.http.get<ApiResponse<PharmacyResponse[]>>(`${this.base}/pharmacies`)
      .pipe(map(r => r.answer));
  }

  getGreenDispensations(pharmacyId: string, opts: { startDate?: string; endDate?: string; page?: number; size?: number; sort?: string }):
      Observable<Page<DispensationSearchRow>> {
    let params = new HttpParams().set('pharmacyId', pharmacyId)
      .set('page', String(opts.page ?? 0)).set('size', String(opts.size ?? 10));
    if (opts.sort) params = params.set('sort', opts.sort);
    if (opts.startDate) params = params.set('startDate', opts.startDate);
    if (opts.endDate) params = params.set('endDate', opts.endDate);
    return this.http.get<ApiResponse<Page<DispensationSearchRow>>>(`${this.base}/green-dispensations`, { params })
      .pipe(map(r => r.answer));
  }

  control(dispensationId: string): Observable<boolean> {
    return this.http.post<ApiResponse<boolean>>(`${this.base}/dispensations/${dispensationId}/control`, {})
      .pipe(map(r => r.answer));
  }
}
```
Verificar el nombre/forma real de `ApiResponse`, `Page`, `PharmacyResponse` en el clon y ajustar imports.

- [ ] **Step 3: Build + commit**

Run: `npm run build -- --configuration=preprod`
```bash
git add -A && git commit -m "feat(qf-app): PharmaceuticalDirectorService + dtControl fields in model"
```

---

## Task 7: Pantalla 1 — Listado de farmacias del QF

**Files:**
- Create: `qf-recetalia-app/src/app/pages/application/home/pharmacies/pharmacy-list/pharmacy-list.component.{ts,html}`

- [ ] **Step 1: Componente**

```typescript
import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { PharmaceuticalDirectorService } from '../../../../../services/pharmaceutical-director.service';
import { PharmacyResponse } from '../../../../../model/response/pharmacy-response';

@Component({ selector: 'app-pharmacy-list', templateUrl: './pharmacy-list.component.html' })
export class PharmacyListComponent implements OnInit {
  pharmacies: PharmacyResponse[] = [];
  loading = true;
  constructor(private pd: PharmaceuticalDirectorService, private router: Router) {}
  ngOnInit(): void {
    this.pd.getMyPharmacies().subscribe({
      next: (list) => { this.pharmacies = list; this.loading = false; },
      error: () => { this.loading = false; }
    });
  }
  open(p: PharmacyResponse) { this.router.navigate(['/farmacias', p.id, 'recetas-verdes']); }
}
```

- [ ] **Step 2: HTML (p-table simple, click → detalle)**

```html
<div class="container mt-4">
  <h4>Mis farmacias</h4>
  <p-table [value]="pharmacies" [loading]="loading" [paginator]="pharmacies.length > 10" [rows]="10">
    <ng-template pTemplate="header">
      <tr><th>Farmacia</th><th>RUT</th><th>Estado</th><th></th></tr>
    </ng-template>
    <ng-template pTemplate="body" let-p>
      <tr class="cursor-pointer" (click)="open(p)">
        <td>{{ p.name }}</td><td>{{ p.rut }}</td><td>{{ p.status }}</td>
        <td><button class="btn btn-success btn-sm">Ver recetas verdes</button></td>
      </tr>
    </ng-template>
    <ng-template pTemplate="emptymessage"><tr><td colspan="4">No hay farmacias asignadas a tu CJP.</td></tr></ng-template>
  </p-table>
</div>
```

- [ ] **Step 3: Build + commit** (se enruta en Task 8)

```bash
git add -A && git commit -m "feat(qf-app): QF pharmacy list screen"
```

---

## Task 8: Pantalla 2 — Recetas verdes dispensadas + control (check)

**Files:**
- Create: `qf-recetalia-app/src/app/pages/application/home/green-dispensations/green-dispensations-list/green-dispensations-list.component.{ts,html}`

- [ ] **Step 1: Componente (p-table lazy + acción de control)**

```typescript
import { Component, OnInit } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { PharmaceuticalDirectorService } from '../../../../../services/pharmaceutical-director.service';
import { DispensationSearchRow } from '../../../../../model/response/dispensation-search-row';

@Component({ selector: 'app-green-dispensations-list', templateUrl: './green-dispensations-list.component.html' })
export class GreenDispensationsListComponent implements OnInit {
  pharmacyId!: string;
  rows: DispensationSearchRow[] = [];
  totalRecords = 0;
  loading = false;
  pageSize = 10;
  rangeDates: Date[] | null = null;
  controllingId: string | null = null;

  constructor(private route: ActivatedRoute, private pd: PharmaceuticalDirectorService) {}

  ngOnInit(): void { this.pharmacyId = this.route.snapshot.paramMap.get('pharmacyId')!; }

  load(event: any) {
    this.loading = true;
    const page = event ? Math.floor(event.first / event.rows) : 0;
    const size = event?.rows ?? this.pageSize;
    const startDate = this.rangeDates?.[0] ? this.toIso(this.rangeDates[0]) : undefined;
    const endDate = this.rangeDates?.[1] ? this.toIso(this.rangeDates[1]) : undefined;
    this.pd.getGreenDispensations(this.pharmacyId, { page, size, sort: 'dispensationCreatedAt,desc', startDate, endDate })
      .subscribe({
        next: (p) => { this.rows = p.content; this.totalRecords = p.totalElements; this.loading = false; },
        error: () => { this.loading = false; }
      });
  }

  control(row: DispensationSearchRow) {
    if (row.dtControlAt) return;
    this.controllingId = row.dispensationId;
    this.pd.control(row.dispensationId).subscribe({
      next: () => { row.dtControlAt = new Date().toISOString(); this.controllingId = null; },
      error: () => { this.controllingId = null; }
    });
  }

  applyFilter() { this.load({ first: 0, rows: this.pageSize }); }
  private toIso(d: Date): string { return d.toISOString().substring(0, 10); }
}
```

- [ ] **Step 2: HTML**

```html
<div class="container mt-4">
  <h4>Recetas verdes dispensadas</h4>
  <div class="d-flex align-items-center gap-2 mb-3">
    <p-calendar [(ngModel)]="rangeDates" selectionMode="range" dateFormat="dd/mm/yy"
                placeholder="Rango de fechas" [showButtonBar]="true"></p-calendar>
    <button class="btn btn-primary btn-sm" (click)="applyFilter()">Filtrar</button>
  </div>
  <p-table [value]="rows" [lazy]="true" (onLazyLoad)="load($event)" [loading]="loading"
           [paginator]="true" [rows]="pageSize" [totalRecords]="totalRecords" [rowsPerPageOptions]="[10,25,50]">
    <ng-template pTemplate="header">
      <tr><th>Código</th><th>Paciente</th><th>Médico</th><th>Medicamento</th>
          <th>Fecha disp.</th><th>Control D.T.</th></tr>
    </ng-template>
    <ng-template pTemplate="body" let-r>
      <tr class="back_green">
        <td>{{ r.prescriptionCode }}</td>
        <td>{{ r.patientName }} {{ r.patientLastName }}</td>
        <td>{{ r.medicName }} {{ r.medicLastname }}</td>
        <td>{{ r.dispensationProductName }}</td>
        <td>{{ (r.dispensationUpdatedAt || r.dispensationCreatedAt) | date:'dd/MM/yyyy HH:mm' }}</td>
        <td>
          <span *ngIf="r.dtControlAt" class="text-success">
            <i class="fas fa-check"></i> Controlada {{ r.dtControlAt | date:'dd/MM/yyyy' }}
          </span>
          <button *ngIf="!r.dtControlAt" class="btn btn-success btn-sm"
                  [disabled]="controllingId === r.dispensationId" (click)="control(r)">
            Controlar / Firmar
          </button>
        </td>
      </tr>
    </ng-template>
    <ng-template pTemplate="emptymessage"><tr><td colspan="6">Sin recetas verdes dispensadas en el período.</td></tr></ng-template>
  </p-table>
</div>
```
> `dispensationUpdatedAt` puede no venir en el modelo del clon; si falta, agregarlo a `DispensationSearchRow` (ya existe `dispensationCreatedAt`).

- [ ] **Step 3: Build + commit** (rutas en Task 9)

```bash
git add -A && git commit -m "feat(qf-app): green dispensations list with DT control (firma) action"
```

---

## Task 9: Guard, routing, sidebar y limpieza del scaffold

**Files:**
- Modify: `qf-recetalia-app/src/app/interceptors/auth.guard.ts`
- Modify: `qf-recetalia-app/src/app/app-routing.module.ts`
- Modify: `qf-recetalia-app/src/app/pages/application/home/home-routing.module.ts` + `home.module.ts`
- Modify: sidebar (`.../home/components/sidebar/sidebar.component.{ts,html}`)
- Delete: módulos/carpetas de farmacias no usados (prescriptions, dispensations add/search, patient, medicine, pharmacy-dispenser, dashboard, register, forgot-password) y sus referencias.

- [ ] **Step 1: Guard del QF (sin resolver farmacia)**

```typescript
export const authGuard: CanActivateFn = (route) => {
  const authService = inject(AuthService);
  const router = inject(Router);
  const user = authService.getCurrentUser();
  const allowed = (route.data?.['roles'] as string[]) ?? ['ROLE_PHARMACEUTICAL_DIRECTOR'];
  if (user && allowed.includes(user.role)) return true;
  router.navigate(['/login']);
  return false;
};
```

- [ ] **Step 2: Rutas raíz**

`app-routing.module.ts`:
```typescript
const routes: Routes = [
  { path: '', loadChildren: () => import('./pages/application/home/home.module').then(m => m.HomeModule),
    canActivate: [authGuard], data: { roles: ['ROLE_PHARMACEUTICAL_DIRECTOR'] } },
  { path: 'login', loadChildren: () => import('./pages/application/login/login.module').then(m => m.LoginModule) },
  { path: 'change-password', loadChildren: () => import('./pages/application/change-password/change-password.module').then(m => m.ChangePasswordModule) },
  { path: '**', redirectTo: 'login' },
];
```

- [ ] **Step 3: Rutas del home (2 pantallas)**

`home-routing.module.ts` (children bajo `HomeComponent`):
```typescript
{ path: '', component: PharmacyListComponent },
{ path: 'farmacias/:pharmacyId/recetas-verdes', component: GreenDispensationsListComponent },
```
Registrar ambos componentes en `home.module.ts` (declarations) e importar `TableModule`, `CalendarModule`, `ButtonModule`, `FormsModule`.

- [ ] **Step 4: Sidebar QF**

Reemplazar los links del sidebar por: "Mis farmacias" (`routerLink="/"`, icono `fas fa-shop`) y "Salir" (logout → `/login`). Quitar Dashboard/Dispensaciones/Perfil. Quitar la resolución de `pharmacyName` por email; mostrar el CJP (`authService.getCurrentUser()?.cjp`) o "Químico Farmacéutico".

- [ ] **Step 5: Eliminar módulos de farmacias no usados y arreglar imports**

Borrar las carpetas de features no usados y quitar sus imports/rutas. Tras borrar, compilar e ir resolviendo referencias rotas (servicios que sólo usaban esos módulos también se borran).
Run iterativo: `npm run build -- --configuration=preprod` hasta que compile.

- [ ] **Step 6: Branding mínimo**

Reemplazar `src/assets/images/logos/logo.png` y el favicon por los del QF si Pablo los provee; si no, dejar los de Recetalia (genéricos). Cambiar el `<title>` en `src/index.html` a "Recetalia — Químico Farmacéutico".

- [ ] **Step 7: Build final + commit**

Run: `npm run build -- --configuration=preprod`
Expected: `Application bundle generation complete`.
```bash
git add -A && git commit -m "feat(qf-app): QF routing, guard, sidebar; trim unused farmacias modules"
```

---

## Verificación (local, apuntando al backend del Plan 1)

> Requiere el backend del Plan 1 corriendo y accesible (con el rol/app/columnas ya aplicados en su DB), y al menos un QF creado (una sucursal con `managerCJP`). Para pruebas locales, apuntar `environment` al host correspondiente o usar `ng serve` con proxy.

- [ ] **V1: Servir la app** — `npm start` (o `npm run build` + servir `dist/qf-recetalia-app/browser` estático) y abrir el login.
- [ ] **V2: Login por CJP** — ingresar un CJP válido + el password genérico → si `mustChangePassword`, redirige a cambio de contraseña; cambiar → vuelve a login; re-login → entra al listado de farmacias.
- [ ] **V3: Farmacias** — el listado muestra sólo las sucursales con ese CJP.
- [ ] **V4: Recetas verdes** — al abrir una farmacia se listan sólo verdes dispensadas; "Controlar/Firmar" marca la fila como "Controlada DD/MM"; al recargar persiste (dtControlAt del backend).
- [ ] **V5: Rol** — con un token de otro rol, el guard redirige a `/login`.

---

## Self-Review (cobertura del spec)

- App nueva `qf-recetalia-app` clonada + reducida → Tasks 1, 9. Environment `apipre` + dominio QF → Task 2.
- Login por CJP → Task 4. Cambio forzado de contraseña → Tasks 4-5. Rol QF en el guard → Task 9.
- Listado de farmacias del QF → Tasks 6-7. Verdes dispensadas + check de control → Tasks 6, 8.
- **Fuera de esta fase:** módulo/listado + Excel en la app de Farmacias (Plan 3); DNS/nginx/cert/deploy de `qfpre.doctorconsultas.com` (Plan 4).

**A validar durante ejecución (ajustar inline):**
- Forma real de `AuthResponse`/`ApiResponse`/`Page`/`PharmacyResponse` y del padding AES del login original (replicarlo idéntico en `crypto.util.ts`).
- Nombres reales de módulos/carpetas a borrar en Task 9 (compilar iterando).
- Que `DispensationSearchRow` del clon tenga `dispensationUpdatedAt`/`dispensationProductName` (agregar si faltan).
