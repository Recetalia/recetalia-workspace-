# QF — Bandeja de curación en Gestión — Plan 2c

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que Gestión vea qué Químicos Farmacéuticos quedaron con el CJP en revisión y pueda saltar a corregir las farmacias que lo causan.

**Architecture:** Una pantalla de listado en el menú de Gestión que consume `GET /api/pharmaceutical-directors/needs-review`. Cada fila es un QF; al expandirla se ven las farmacias que declaran su CJP con el titular que cada una dice, que es donde se ve el conflicto. Desde ahí se abre el modal de farmacia que ya existe para corregir el CJP.

**Tech Stack:** Angular 18.2 (NgModule, no standalone), PrimeNG 17 (`p-table` con row expansion, `DialogService`), Bootstrap 5.

**Spec:** [2026-07-31-qf-registro-y-libro-negro-papel-design.md](2026-07-31-qf-registro-y-libro-negro-papel-design.md) — sección "Cómo se cura un CJP marcado".

---

## Contexto imprescindible antes de empezar

**El problema, con números reales de DEV.** Un backfill marcó `status = 'NEEDS_REVIEW'` a los QF cuyo CJP figura con más de un titular en `pharmacy`: **20 CJPs que cubren 65 de 337 farmacias**. El peor caso es el CJP `1`, usado por seis personas distintas como número de relleno (SAN ROQUE en varias sucursales, ALBISU, BOTICA). Otros son la misma persona escrita distinto: `ANDREA FILIPPINI` / `Andrea Fillippini`, `ADRIANA TELECHEA` / `ADRIANA TELLECHEA`.

Un QF marcado **no puede listar farmacias, ni ver recetas verdes, ni firmar, ni registrarse**. Sin esta pantalla la curación es posible pero invisible: habría que ir farmacia por farmacia sin saber cuáles están mal.

**Cómo se cura, y por qué esta pantalla alcanza.** Gestión corrige el `managerCJP` de las farmacias equivocadas desde el modal que ya existe. Cuando el CJP deja de figurar con más de un titular, el backend lo detecta solo (`recomputeStatus`, ya implementado y validado) y el QF pasa a `ACTIVE`. A partir de ahí ese QF puede entrar y corregir su propio nombre y documento en su pantalla de registro. **No hace falta que Gestión edite la entidad QF** — el dato se arregla solo por el camino largo, y el corto sería duplicar la fuente de verdad.

**El endpoint ya existe y está validado en DEV:**

```
GET /api/pharmaceutical-directors/needs-review     (rol ROLE_ROLE_MANAGEMENT)
→ {"status":"SUCCESS","answer":[
     {"id","cjp","name","lastname","status",
      "pharmacies":[{"id","name","managerName","managerLastname"}]}
   ]}
```

Devuelve 20 filas. Verificado que responde 401 sin token y 403 con token de QF.

**Cómo está armada esta app:**
- **No hay módulos por feature**: todo se declara en `home.module.ts` y las rutas hijas van en `home-routing.module.ts`, **sin lazy loading**.
- **No hay filtrado por rol en el sidebar**: el guard vive en `app-routing.module.ts` sobre la ruta raíz (`data: { roles: ['ROLE_MANAGEMENT'] }`). Alcanza con agregar el `<li>`.
- Ya están importados en `HomeModule` los módulos de PrimeNG que hacen falta: `TableModule`, `ButtonModule`, `DynamicDialogModule`, y `providers: [DialogService]`.
- **Gotcha documentado en el propio código:** con `[lazy]="true"` no hay que llamar al load en `ngOnInit` — provoca doble request y la lista queda "trabada". Acá **no** usamos lazy (son 20 filas finitas), así que el load va en `ngOnInit` como en `medical-provider-list`.

**Comandos:** `npm run build`. No hay tests ni lint en esta app: la verificación es en el browser.

**Rama:** seguir en `feat/qf-lookup-cjp` de `gestion-recetadigital-app`, donde quedó el Plan 2b (commit `d1fd1e5`).

---

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `model/response/pharmaceutical-director-review-row.ts` | Tipo de la fila |
| `services/pharmaceutical-director.service.ts` | Cliente del endpoint |
| `pages/application/home/pharmaceutical-director/pharmaceutical-director-list/*` | La pantalla |
| `pages/application/home/home-routing.module.ts` | Ruta hija |
| `pages/application/home/home.module.ts` | Declaración del componente |
| `pages/application/home/components/sidebar/sidebar.component.html` | Ítem de menú |

El servicio va **aparte** de `PharmacyService` a propósito: aquel ya tiene 195 líneas y apunta a `/pharmacies`; este apunta a otro recurso.

---

### Task 1: Modelo y servicio

**Files:**
- Create: `src/app/model/response/pharmaceutical-director-review-row.ts`
- Create: `src/app/services/pharmaceutical-director.service.ts`

- [ ] **Step 1: El modelo**

```typescript
/** Una fila de la bandeja de curación: un QF y las farmacias que declaran su CJP. */
export interface PharmaceuticalDirectorReviewRow {
  id: string;
  cjp: string;
  name: string;
  lastname: string;
  status: string;
  pharmacies: PharmacyBrief[];
}

export interface PharmacyBrief {
  id: string;
  name: string;
  /** Titular que declara esa farmacia. Si difiere entre filas, ahí está el conflicto. */
  managerName: string;
  managerLastname: string;
}
```

- [ ] **Step 2: El servicio**

```typescript
import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { map, catchError } from 'rxjs/operators';
import { environment } from '../../environments/environment';
import { ApiResponse } from '../model/response/api-response';
import { PharmaceuticalDirectorReviewRow } from '../model/response/pharmaceutical-director-review-row';

@Injectable({
  providedIn: 'root'
})
export class PharmaceuticalDirectorService {
  private baseUrl = `${environment.apiUrl}/pharmaceutical-directors`;

  constructor(private http: HttpClient) { }

  /**
   * Bandeja de curación: los QF cuyo CJP figura con más de un titular en `pharmacy`.
   * Requiere rol de Gestión.
   */
  getNeedsReview(): Observable<PharmaceuticalDirectorReviewRow[]> {
    return this.http.get<ApiResponse<PharmaceuticalDirectorReviewRow[]>>(`${this.baseUrl}/needs-review`).pipe(
      map(response => {
        if (response.status === 'SUCCESS') {
          return response.answer;
        }
        throw new Error('API responded with error: ' + response.applicationProvider);
      }),
      catchError(error => {
        console.error('Failed to fetch pharmaceutical directors needing review:', error);
        const msg = error?.error?.answer || error?.message || 'No se pudo obtener la lista de químicos en revisión.';
        return throwError(() => new Error(msg));
      })
    );
  }
}
```

- [ ] **Step 3: Build**

Run: `npm run build`
Expected: build exitoso.

- [ ] **Step 4: Commit**

```bash
git add src/app/model/response/pharmaceutical-director-review-row.ts \
        src/app/services/pharmaceutical-director.service.ts
git commit -m "feat(qf): servicio de la bandeja de curacion"
```

---

### Task 2: La pantalla

**Files:**
- Create: `src/app/pages/application/home/pharmaceutical-director/pharmaceutical-director-list/pharmaceutical-director-list.component.ts`
- Create: `.../pharmaceutical-director-list.component.html`
- Create: `.../pharmaceutical-director-list.component.scss`
- Modify: `src/app/pages/application/home/home.module.ts`
- Modify: `src/app/pages/application/home/home-routing.module.ts`
- Modify: `src/app/pages/application/home/components/sidebar/sidebar.component.html`

- [ ] **Step 1: El componente**

```typescript
import { Component, OnInit, NgZone } from '@angular/core';
import { DialogService } from 'primeng/dynamicdialog';
import { take } from 'rxjs';
import {
  PharmaceuticalDirectorReviewRow,
  PharmacyBrief
} from '../../../../../model/response/pharmaceutical-director-review-row';
import { PharmaceuticalDirectorService } from '../../../../../services/pharmaceutical-director.service';
import { PharmacyUpdateComponent } from '../../pharmacy/pharmacy-update/pharmacy-update.component';

@Component({
  selector: 'app-pharmaceutical-director-list',
  standalone: false,
  templateUrl: './pharmaceutical-director-list.component.html',
  styleUrls: ['./pharmaceutical-director-list.component.scss'],
})
export class PharmaceuticalDirectorListComponent implements OnInit {

  rows: PharmaceuticalDirectorReviewRow[] = [];
  loading = false;
  errorMessage = '';
  expanded: { [cjp: string]: boolean } = {};

  constructor(
    private service: PharmaceuticalDirectorService,
    private zone: NgZone,
    private dialogService: DialogService,
  ) { }

  // Sin [lazy]: son 20 filas finitas, se cargan todas de una.
  ngOnInit(): void { this.load(); }

  load(): void {
    this.loading = true;
    this.errorMessage = '';
    this.service.getNeedsReview().subscribe({
      next: data => this.zone.run(() => {
        this.rows = data;
        this.loading = false;
      }),
      error: (err) => this.zone.run(() => {
        this.errorMessage = err?.message || 'No se pudo obtener la lista.';
        this.loading = false;
      }),
    });
  }

  /** Los titulares distintos que declaran las farmacias de este CJP: el conflicto en sí. */
  titulares(row: PharmaceuticalDirectorReviewRow): string[] {
    const set = new Set<string>();
    (row.pharmacies || []).forEach(p => {
      const nombre = `${(p.managerName || '').trim()} ${(p.managerLastname || '').trim()}`.trim();
      if (nombre) { set.add(nombre); }
    });
    return Array.from(set).sort();
  }

  /**
   * Abre el modal de la farmacia para corregirle el CJP. Al cerrarse se recarga la bandeja:
   * si la corrección resolvió el conflicto, el backend ya pasó ese QF a ACTIVE y la fila
   * desaparece sola.
   */
  openPharmacy(pharmacy: PharmacyBrief): void {
    const ref = this.dialogService.open(PharmacyUpdateComponent, {
      header: `Editar Farmacia - ${pharmacy.name}`,
      style: { width: '95%', 'max-width': '95%' },
      contentStyle: { 'max-height': '95vh', overflow: 'auto' },
      dismissableMask: true,
      data: { id: pharmacy.id }
    });
    ref.onClose.pipe(take(1)).subscribe(() => this.load());
  }
}
```

- [ ] **Step 2: El HTML**

```html
<div class="content-table mt-3">
  <h2>Químicos Farmacéuticos en revisión</h2>

  <p class="text-muted">
    Estos CJP figuran con más de un titular entre las farmacias que los declaran, así que no
    identifican a una persona. Mientras estén en revisión, esos químicos no pueden registrarse
    ni firmar recetas verdes. Para resolverlo, corregí el CJP de las farmacias que lo tengan mal:
    cuando el CJP deje de estar compartido, el químico se habilita solo y la fila desaparece.
  </p>

  <div *ngIf="errorMessage" class="alert alert-danger">{{ errorMessage }}</div>

  <div class="d-flex justify-content-between align-items-center mb-2">
    <span class="text-muted" *ngIf="!loading">{{ rows.length }} en revisión</span>
    <button type="button" class="btn btn-outline-secondary" (click)="load()" [disabled]="loading">
      Actualizar
    </button>
  </div>

  <p-table [value]="rows" [loading]="loading" dataKey="cjp" class="custom-table">
    <ng-template pTemplate="header">
      <tr>
        <th style="width:3rem"></th>
        <th>CJP</th>
        <th>Titulares en conflicto</th>
        <th style="width:9rem">Farmacias</th>
      </tr>
    </ng-template>

    <ng-template pTemplate="body" let-row let-expanded="expanded">
      <tr>
        <td>
          <button type="button" pButton pRipple [pRowToggler]="row"
            class="p-button-text p-button-rounded p-button-plain"
            [icon]="expanded ? 'pi pi-chevron-down' : 'pi pi-chevron-right'"></button>
        </td>
        <td><strong>{{ row.cjp }}</strong></td>
        <td>
          <div *ngFor="let t of titulares(row)">{{ t }}</div>
        </td>
        <td>{{ row.pharmacies.length }}</td>
      </tr>
    </ng-template>

    <ng-template pTemplate="rowexpansion" let-row>
      <tr>
        <td colspan="4">
          <table class="table table-sm mb-0">
            <thead>
              <tr>
                <th>Farmacia</th>
                <th>Titular que declara</th>
                <th style="width:8rem"></th>
              </tr>
            </thead>
            <tbody>
              <tr *ngFor="let p of row.pharmacies">
                <td>{{ p.name }}</td>
                <td>{{ p.managerName }} {{ p.managerLastname }}</td>
                <td>
                  <button type="button" class="btn btn-sm btn-outline-primary"
                    (click)="openPharmacy(p)">
                    Corregir
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </td>
      </tr>
    </ng-template>

    <ng-template pTemplate="emptymessage">
      <tr>
        <td colspan="4" class="text-center text-muted py-4">
          No hay químicos en revisión.
        </td>
      </tr>
    </ng-template>
  </p-table>
</div>
```

- [ ] **Step 3: El SCSS**

Crear el archivo vacío (el componente lo referencia y las clases vienen de Bootstrap y de los estilos globales de `custom-table`):

```scss
/* Los estilos vienen de Bootstrap y de la clase global .custom-table. */
```

- [ ] **Step 4: Registrar el componente**

En `home.module.ts`: agregar el import y sumar `PharmaceuticalDirectorListComponent` al array `declarations`.

⚠️ **`pRowToggler` y `pRipple` vienen de módulos de PrimeNG que pueden no estar importados.** `pRowToggler` es parte de `TableModule` (ya está). `pRipple` es de `RippleModule` — **verificá si está en los imports de `HomeModule`**; si no está, o lo agregás, o sacás el `pRipple` del botón (es solo el efecto visual de onda, no hace falta). Elegí sacarlo antes que sumar un módulo por un efecto cosmético, y decilo en el reporte.

- [ ] **Step 5: La ruta**

En `home-routing.module.ts`, agregar el import del componente y la ruta hija junto a las demás:

```typescript
      {
        path: "pharmaceutical-directors",
        component: PharmaceuticalDirectorListComponent,
      },
```

- [ ] **Step 6: El ítem del sidebar**

En `sidebar.component.html`, dentro del `<ul class="nav flex-column nav-submenu">` de la sección **Farmacias** (donde ya están "Farmacias" y "Cadenas"), agregar como tercer ítem:

```html
        <li class="nav-item">
          <a class="nav-link" routerLink="pharmaceutical-directors" routerLinkActive="active" (click)="closeSidebar()">
            <i class="fas fa-flask"></i> <span>Químicos</span>
          </a>
        </li>
```

Va en esa sección porque el QF es un atributo de la farmacia y ahí es donde alguien lo va a buscar.

**Y ajustá el colapsable** para que la sección quede abierta cuando se está en esa ruta. En `sidebar.component.ts`, en `updateSectionRouteState`:

```typescript
    this.pharmacySectionRouteActive = path.includes('/pharmacies')
      || path.includes('/franchises')
      || path.includes('/pharmaceutical-directors');
```

- [ ] **Step 7: Build**

Run: `npm run build`
Expected: build exitoso, sin errores de template (`strictTemplates` está activo).

- [ ] **Step 8: Commit**

```bash
git add src/app/pages/application/home/pharmaceutical-director \
        src/app/pages/application/home/home.module.ts \
        src/app/pages/application/home/home-routing.module.ts \
        src/app/pages/application/home/components/sidebar
git commit -m "feat(qf): bandeja de curacion de CJPs en Gestion"
```

---

### Task 3: Deploy y validación

**Files:** ninguno — es verificación.

- [ ] **Step 1: Deployar Gestión al .98**

```bash
cd /Users/pablo/iwtg/recetalia-workspace
rsync -az --delete --exclude .git --exclude node_modules --exclude dist --exclude .angular \
  gestion-recetadigital-app/ root@138.197.150.98:/opt/recetalia/gestion-recetadigital-app/
ssh root@138.197.150.98 "cd /opt/recetalia/deploy-recetalia && \
  docker compose build gestion-recetadigital-app && \
  docker compose up -d --no-deps gestion-recetadigital-app"
```

⚠️ **Nunca `docker compose up -d` a secas**: recrea nginx y rompe PRE.

- [ ] **Step 2: Confirmar que el bundle nuevo se sirve**

La ruta nueva introduce la cadena `pharmaceutical-directors/needs-review`. Bajá los chunks que referencia el index de `gestionpre.recetalia.com` y buscala; reportá en qué archivo apareció. Si no aparece, el build no tomó los cambios.

- [ ] **Step 3: El endpoint, con token de Gestión**

```bash
TOKEN=$(curl -s -X POST "https://apipre.recetalia.com/security-api-recetalia/api/auth/loginBack" \
  -H "Content-Type: application/json" \
  -d '{"email":"gestion@recetalia.com","password":"1wtg_p4ss","info":"000"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmaceutical-directors/needs-review" \
  | python3 -c "import sys,json; d=json.load(sys.stdin)['answer']; print(len(d),'filas'); print(d[0]['cjp'], len(d[0]['pharmacies']),'farmacias')"
```

Esperado: 20 filas.

- [ ] **Step 4: Regresión del ambiente**

Los 5 frontends de PRE en 200 y ningún contenedor caído salvo `observatorio-cpa`.

- [ ] **Step 5: Lo que hay que mirar en el browser**

La extensión de Chrome puede no estar conectada; si no lo está, **dejá la lista escrita para que la valide una persona** en vez de darla por buena:

1. `gestionpre.recetalia.com` → login `gestion@recetalia.com` / `1wtg_p4ss` → menú **Farmacias → Químicos**.
2. Tienen que aparecer **20 filas**. La del CJP `1` debe listar **6 titulares distintos** y **7 farmacias**.
3. Expandir esa fila muestra las 7 farmacias con el titular que declara cada una.
4. "Corregir" abre el modal de esa farmacia, ya con el aviso rojo de CJP en revisión (viene del Plan 2b).
5. Al cerrar el modal, la bandeja se recarga.

---

## Lo que queda después de este plan

- **Plan 3** — la app del QF: pantalla de registro (`/registro`) que reemplaza a `/change-password`, más el Nº de talonario en el listado de recetas verdes.
- **Plan 4** — Mantenimiento de Libro Negro en Farmacias (la carga de recetas en papel: es la feature 2 del pedido original, y la única de las tres que no está empezada), más endurecer por rol el Excel de controlados.
