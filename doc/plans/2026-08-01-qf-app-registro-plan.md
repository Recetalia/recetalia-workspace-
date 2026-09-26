# QF — Pantalla de registro y Nº de talonario — Plan 3

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el Químico Farmacéutico, en su primer ingreso, verifique sus datos, vea qué farmacias lo declararon D.T. y defina su propia clave. Y que el listado de recetas verdes muestre el Nº de talonario además del código Recetalia.

**Architecture:** La pantalla `/change-password` (que solo pide clave) se reemplaza por `/registro`, que precarga con `GET /api/pharmaceutical-director/me` y guarda con `POST .../register` — los dos endpoints ya existen. Un guard nuevo impide entrar a la app sin haber completado el registro. Del lado del backend falta una pieza: el Nº de talonario está en la tabla pero nunca se agregó a la proyección que alimenta los listados.

**Tech Stack:** Angular 18.2 (NgModule), Bootstrap 5.3 para formularios, PrimeNG 17 solo para tablas y calendario. Backend: Java 21 / Spring Boot 3.3, query nativa con proyección por interfaz.

**Spec:** [2026-07-31-qf-registro-y-libro-negro-papel-design.md](2026-07-31-qf-registro-y-libro-negro-papel-design.md) — secciones "1.B Primer ingreso" y "Feature 3".

---

## Contexto imprescindible antes de empezar

**Qué existe ya, y funciona en DEV:**

| Endpoint | Qué hace |
|---|---|
| `GET /api/pharmaceutical-director/me` | Datos del QF autenticado + sus farmacias. **No bloquea a los `NEEDS_REVIEW`**, a propósito: es el que permite mostrarle por qué no puede operar |
| `POST /api/pharmaceutical-director/register` | Renueva la clave, sella `registeredAt` y propaga los datos a las farmacias. Rechaza a los `NEEDS_REVIEW` |
| `GET /api/pharmaceutical-director/pharmacies` \| `/green-dispensations` \| `.../control` | El módulo QF que ya estaba |

`/me` devuelve `{id, cjp, name, lastname, document, email, phone, status, registeredAt, pharmacies[]}`. **`status` puede ser `ACTIVE`, `INACTIVE` o `NEEDS_REVIEW`**, y `registeredAt` en `null` significa que nunca completó el registro.

**Por qué importa el `NEEDS_REVIEW`.** 19 CJPs reales figuran con más de un titular entre las farmacias que los declaran (el CJP `1` lo usan seis personas). Esos QF no pueden registrarse ni firmar hasta que Gestión cure el dato desde la bandeja del Plan 2c. La pantalla nueva tiene que explicárselo, no dejarlo golpeándose contra un error.

**Cómo entra el QF hoy:** login con CJP → el front arma `{cjp}@qf.recetalia.com` → si la respuesta trae `mustChangePassword`, guarda `qf_email` en `localStorage` y navega a `/change-password`. Eso se reemplaza.

**Trampa conocida de esta app, ya resuelta, no la reintroduzcas:** el `AuthInterceptor` no debe mandar `Bearer` a `/api/auth/*` — el security-api lo rechaza con 401 y el interceptor terminaba deslogueando al usuario en pleno cambio de clave.

**Cifrado:** `generateDynamicInfo()` y `encryptPassword()` viven en `src/app/shared/utils/crypto.util.ts`. `AuthService.renewPassword` ya completa los campos que el backend exige por `@NotBlank` aunque no use.

**Esta app no tiene tests.** La verificación es en el browser. Build: `npm run build`.

**Ramas:** `recetalia-api-rest` sigue en `feat/qf-registro-y-papel`. `qf-recetalia-app` está en `2.x.y` y **no tiene remoto todavía** — crear `feat/qf-registro-app` ahí.

---

### Task 1: Backend — el Nº de talonario en la proyección

El Nº vive en `prescription.paperNumber` desde el Plan 1, pero la query nativa que alimenta todos los listados de dispensaciones nunca lo seleccionó, así que no llega al front.

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/dto/response/DispensationSearchRow.java`
- Modify: `src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java`

- [ ] **Step 1: Agregar los getters a la proyección**

En `DispensationSearchRow`, junto a los campos de prescription (después de `getCondvtaId()`):

```java
  /** Nº de talonario de la receta verde en papel. NULL para las emitidas por Recetalia. */
  String  getPrescriptionPaperNumber();
  /** DIGITAL | PAPER. */
  String  getPrescriptionOrigin();
```

- [ ] **Step 2: Seleccionarlos en la query nativa**

En `DispensationRepository.searchDispensations`, dentro del `value` del `@Query`, agregar dos líneas al SELECT junto a las otras de `pr.` (por ejemplo después de `pr.createdAt AS prescriptionCreatedAt`):

```sql
      pr.paperNumber AS prescriptionPaperNumber,
      pr.origin AS prescriptionOrigin,
```

⚠️ **Solo en el `value`, NO en el `countQuery`** — ese hace `SELECT COUNT(*)` y no tiene lista de columnas.

⚠️ **Ojo con la coma.** Es una query larga escrita como text block: verificá que la línea anterior termine en coma y que la última de tu agregado también, o el SQL no compila y solo te vas a enterar en runtime (`ddl-auto: none`, la query nativa no se valida al arrancar).

- [ ] **Step 3: Compilar**

Run: `./gradlew build`
Expected: `BUILD SUCCESSFUL`, 137 tests verdes. Los tests no ejercitan esta query (no hay DB en los tests), así que el build verde **no** prueba que el SQL esté bien: eso se verifica en la Task 4.

- [ ] **Step 4: Commit**

```bash
git add src/main/java/com/recetalia/api/application/dto/response/DispensationSearchRow.java \
        src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java
git commit -m "feat(qf): exponer el Nro de talonario y el origen en la proyeccion de dispensaciones"
```

---

### Task 2: App QF — la pantalla de registro

**Files:**
- Create: `src/app/model/response/pharmaceutical-director-me-response.ts`
- Modify: `src/app/services/pharmaceutical-director.service.ts`
- Create: `src/app/pages/application/registro/registro.component.{ts,html,scss}`
- Create: `src/app/pages/application/registro/registro.module.ts`
- Create: `src/app/pages/application/registro/registro-routing.module.ts`
- Create: `src/app/interceptors/registered.guard.ts`
- Modify: `src/app/app-routing.module.ts`
- Modify: `src/app/pages/application/login/login.component.ts`
- Delete: `src/app/pages/application/change-password/` (los 5 archivos)

- [ ] **Step 1: El modelo**

`src/app/model/response/pharmaceutical-director-me-response.ts`:

```typescript
import { PharmacyResponse } from './pharmacy-response';

export interface PharmaceuticalDirectorMeResponse {
  id: string;
  cjp: string;
  name: string;
  lastname: string;
  document: { number: string; type: string } | null;
  email: string | null;
  phone: any | null;
  /** ACTIVE | INACTIVE | NEEDS_REVIEW */
  status: string;
  /** null = nunca completó el registro */
  registeredAt: string | null;
  pharmacies: PharmacyResponse[];
}
```

- [ ] **Step 2: Los métodos del servicio**

En `src/app/services/pharmaceutical-director.service.ts`, agregar el import del modelo y:

```typescript
  getMe(): Observable<PharmaceuticalDirectorMeResponse> {
    return this.http.get<ApiResponse<PharmaceuticalDirectorMeResponse>>(`${this.base}/me`)
      .pipe(map(r => r.answer));
  }

  register(body: {
    name: string; lastname: string;
    document: { number: string; type: string } | null;
    email: string | null; phone: any | null;
    password: string; info: string;
  }): Observable<PharmaceuticalDirectorMeResponse> {
    return this.http.post<ApiResponse<PharmaceuticalDirectorMeResponse>>(`${this.base}/register`, body)
      .pipe(map(r => r.answer));
  }
```

- [ ] **Step 3: El componente**

`src/app/pages/application/registro/registro.component.ts`:

```typescript
import { Component, Inject, OnInit, PLATFORM_ID } from '@angular/core';
import { Router } from '@angular/router';
import { FormBuilder, FormGroup, Validators } from '@angular/forms';
import { isPlatformBrowser } from '@angular/common';
import { AuthService } from '../../../services/auth.service';
import { PharmaceuticalDirectorService } from '../../../services/pharmaceutical-director.service';
import { PharmaceuticalDirectorMeResponse } from '../../../model/response/pharmaceutical-director-me-response';
import { PharmacyResponse } from '../../../model/response/pharmacy-response';
import { generateDynamicInfo, encryptPassword } from '../../../shared/utils/crypto.util';

@Component({
  selector: 'app-registro',
  templateUrl: './registro.component.html',
  styleUrls: ['./registro.component.scss']
})
export class RegistroComponent implements OnInit {

  form!: FormGroup;
  me: PharmaceuticalDirectorMeResponse | null = null;
  pharmacies: PharmacyResponse[] = [];
  loading = true;
  saving = false;
  error: string | null = null;

  /** El CJP figura con más de un titular: no es una identidad y no puede registrarse. */
  enRevision = false;

  constructor(
    private fb: FormBuilder,
    private pd: PharmaceuticalDirectorService,
    private authService: AuthService,
    private router: Router,
    @Inject(PLATFORM_ID) private platformId: Object
  ) {}

  ngOnInit(): void {
    this.form = this.fb.group({
      name: ['', Validators.required],
      lastname: ['', Validators.required],
      documentType: ['UY'],
      documentNumber: [''],
      email: ['', Validators.email],
      password: ['', [Validators.required, Validators.minLength(6)]],
      confirm: ['', [Validators.required, Validators.minLength(6)]],
    });

    this.pd.getMe().subscribe({
      next: (me) => {
        this.me = me;
        this.pharmacies = me.pharmacies ?? [];
        this.enRevision = me.status === 'NEEDS_REVIEW';

        // Los datos vienen de lo que cargó la farmacia; el QF los verifica y corrige.
        this.form.patchValue({
          name: me.name ?? '',
          lastname: me.lastname ?? '',
          documentType: me.document?.type ?? 'UY',
          documentNumber: me.document?.number ?? '',
          email: me.email ?? '',
        });

        if (this.enRevision) { this.form.disable(); }
        this.loading = false;
      },
      error: () => {
        this.error = 'No pudimos cargar tus datos. Volvé a entrar.';
        this.loading = false;
      }
    });
  }

  get f() { return this.form.controls; }

  onSubmit(): void {
    this.error = null;
    if (this.enRevision) { return; }
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }
    const v = this.form.value;
    if (v.password !== v.confirm) {
      this.error = 'Las contraseñas no coinciden';
      return;
    }

    this.saving = true;
    const info = generateDynamicInfo();
    this.pd.register({
      name: v.name,
      lastname: v.lastname,
      document: v.documentNumber ? { number: v.documentNumber, type: v.documentType } : null,
      email: v.email || null,
      phone: null,
      password: encryptPassword(v.password, info),
      info,
    }).subscribe({
      next: () => {
        // La clave cambió: el token viejo ya no sirve, hay que volver a entrar.
        this.authService.clearToken();
        if (isPlatformBrowser(this.platformId)) {
          localStorage.removeItem('qf_email');
        }
        this.router.navigate(['/login'], { queryParams: { registrado: 1 } });
      },
      error: (err) => {
        this.saving = false;
        this.error = err?.error?.answer || 'No se pudo completar el registro.';
      }
    });
  }
}
```

- [ ] **Step 4: El HTML**

`registro.component.html` (Bootstrap puro, como el resto de esta app):

```html
<div class="container mt-4 mb-5" style="max-width: 720px;">

  <div *ngIf="loading" class="text-center py-5">Cargando tus datos…</div>

  <ng-container *ngIf="!loading">

    <h3>Completá tu registro</h3>
    <p class="text-muted" *ngIf="!enRevision">
      Es tu primer ingreso. Verificá tus datos, mirá las farmacias que te declararon
      Director Técnico y definí tu contraseña.
    </p>

    <!-- CJP en revisión: no puede registrarse hasta que Gestión cure el dato -->
    <div *ngIf="enRevision" class="alert alert-warning">
      <strong>Tu registro está en revisión.</strong><br>
      El CJP {{ me?.cjp }} figura con más de un titular entre las farmacias que lo declararon,
      así que todavía no podemos confirmar tu identidad. Contactate con Recetalia para
      habilitarlo.
    </div>

    <form [formGroup]="form" (ngSubmit)="onSubmit()">

      <h5 class="mt-4">Tus datos</h5>

      <div class="mb-3">
        <label class="form-label">CJP</label>
        <input type="text" class="form-control" [value]="me?.cjp" disabled>
      </div>

      <div class="mb-3">
        <label class="form-label">Nombre</label>
        <input type="text" class="form-control" formControlName="name">
        <div *ngIf="f['name'].touched && f['name'].invalid" class="text-danger">
          <p>El nombre es necesario.</p>
        </div>
      </div>

      <div class="mb-3">
        <label class="form-label">Apellido</label>
        <input type="text" class="form-control" formControlName="lastname">
        <div *ngIf="f['lastname'].touched && f['lastname'].invalid" class="text-danger">
          <p>El apellido es necesario.</p>
        </div>
      </div>

      <div class="mb-3">
        <label class="form-label">Documento</label>
        <select class="form-select mb-2" formControlName="documentType">
          <option value="UY">Cédula UY</option>
          <option value="AR">Cédula AR</option>
          <option value="PASSPORT">Pasaporte</option>
          <option value="RUT">RUT</option>
          <option value="OTHER">Otro</option>
        </select>
        <input type="text" class="form-control" formControlName="documentNumber"
               placeholder="Número de documento">
      </div>

      <div class="mb-3">
        <label class="form-label">Email de contacto</label>
        <input type="email" class="form-control" formControlName="email"
               placeholder="tu@email.com">
        <div *ngIf="f['email'].touched && f['email'].invalid" class="text-danger">
          <p>El email no parece válido.</p>
        </div>
      </div>

      <h5 class="mt-4">Farmacias que te declararon Director Técnico</h5>
      <ul class="list-group mb-3" *ngIf="pharmacies.length">
        <li class="list-group-item" *ngFor="let p of pharmacies">
          <strong>{{ p.name }}</strong>
          <span class="text-muted" *ngIf="p.addressStreet">
            — {{ p.addressStreet }} {{ p.addressNumber }}
          </span>
        </li>
      </ul>
      <div class="alert alert-secondary" *ngIf="!pharmacies.length">
        Todavía no hay farmacias asociadas a tu CJP.
      </div>

      <h5 class="mt-4">Tu contraseña</h5>
      <p class="text-muted">
        Definí una contraseña propia. La que te dio la farmacia deja de funcionar.
      </p>

      <div class="mb-3">
        <input type="password" class="form-control" placeholder="Nueva contraseña"
               formControlName="password">
        <div *ngIf="f['password'].touched && f['password'].invalid" class="text-danger">
          <p>Mínimo 6 caracteres.</p>
        </div>
      </div>

      <div class="mb-3">
        <input type="password" class="form-control" placeholder="Repetí la contraseña"
               formControlName="confirm">
      </div>

      <div *ngIf="error" class="alert alert-danger">{{ error }}</div>

      <div class="text-center mt-4">
        <button type="submit" class="btn btn-primary"
                [disabled]="enRevision || saving || form.invalid">
          {{ saving ? 'Guardando…' : 'Completar registro' }}
        </button>
      </div>

    </form>
  </ng-container>
</div>
```

- [ ] **Step 5: SCSS, módulo y routing**

`registro.component.scss`:

```scss
/* Los estilos vienen de Bootstrap. */
```

`registro-routing.module.ts`:

```typescript
import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';
import { RegistroComponent } from './registro.component';

const routes: Routes = [
  { path: '', component: RegistroComponent }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})
export class RegistroRoutingModule { }
```

`registro.module.ts`:

```typescript
import { CUSTOM_ELEMENTS_SCHEMA, NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule } from '@angular/forms';
import { RegistroComponent } from './registro.component';
import { RegistroRoutingModule } from './registro-routing.module';

@NgModule({
  declarations: [RegistroComponent],
  imports: [
    CommonModule,
    ReactiveFormsModule,
    RegistroRoutingModule
  ],
  schemas: [CUSTOM_ELEMENTS_SCHEMA]
})
export class RegistroModule { }
```

- [ ] **Step 6: El guard que impide entrar sin registrarse**

`src/app/interceptors/registered.guard.ts`:

```typescript
import { CanActivateFn, Router } from '@angular/router';
import { inject } from '@angular/core';
import { map, of, catchError } from 'rxjs';
import { PharmaceuticalDirectorService } from '../services/pharmaceutical-director.service';

/**
 * Un QF que no completó su registro no puede usar la app: se lo manda a /registro.
 * Consulta /me porque `registeredAt` no viaja en el token — el token solo trae
 * `mustChangePassword`, que se apaga al renovar la clave, y eso no alcanza para saber
 * si además verificó sus datos.
 */
export const registeredGuard: CanActivateFn = () => {
  const pd = inject(PharmaceuticalDirectorService);
  const router = inject(Router);

  return pd.getMe().pipe(
    map(me => me.registeredAt ? true : router.createUrlTree(['/registro'])),
    // Si /me falla no hay forma de saberlo: se deja pasar y que falle donde corresponda,
    // en vez de encerrar al usuario en un redirect por un error de red.
    catchError(() => of(true))
  );
};
```

- [ ] **Step 7: Enganchar el routing**

En `app-routing.module.ts`: importar `registeredGuard`, **reemplazar la ruta `change-password` por `registro`**, y sumar el guard nuevo a la raíz:

```typescript
  {
    path: '',
    loadChildren: () => import('./pages/application/home/home.module').then(h => h.HomeModule),
    canActivate: [authGuard, registeredGuard],
    data: { roles: ['ROLE_PHARMACEUTICAL_DIRECTOR'] }
  },
  {
    path: 'login',
    loadChildren: () => import('./pages/application/login/login.module').then(l => l.LoginModule)
  },
  {
    path: 'registro',
    loadChildren: () => import('./pages/application/registro/registro.module').then(m => m.RegistroModule)
  },
  { path: '**', redirectTo: 'login' }
```

⚠️ **`/registro` queda sin `authGuard` a propósito**, igual que estaba `change-password`: el QF llega ahí recién logueado y el interceptor le pone el `Bearer`. Si no hubiera token, `/me` devuelve 401 y el componente muestra el error. **No le pongas `registeredGuard`**, o se redirige a sí mismo en loop.

- [ ] **Step 8: El login navega a `/registro`**

En `login.component.ts`, en el `next` del subscribe, cambiar `this.router.navigate(['/change-password'])` por `this.router.navigate(['/registro'])`. El `localStorage.setItem('qf_email', email)` se puede dejar (no molesta) o sacar: la pantalla nueva no lo usa, porque `/register` resuelve el QF del token.

- [ ] **Step 9: Borrar la pantalla vieja**

```bash
git rm -r src/app/pages/application/change-password
```

Verificá con grep que no quede ninguna referencia a `change-password` ni a `ChangePasswordModule`.

- [ ] **Step 10: Build y commit**

```bash
npm run build
git add -A src/app
git commit -m "feat(qf): pantalla de registro del QF en reemplazo del cambio de clave"
```

---

### Task 3: App QF — el Nº de talonario en el listado

**Files:**
- Modify: `src/app/model/response/dispensation-search-row.ts`
- Modify: `src/app/pages/application/home/green-dispensations/green-dispensations-list/green-dispensations-list.component.html`

- [ ] **Step 1: El modelo**

En `dispensation-search-row.ts`, en el bloque de Prescription:

```typescript
  /** Nº de talonario de la receta verde en papel. Ausente en las emitidas por Recetalia. */
  prescriptionPaperNumber?: string | null;
  /** DIGITAL | PAPER */
  prescriptionOrigin?: string | null;
```

- [ ] **Step 2: La columna en dos líneas**

En el `.html`, reemplazar la celda del código:

```html
        <td>{{ r.prescriptionCode }}</td>
```

por:

```html
        <td>
          {{ r.prescriptionCode }}
          <div *ngIf="r.prescriptionPaperNumber" class="text-muted small">
            Nº {{ r.prescriptionPaperNumber }}
          </div>
        </td>
```

Sin `paperNumber` la segunda línea no se renderiza, que es el caso de todas las recetas emitidas por Recetalia.

- [ ] **Step 3: Build y commit**

```bash
npm run build
git add src/app/model/response/dispensation-search-row.ts \
        src/app/pages/application/home/green-dispensations
git commit -m "feat(qf): mostrar el Nro de talonario junto al codigo Recetalia"
```

---

### Task 4: Deploy y validación

**Files:** ninguno — es verificación.

- [ ] **Step 1: Deployar api-rest y la app QF**

```bash
cd /Users/pablo/iwtg/recetalia-workspace
rsync -az --delete --exclude .git --exclude build --exclude .gradle \
  recetalia-api-rest/ root@138.197.150.98:/opt/recetalia/recetalia-api-rest/
rsync -az --delete --exclude .git --exclude node_modules --exclude dist --exclude .angular \
  qf-recetalia-app/ root@138.197.150.98:/opt/recetalia/qf-recetalia-app/
ssh root@138.197.150.98 "cd /opt/recetalia/deploy-recetalia && docker compose build recetalia-api-rest"
ssh root@138.197.150.98 "cd /opt/recetalia/deploy-recetalia && docker compose build qf-app"
ssh root@138.197.150.98 "cd /opt/recetalia/deploy-recetalia && docker compose up -d --no-deps recetalia-api-rest qf-app"
```

⚠️ **`--no-deps` siempre**: un `up -d` a secas recrea nginx y rompe PRE. Los builds, en serie.
⚠️ **El servicio de la app QF puede no llamarse `qf-app`** — está en el overlay `docker-compose.dev98.yml`. Confirmá el nombre con `docker compose config --services` antes de buildear.

- [ ] **Step 2: Que la query nueva no rompió el listado — lo más importante**

El SQL solo se valida en runtime. Si la coma quedó mal, este endpoint tira 500:

```bash
QFTOKEN=$(curl -s -X POST "https://apipre.recetalia.com/security-api-recetalia/api/auth/loginBack" \
  -H "Content-Type: application/json" \
  -d '{"email":"999999@qf.recetalia.com","password":"Recetalia2026!","info":"000"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

PH=$(curl -s -H "Authorization: Bearer $QFTOKEN" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmaceutical-director/pharmacies" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['answer'][0]['id'])")

curl -s -H "Authorization: Bearer $QFTOKEN" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmaceutical-director/green-dispensations?pharmacyId=$PH&page=0&size=5" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)['answer']
print(d['totalElements'],'dispensaciones verdes')
for r in d['content'][:3]:
    print(r['prescriptionCode'], '| paperNumber:', r.get('prescriptionPaperNumber'), '| origin:', r.get('prescriptionOrigin'))
"
```

Esperado: sin 500, y cada fila con `prescriptionOrigin: DIGITAL` y `prescriptionPaperNumber: None` — todavía no hay recetas de papel, esas llegan con el Plan 4. **Lo que se está probando acá es que la query sigue andando y que los campos nuevos viajan.**

Verificá también que **el Libro Negro de Farmacias y el Excel de controlados sigan funcionando**, porque usan la misma query:

```bash
FTOKEN=$(curl -s -X POST "https://apipre.recetalia.com/security-api-recetalia/api/auth/loginBack" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"Recetalia2026!","info":"000"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -s -o /dev/null -w "dispensations/search: %{http_code}\n" -H "Authorization: Bearer $FTOKEN" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/dispensations/search?condvtaId=GREEN&page=0&size=5"
```

- [ ] **Step 3: `/me` y el flujo de registro, por API**

```bash
curl -s -H "Authorization: Bearer $QFTOKEN" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmaceutical-director/me" \
  | python3 -m json.tool
```

Esperado: `status: ACTIVE`, `registeredAt: null`, y las 3 farmacias.

**NO ejecutes el `POST /register`**: consumiría el primer ingreso del QF de prueba y le cambiaría la clave, dejando el ambiente en un estado que hay que restaurar a mano. Se prueba en el browser, en el step siguiente.

- [ ] **Step 4: Regresión**

Los 5 frontends de PRE en 200 y ningún contenedor caído salvo `observatorio-cpa`.

- [ ] **Step 5: Lo que hay que mirar en el browser**

Si la extensión de Chrome no está conectada, **dejá esta lista escrita para que la valide una persona** en vez de darla por buena:

1. `qfpre.recetalia.com` → login con CJP **999999** / `Recetalia2026!` → tiene que caer en **`/registro`**, no en la app.
2. La pantalla muestra el CJP en solo lectura, nombre y apellido precargados, y **las 3 farmacias** (ARIES, MINAS, Test).
3. Intentar navegar a `/` sin completar el registro tiene que devolverlo a `/registro`.
4. Completar el registro con una clave nueva → vuelve al login con el aviso.
5. Entrar con la clave nueva → ahora sí entra a la app y ve sus farmacias.
6. Abrir una farmacia: el listado de recetas verdes sigue andando, y la columna Código muestra solo el código (sin `Nº`, porque todavía no hay recetas de papel).
7. **Un QF en revisión**: entrar con un CJP de los marcados (sacalo de la bandeja de Gestión) tiene que mostrar el cartel amarillo con el formulario deshabilitado.

⚠️ Después del punto 4 **la clave del QF de prueba cambia**. Anotá cuál pusiste y actualizá la memoria `pre-environment-access`, o restaurá el estado dejando `registeredAt` en NULL y la clave original.

---

## Lo que queda después de este plan

**Plan 4 — Mantenimiento de Libro Negro**, la carga de recetas en papel desde Farmacias. Es la feature 2 del pedido original y la única de las tres que no está empezada. Incluye también:
- El Nº de talonario en el Libro Negro de Farmacias y en el Excel de controlados (con este plan ya viaja en la proyección; falta mostrarlo en esos dos lugares).
- Endurecer por rol el endpoint del Excel, que quedó en `authenticated()` desde julio.
