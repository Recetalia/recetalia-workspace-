# QF — Validación por Gestión — Plan 2: Pantallas

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans. Los steps usan checkbox (`- [ ]`).

**Goal:** Que Gestión pueda habilitar QFs desde la pantalla, y que los formularios de farmacia dejen de pedir la clave del QF.

**Architecture:** El backend ya está hecho y validado ([Plan 1](2026-08-02-qf-validacion-backend-plan.md)). Acá van dos cosas: una solapa nueva en la bandeja de QF de Gestión con el modal de clave, y sacar el campo de clave de los dos formularios de alta/edición de farmacia.

**Tech Stack:** Angular 18 (NgModule, no standalone salvo donde el repo ya lo use), Reactive Forms, PrimeNG 17 + Bootstrap 5.

**Spec:** [2026-08-02-qf-validacion-gestion-design.md](2026-08-02-qf-validacion-gestion-design.md)

---

## Contexto imprescindible

**Ramas:** `gestion-recetadigital-app` y `farmacias-recetalia-app` están las dos en `feat/qf-lookup-cjp`.

**El backend ya expone y está validado en DEV:**

| Endpoint | Body | Devuelve |
|---|---|---|
| `GET /api/pharmaceutical-directors/pending-validation` | — | `PharmaceuticalDirectorReviewRow[]` |
| `POST /api/pharmaceutical-directors/{cjp}/validate` | `{"password":"..."}` | `true` |
| `POST /api/pharmaceutical-directors/{cjp}/reassign-password` | `{"password":"..."}` | `true` |

Los tres exigen rol de Gestión (protegidos por path en `SecurityConfiguration`).

**La clave viaja EN CLARO.** No se cifra AES como en el login: estos endpoints usan el camino `...Back` del security-api justamente porque no hay front que cifre. **No la pases por `encryptPassword`.**

### Las trampas

⚠️ **Un `@Valid` roto vuelve como 500 "Error interno del servidor" sin decir qué campo.** `GlobalExceptionHandler` del backend no extiende `ResponseEntityExceptionHandler`. El backend exige la clave con **mínimo 8 caracteres**: si el formulario no lo valida del lado del cliente, el operador ve "Error interno del servidor" y no entiende nada. **Validá en el front.**

⚠️ **El service de Gestión ya propaga bien los errores** (`pharmaceutical-director.service.ts` lee `error?.error?.answer`). Seguí ese patrón en los métodos nuevos: los mensajes del backend son útiles ("El QF con CJP X ya está habilitado").

⚠️ **La bandeja usa `zone.run(...)`** en los callbacks (ver `pharmaceutical-director-list.component.ts:36-45`). Es por SSR/change detection: mantenelo en el código nuevo o la tabla no se refresca.

⚠️ **En `farmacias-recetalia-app` el service worker sirve assets viejos.** Después de deployar hay que desregistrar el SW y limpiar caches; un F5 no alcanza. Ver la Task 5.

---

### Task 1: El servicio de Gestión

**Files:**
- Modify: `gestion-recetadigital-app/src/app/services/pharmaceutical-director.service.ts`

- [ ] **Step 1: Los tres métodos**

Agregá al service, siguiendo exactamente el patrón de `getNeedsReview` (mismo `map`, mismo `catchError` que lee `error?.error?.answer`):

```typescript
  /** QF que todavía no puede usar nadie: esperan que Gestión los habilite. */
  getPendingValidation(): Observable<PharmaceuticalDirectorReviewRow[]> {
    return this.http.get<ApiResponse<PharmaceuticalDirectorReviewRow[]>>(`${this.baseUrl}/pending-validation`).pipe(
      map(response => {
        if (response.status === 'SUCCESS') { return response.answer; }
        throw new Error('API responded with error: ' + response.applicationProvider);
      }),
      catchError(error => {
        console.error('Failed to fetch pending validation:', error);
        const msg = error?.error?.answer || error?.message || 'No se pudo obtener la lista de pendientes.';
        return throwError(() => new Error(msg));
      })
    );
  }

  /**
   * Habilita al QF y le crea el usuario de login con esta clave.
   * La clave viaja EN CLARO a propósito: el backend usa el camino `...Back` del security-api,
   * que no descifra. No la cifres con AES.
   */
  validate(cjp: string, password: string): Observable<boolean> {
    return this.http.post<ApiResponse<boolean>>(`${this.baseUrl}/${encodeURIComponent(cjp)}/validate`, { password }).pipe(
      map(response => {
        if (response.status === 'SUCCESS') { return response.answer; }
        throw new Error('API responded with error: ' + response.applicationProvider);
      }),
      catchError(error => {
        console.error('Failed to validate QF:', error);
        const msg = error?.error?.answer || error?.message || 'No se pudo habilitar al químico farmacéutico.';
        return throwError(() => new Error(msg));
      })
    );
  }

  /** Le asigna una clave nueva a un QF ya habilitado. Misma advertencia sobre el cifrado. */
  reassignPassword(cjp: string, password: string): Observable<boolean> {
    return this.http.post<ApiResponse<boolean>>(`${this.baseUrl}/${encodeURIComponent(cjp)}/reassign-password`, { password }).pipe(
      map(response => {
        if (response.status === 'SUCCESS') { return response.answer; }
        throw new Error('API responded with error: ' + response.applicationProvider);
      }),
      catchError(error => {
        console.error('Failed to reassign QF password:', error);
        const msg = error?.error?.answer || error?.message || 'No se pudo reasignar la clave.';
        return throwError(() => new Error(msg));
      })
    );
  }
```

- [ ] **Step 2: `validatedAt` en el modelo de la fila**

En `src/app/model/response/pharmaceutical-director-review-row.ts`:

```typescript
  /** Cuándo Gestión lo habilitó. Ausente/null = pendiente. */
  validatedAt?: string | null;
```

- [ ] **Step 3: Build y commit**

`npm run build` → exit 0.

```bash
git add -A
git commit -m "feat(qf): servicio de habilitacion de quimicos farmaceuticos

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: La solapa de pendientes

La bandeja de hoy muestra sólo los `NEEDS_REVIEW`. Pasa a tener dos solapas.

**Files:**
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/pharmaceutical-director/pharmaceutical-director-list/pharmaceutical-director-list.component.{ts,html}`
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/home.module.ts`

- [ ] **Step 1: El componente**

En el `.ts`, agregá el estado de la solapa nueva y el modal:

```typescript
  // --- solapa de pendientes de habilitación ---
  pending: PharmaceuticalDirectorReviewRow[] = [];
  pendingLoading = false;

  // --- modal de clave ---
  passwordTarget: PharmaceuticalDirectorReviewRow | null = null;
  /** 'validate' = habilitar por primera vez. 'reassign' = ya está habilitado. */
  passwordMode: 'validate' | 'reassign' = 'validate';
  password = '';
  passwordSaving = false;
  passwordError = '';
  successMessage = '';

  loadPending(): void {
    this.pendingLoading = true;
    this.errorMessage = '';
    this.service.getPendingValidation().subscribe({
      next: data => this.zone.run(() => { this.pending = data; this.pendingLoading = false; }),
      error: err => this.zone.run(() => {
        this.errorMessage = err?.message || 'No se pudo obtener la lista.';
        this.pendingLoading = false;
      }),
    });
  }

  askPassword(row: PharmaceuticalDirectorReviewRow, mode: 'validate' | 'reassign'): void {
    this.passwordTarget = row;
    this.passwordMode = mode;
    this.password = '';
    this.passwordError = '';
    this.successMessage = '';
  }

  dismissPassword(): void { this.passwordTarget = null; }

  /**
   * El backend exige 8 caracteres, pero un @Valid roto vuelve como 500 "Error interno del
   * servidor" sin decir qué campo: si no validamos acá, el operador no entiende qué pasó.
   */
  get passwordInvalid(): boolean { return this.password.trim().length < 8; }

  confirmPassword(): void {
    if (!this.passwordTarget || this.passwordInvalid) { return; }
    const cjp = this.passwordTarget.cjp;
    const mode = this.passwordMode;
    this.passwordSaving = true;
    this.passwordError = '';

    const call = mode === 'validate'
      ? this.service.validate(cjp, this.password.trim())
      : this.service.reassignPassword(cjp, this.password.trim());

    call.subscribe({
      next: () => this.zone.run(() => {
        this.passwordSaving = false;
        this.passwordTarget = null;
        this.successMessage = mode === 'validate'
          ? `Químico ${cjp} habilitado. Pasale la clave: la va a tener que cambiar al entrar.`
          : `Clave reasignada al químico ${cjp}. La anterior dejó de servir.`;
        this.loadPending();
      }),
      error: err => this.zone.run(() => {
        this.passwordSaving = false;
        this.passwordError = err?.message || 'No se pudo completar la operación.';
      }),
    });
  }
```

Y en `ngOnInit`, cargá también los pendientes: `this.load(); this.loadPending();`

- [ ] **Step 2: El template**

Envolvé el contenido actual en un `p-tabView` con dos solapas. La solapa **"Pendientes de habilitación"** va primera (es la accionable); la de revisión queda como está, sin tocar su tabla.

La tabla de pendientes: CJP, nombre y apellido, email si lo hay, farmacias asociadas, y un botón **"Habilitar"** por fila. Reusá el patrón de la tabla existente (`p-table` con `dataKey="cjp"`, `class="custom-table"`).

Arriba de la tabla, un texto que explique qué es esto:

```html
    <p class="text-muted">
      Estos químicos fueron declarados por una farmacia pero todavía no pueden entrar a su app.
      Al habilitarlos les asignás una clave, que tenés que hacerles llegar por fuera del sistema.
      La van a tener que cambiar la primera vez que entren.
    </p>
```

El modal (un `p-dialog`, mismo patrón que el resto de la app):

```html
<p-dialog [visible]="!!passwordTarget" (visibleChange)="!$event && dismissPassword()"
          [header]="passwordMode === 'validate' ? 'Habilitar químico farmacéutico' : 'Reasignar clave'"
          [modal]="true" [draggable]="false" [style]="{ width: '90vw', maxWidth: '480px' }">
  <div *ngIf="passwordError" class="alert alert-danger">{{ passwordError }}</div>

  <p *ngIf="passwordTarget">
    <strong>{{ passwordTarget.name }} {{ passwordTarget.lastname }}</strong> — CJP {{ passwordTarget.cjp }}
  </p>

  <label class="form-label">Clave</label>
  <input type="text" class="form-control" [(ngModel)]="password"
         placeholder="Mínimo 8 caracteres" autocomplete="off" />
  <small class="text-muted">
    Se la tenés que pasar vos por fuera del sistema. Va a tener que cambiarla al entrar.
  </small>
  <div *ngIf="password && passwordInvalid" class="text-danger small mt-1">
    La clave necesita al menos 8 caracteres.
  </div>

  <ng-template pTemplate="footer">
    <button type="button" class="btn btn-outline-secondary" (click)="dismissPassword()"
            [disabled]="passwordSaving">Cancelar</button>
    <button type="button" class="btn btn-primary" (click)="confirmPassword()"
            [disabled]="passwordSaving || passwordInvalid">
      {{ passwordSaving ? 'Guardando...' : (passwordMode === 'validate' ? 'Habilitar' : 'Reasignar') }}
    </button>
  </ng-template>
</p-dialog>
```

Y arriba de todo, el cartel de éxito:

```html
<div *ngIf="successMessage" class="alert alert-success">{{ successMessage }}</div>
```

⚠️ La clave va en un `<input type="text">` a propósito: el operador **tiene que poder leer lo que escribe** para dictarla. No uses `p-password` ni `type="password"`.

- [ ] **Step 3: Los módulos**

Verificá que `TabViewModule` (`primeng/tabview`), `DialogModule` (`primeng/dialog`) y `FormsModule` estén importados en `home.module.ts`. Agregá los que falten.

- [ ] **Step 4: Build y commit**

`npm run build` → exit 0.

---

### Task 3: Sacar la clave del registro de Farmacias

**Files:**
- Modify: `farmacias-recetalia-app/src/app/pages/application/register/register.component.{ts,html}`
- Modify: `farmacias-recetalia-app/src/app/model/request/pharmacy-request.ts`

- [ ] **Step 1: El modelo**

En `pharmacy-request.ts:31`, reemplazá `managerPassword?: string;` por:

```typescript
  /** Email del QF. Opcional: si está, Gestión lo contacta directo al habilitarlo. */
  managerEmail?: string;
```

- [ ] **Step 2: El formulario**

En `register.component.ts`:
- Sacá `managerPassword: ['']` del `FormGroup` (línea ~73) y poné `managerEmail: ['']`.
- Sacá el bloque de la línea ~145 que le pone/saca validadores a `managerPassword` según `qfState`.
- En el payload (línea ~222), sacá `managerPassword: ...encryptPassword(...)` y mandá `managerEmail: formValue.managerEmail?.trim() || null`.

⚠️ **No toques el `encryptPassword` de la clave de la FARMACIA** — esa sigue yendo cifrada. La que se va es la del QF.

- [ ] **Step 3: El template**

En `register.component.html`, borrá el bloque de las líneas ~239-250 (label + `p-password` + el error de `managerPassword`) y poné en su lugar el campo de email y el aviso:

```html
            <div class="col-12 col-md-6" *ngIf="qfState === 'new'">
              <label for="managerEmail">Email del Químico Farmacéutico (opcional)</label>
              <input type="email" id="managerEmail" class="form-control" formControlName="managerEmail"
                     placeholder="Para que Recetalia pueda contactarlo" />
            </div>

            <div class="col-12" *ngIf="qfState === 'new'">
              <div class="alert alert-info">
                El acceso del Químico Farmacéutico será habilitado por Recetalia. Le vamos a hacer
                llegar su clave para que pueda entrar a su aplicación.
              </div>
            </div>
```

Mantené la condición `qfState === 'new'` que ya usa el bloque de la clave: si el CJP ya existe, el QF ya está creado y no hay nada que declarar.

- [ ] **Step 4: Build y commit**

`npm run build` → exit 0. Verificá que no quede ninguna referencia: `grep -rn managerPassword src/` → vacío.

---

### Task 4: Sacar la clave del modal de Gestión

**Files:**
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/pharmacy/pharmacy-update/pharmacy-update.component.{ts,html}`
- Modify: `gestion-recetadigital-app/src/app/model/request/pharmacy-request.ts`

- [ ] **Step 1: Lo mismo que la Task 3**

Mismo cambio en el modelo (`managerPassword` → `managerEmail`), en el `FormGroup`, en el payload y en el template (líneas ~267-287 del HTML, que incluyen el toggle de `reveal.managerPassword`).

Acá el aviso puede ser más corto, porque el operador de Gestión ya sabe cómo sigue:

```html
              <div class="col-12" *ngIf="qfState === 'new'">
                <div class="alert alert-info">
                  El químico va a quedar pendiente de habilitación. Habilitalo desde
                  <strong>Farmacias → Químicos</strong> para asignarle su clave.
                </div>
              </div>
```

- [ ] **Step 2: Build y commit**

`npm run build` → exit 0. `grep -rn managerPassword src/` → vacío.

---

### Task 5: Validación en DEV

- [ ] **Step 1: Deploy**

```bash
for APP in gestion-recetadigital-app farmacias-recetalia-app; do
  rsync -az --delete --exclude='.git' --exclude='node_modules' --exclude='dist' \
    --exclude='.angular' "$APP/" "root@138.197.150.98:/opt/recetalia/$APP/"
done
ssh root@138.197.150.98 'cd /opt/recetalia/deploy-recetalia && \
  docker compose build gestion-recetadigital-app && \
  docker compose build farmacias-recetalia-app && \
  docker compose up -d --no-deps gestion-recetadigital-app farmacias-recetalia-app'
```

⚠️ Builds **en serie** (los frontends en paralelo agotan la RAM de 8GB) y `--no-deps` nombrando servicios (un `up -d` a secas recrea nginx y rompe PRE).

- [ ] **Step 2: Limpiar el service worker antes de probar**

En el browser, sobre el dominio de la app:

```javascript
const r = await navigator.serviceWorker.getRegistrations();
for (const x of r) await x.unregister();
for (const n of await caches.keys()) await caches.delete(n);
```

Y recargar. **Sin esto vas a estar mirando el bundle viejo** y diagnosticando bugs que no existen.

- [ ] **Step 3: El circuito en `gestionpre.recetalia.com`**

1. Farmacias → Químicos → tiene que haber dos solapas.
2. "Pendientes de habilitación": el CJP `777001` (dato de prueba del Plan 1) tiene que estar… **salvo que ya lo hayas habilitado** — en ese caso creá otro pendiente:
```bash
ssh root@138.197.150.98 "docker exec -e MYSQL_PWD='RecDev98_x7Kq2mVt' recetalia-mysql \
  mysql -urecetalia_dev recetali_receta -e \"INSERT INTO pharmaceutical_director \
  (id,cjp,name,lastname,status,createdAt,updatedAt,validatedAt) VALUES \
  (UUID(),'777002','QF','PruebaPantalla','ACTIVE',NOW(),NOW(),NULL);\""
```
3. Habilitar → clave de menos de 8 caracteres → el botón queda deshabilitado y avisa.
4. Con una clave válida → mensaje de éxito y la fila desaparece de pendientes.
5. Loguear ese QF en `qfpre.recetalia.com` con esa clave → entra y le pide cambiarla.
6. Reasignar clave desde la bandeja → la anterior deja de servir.

- [ ] **Step 4: El registro de Farmacias**

En `farmaciaspre.recetalia.com/register/`: el formulario **ya no pide la clave del QF**, muestra el email opcional y el aviso. Con un CJP que ya existe, ni el email ni el aviso aparecen.

- [ ] **Step 5: Que no se rompió nada**

La solapa de "en revisión" sigue listando los 20 de siempre, y el modal de edición de farmacia sigue guardando.

---

## Lo que queda afuera

**El QF de la app (`qf-recetalia-app`) no se toca.** Como el usuario de login no existe hasta que Gestión valida, un QF sin habilitar no puede loguear: nunca ve una pantalla de "no habilitado". Ver la spec, sección "La consecuencia que simplifica el alcance".
