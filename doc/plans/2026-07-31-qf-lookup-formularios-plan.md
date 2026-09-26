# QF — Lookup por CJP en los formularios de farmacia — Plan 2b

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que al tipear el CJP del Director Técnico, el formulario busque si ese Químico Farmacéutico ya existe: si existe lo muestra en solo lectura y lo asocia, y si no existe pide sus datos y una clave inicial.

**Architecture:** Un lookup contra `GET /api/pharmacies/pharmaceutical-director-lookup/{cjp}` disparado al salir del campo CJP, que pone el formulario en uno de cuatro estados y ajusta qué campos están habilitados. Mismo comportamiento en las dos apps, con el código adaptado a cada una.

**Tech Stack:** Angular 18.2 (NgModule, no standalone), Reactive Forms, Bootstrap 5 + PrimeNG 17, RxJS, TypeScript strict.

**Spec:** [2026-07-31-qf-registro-y-libro-negro-papel-design.md](2026-07-31-qf-registro-y-libro-negro-papel-design.md) — sección "1.A Alta / selección del QF desde la farmacia".
**Backend:** Planes [2a](2026-07-31-qf-curacion-backend-plan.md) y [1](2026-07-31-qf-registro-backend-plan.md), completos y validados en DEV.

---

## Contexto imprescindible antes de empezar

**Son dos formularios, no cuatro.** Los `profile` de Farmacias y Gestión tienen los campos del D.T. **deshabilitados** — solo los muestran. Los únicos que los editan son el **registro de Farmacias** (alta pública) y el **modal `pharmacy-update` de Gestión** (alta y edición). No toques los `profile`.

**Ramas.** `farmacias-recetalia-app` está en `2.x.y` con 10 commits sin pushear; `gestion-recetadigital-app` está en `main` limpia. Crear en cada una:

```bash
git checkout -b feat/qf-lookup-cjp
```

**El endpoint ya existe y está validado en DEV.** `GET /api/pharmacies/pharmaceutical-director-lookup/{cjp}`, público, y devuelve tres respuestas distintas que el front tiene que distinguir:

| Situación | HTTP | Cuerpo |
|---|---|---|
| El QF existe y está habilitado | 200 | `{"status":"SUCCESS","answer":{"cjp","name","lastname"}}` |
| No existe ningún QF con ese CJP | 404 | `{"status":"ERROR","answer":"No hay QF con CJP :: 51697"}` |
| Existe pero su CJP está en revisión | 400 | `{"status":"ERROR","answer":"El CJP 1 está en revisión porque figura con más de un titular. Contactate con Recetalia antes de asociarlo."}` |

El 400 pasa con **20 CJPs reales** (65 de 337 farmacias): son CJPs compartidos por personas distintas, que el sistema marcó como identidad no confiable. El formulario no puede dejar asociar uno de esos.

**Los servicios de las dos apps desenvuelven `ApiResponse` y tiran el error.** El de farmacias propaga el mensaje del backend (`error?.error?.answer`), el de gestión no. Vas a necesitar el mensaje en las dos, así que el método nuevo del servicio de gestión tiene que propagarlo también.

**Las dos apps ya mandan `info`** (el sufijo de la clave AES) en todos los submits que importan, así que la clave inicial del QF se cifra con la misma llave que el resto del alta. No hay nada que agregar ahí.

**Estilo de UI:** inputs HTML planos con clases Bootstrap (`form-group`, `form-control`, `text-danger`), PrimeNG solo para dropdowns, password y diálogos. No hay `MessageService` ni toastr: los errores de campo van en un `div.text-danger` inline y el resultado del submit en un `p-dialog` con la string `messageRegister`.

**Comandos:** `npm run build` en cada app. No hay lint ni prettier configurados.

---

## El comportamiento, igual en las dos apps

Un solo estado, `qfState`, con cuatro valores:

```
idle       → todavía no se buscó (CJP vacío)
searching  → consulta en vuelo
found      → el QF existe: nombre y apellido en solo lectura, sin pedir clave
new        → no existe: se piden nombre, apellido, documento y clave inicial
blocked    → el CJP está en revisión, o falló la consulta: no se puede guardar
```

```
CJP del D.T.  [51697        ]  ← al salir del campo, busca

┌─ found ───────────────────────┐   ┌─ new ─────────────────────────┐
│ ✓ JUAN PEREZ — CJP 51697      │   │ CJP 51697 — QF nuevo          │
│                               │   │ Nombre    [            ]      │
│ Ya registrado en Recetalia.   │   │ Apellido  [            ]      │
│ Se asocia a esta farmacia.    │   │ Documento [            ]      │
│                               │   │ Clave inicial [        ]      │
│ (sin campos editables)        │   │ ↳ entregásela al QF en mano   │
└───────────────────────────────┘   └───────────────────────────────┘

┌─ blocked ─────────────────────────────────────────────┐
│ ⚠ El CJP 1 está en revisión porque figura con más de  │
│   un titular. Contactate con Recetalia antes de       │
│   asociarlo.                                          │
│   (no se puede guardar)                               │
└───────────────────────────────────────────────────────┘
```

**Dos reglas que no se pueden violar:**

1. **Un fallo de red va a `blocked`, no a `new`.** Si el lookup se cae por timeout y el formulario habilitara el alta, se terminaría creando un QF duplicado para un CJP que sí existía. Solo el 404 explícito habilita el alta.
2. **En `found` no se manda `managerPassword`.** El backend ignora ese campo cuando el QF ya existe, pero mandarlo sería filtrar una clave que nadie va a usar.

**Un riesgo a verificar apenas tengas el estado `found` andando.** Los dos formularios tienen un
validador a nivel de grupo, `documentValidator(new ValidateDocumentPipe())`, que mira
`managerDocumentNumber` / `managerDocumentType`. En `found` esos campos quedan vacíos, y si el
validador marca `invalidDocument` con un documento vacío el formulario nunca va a ser válido y el
botón de guardar queda muerto **sin ningún mensaje visible** — el síntoma más difícil de
diagnosticar de todos.

Leé `shared/validators/document-validator.ts` antes de dar la task por cerrada. Si no hace
short-circuit con valor vacío, la salida es hacer que el validador se saltee cuando no hay
documento cargado (es el comportamiento correcto en general, no un parche para este caso: un
documento vacío es asunto de `required`, no de "inválido"). **Probalo en el browser**, no solo
razonándolo.

**Dos lugares donde el plan no puede darte el código exacto**, porque no tengo esos fragmentos a
la vista: el `<button type="submit">` de cada formulario (para agregarle `qfBlocksSubmit` al
`[disabled]`) y, en Gestión, el método que hace el `patchValue` con los datos de la farmacia en
modo edición. Los dos están señalados en su paso con qué buscar y qué hacer una vez encontrado.

---

### Task 1: Farmacias — registro

**Files:**
- Modify: `src/app/model/request/pharmacy-request.ts`
- Modify: `src/app/services/pharmacy.service.ts`
- Modify: `src/app/pages/application/register/register.component.ts`
- Modify: `src/app/pages/application/register/register.component.html`

- [ ] **Step 1: Agregar `managerPassword` al modelo**

En `pharmacy-request.ts`, después de `managerCJP`:

```typescript
  /**
   * Clave inicial del Químico Farmacéutico, definida por la farmacia y entregada en mano.
   * Solo se manda cuando el CJP no existe todavía; si el QF ya existe el backend la ignora.
   * Viaja cifrada AES con el mismo `info` que el resto del alta.
   */
  managerPassword?: string;
```

- [ ] **Step 2: Agregar el modelo de la respuesta del lookup**

Crear `src/app/model/response/pharmaceutical-director-lookup-response.ts`:

```typescript
export interface PharmaceuticalDirectorLookupResponse {
  cjp: string;
  name: string;
  lastname: string;
}
```

- [ ] **Step 3: Agregar el método al servicio**

En `src/app/services/pharmacy.service.ts`, después de `create`:

```typescript
  /**
   * Busca un Químico Farmacéutico por CJP. Endpoint público.
   * 404 = no existe (se puede dar de alta). 400 = el CJP está en revisión (no se puede asociar).
   * El error se propaga con el mensaje del backend, que el formulario muestra tal cual.
   */
  lookupPharmaceuticalDirector(cjp: string): Observable<PharmaceuticalDirectorLookupResponse> {
    const url = `${this.baseUrl}/pharmaceutical-director-lookup/${encodeURIComponent(cjp)}`;
    return this.http.get<ApiResponse<PharmaceuticalDirectorLookupResponse>>(url).pipe(
      map(response => {
        if (response.status === 'SUCCESS') {
          return response.answer;
        }
        throw new Error('API responded with error: ' + response.applicationProvider);
      }),
      catchError(error => {
        const status = error?.status;
        const msg = error?.error?.answer || error?.message || 'No se pudo verificar el CJP.';
        return throwError(() => ({ status, message: msg }));
      })
    );
  }
```

Agregar el import de `PharmaceuticalDirectorLookupResponse`.

- [ ] **Step 4: Estado y lógica en el componente**

En `register.component.ts`, agregar el import del modelo y estas propiedades junto a las que ya están:

```typescript
  qfState: 'idle' | 'searching' | 'found' | 'new' | 'blocked' = 'idle';
  qfFound: PharmaceuticalDirectorLookupResponse | null = null;
  qfMessage: string = '';
  private lastLookedUpCjp: string | null = null;
```

Agregar `managerPassword` al `fb.group`, después de `managerDocumentType`:

```typescript
      managerPassword: [''],
```

Sin validador fijo: se lo pone y se lo saca el lookup según el estado.

Agregar los métodos:

```typescript
  /**
   * Se dispara al salir del campo CJP. Decide si el QF ya existe (se asocia) o hay que
   * darlo de alta. Un fallo de red NO habilita el alta: un timeout no puede terminar
   * creando un QF duplicado para un CJP que sí existía.
   */
  onCjpBlur(): void {
    const cjp = (this.registerForm.get('managerCJP')?.value ?? '').toString().trim();

    if (!cjp) {
      this.lastLookedUpCjp = null;
      this.applyQfState('idle');
      return;
    }
    if (cjp === this.lastLookedUpCjp) {
      return;   // ya se buscó este mismo CJP, no repetir la consulta
    }
    this.lastLookedUpCjp = cjp;
    this.applyQfState('searching');

    this.pharmacyService.lookupPharmaceuticalDirector(cjp).subscribe({
      next: (qf) => {
        this.qfFound = qf;
        this.applyQfState('found');
      },
      error: (err) => {
        if (err?.status === 404) {
          this.applyQfState('new');
        } else {
          this.qfMessage = err?.message || 'No se pudo verificar el CJP.';
          this.applyQfState('blocked');
        }
      }
    });
  }

  /**
   * Ajusta validadores y habilitación según el estado.
   *
   * Ojo con el detalle que hace o rompe esto: en `found` los datos del QF NO se piden, así que
   * sus `Validators.required` tienen que salir. Si quedaran puestos, `managerDocumentNumber`
   * estaría vacío —el lookup público no devuelve el documento, a propósito— y el formulario
   * nunca sería válido: el botón de guardar quedaría muerto sin explicación visible.
   */
  private applyQfState(state: 'idle' | 'searching' | 'found' | 'new' | 'blocked'): void {
    this.qfState = state;
    if (state !== 'found') { this.qfFound = null; }
    if (state !== 'blocked') { this.qfMessage = ''; }

    const datos = ['managerName', 'managerLastname', 'managerDocumentNumber', 'managerDocumentType'];
    const pass = this.registerForm.get('managerPassword');

    if (state === 'found') {
      // El QF ya existe: sus datos salen de la entidad y este formulario no los toca.
      this.registerForm.patchValue({
        managerName: this.qfFound?.name ?? '',
        managerLastname: this.qfFound?.lastname ?? ''
      });
      datos.forEach(c => {
        const ctrl = this.registerForm.get(c);
        ctrl?.clearValidators();
        ctrl?.updateValueAndValidity();
      });
      pass?.reset('');
      pass?.clearValidators();
    } else {
      // `new`, `idle`, `searching` y `blocked`: los datos del QF se piden como siempre.
      datos.forEach(c => {
        const ctrl = this.registerForm.get(c);
        ctrl?.setValidators([Validators.required]);
        ctrl?.updateValueAndValidity();
      });
      if (state === 'new') {
        pass?.setValidators([Validators.required, Validators.minLength(6)]);
      } else {
        pass?.reset('');
        pass?.clearValidators();
      }
    }
    pass?.updateValueAndValidity();
  }

  /** No se puede enviar mientras el CJP esté en revisión o la consulta en vuelo. */
  get qfBlocksSubmit(): boolean {
    return this.qfState === 'blocked' || this.qfState === 'searching';
  }
```

Agregar el import de `Validators` si no está (ya está: viene de `@angular/forms`).

- [ ] **Step 5: Ajustar `onSubmit`**

Al principio del método, después del `if (this.registerForm.valid) {`:

```typescript
      if (this.qfBlocksSubmit) {
        this.messageRegister = this.qfMessage || 'Verificá el CJP del Director Técnico.';
        this.showDialog();
        return;
      }
```

Cambiar `const formValue = this.registerForm.value;` por **`getRawValue()`**: los campos deshabilitados en estado `found` no salen en `.value` y el payload quedaría sin `managerName`.

```typescript
      const formValue = this.registerForm.getRawValue();
```

Y donde se arma `newPharmacy`, reemplazar todas las lecturas `this.registerForm.value.X` por `formValue.X` (hoy mezcla las dos formas), y agregar el campo nuevo después de `managerDocument`:

```typescript
          // Solo cuando el QF es nuevo. Si ya existe, mandar una clave que nadie va a usar
          // sería filtrarla al pedo.
          managerPassword: this.qfState === 'new'
            ? this.encryptPassword(formValue.managerPassword, dynamicInfo)
            : undefined,
```

**Y sacá el `debugger;`** que está en medio de `onSubmit` (línea ~113). Es un resto de depuración que frena el navegador con las devtools abiertas.

- [ ] **Step 6: El HTML**

Reemplazar el bloque "Dirección técnica" completo (líneas 162-223) por:

```html
            <hr> <!-- addresse separator -->

            <h3>Dirección técnica</h3>

            <!-- CJPPU: primero, porque de él depende todo lo demás -->
            <div class="form-group">
              <label for="managerCJP">CJPPU</label>
              <input type="text" class="form-control" id="managerCJP" formControlName="managerCJP"
                placeholder="CJP del Encargado" (blur)="onCjpBlur()">
              <div *ngIf="registerForm.get('managerCJP')?.invalid && registerForm.get('managerCJP')?.touched"
                class="text-danger">
                Este campo es requerido.
              </div>
              <div *ngIf="qfState === 'searching'" class="text-muted small mt-1">
                Verificando CJP…
              </div>
              <div *ngIf="qfState === 'found'" class="text-success small mt-1">
                {{ qfFound?.name }} {{ qfFound?.lastname }} — ya registrado en Recetalia.
                Se asocia a esta farmacia.
              </div>
              <div *ngIf="qfState === 'blocked'" class="text-danger small mt-1">
                {{ qfMessage }}
              </div>
            </div>

            <!-- Datos del QF: se piden solo cuando NO existe. Si ya existe, no se muestran:
                 alcanza con la línea verde de arriba. Mostrarlos deshabilitados y a medio
                 llenar (el lookup público no devuelve el documento) confundiría más de lo
                 que ayuda. -->
            <ng-container *ngIf="qfState !== 'found'">

            <div class="form-group">
              <label for="managerName">Nombre</label>
              <input type="text" class="form-control" id="managerName" formControlName="managerName"
                placeholder="">
              <div *ngIf="registerForm.get('managerName')?.invalid && registerForm.get('managerName')?.touched"
                class="text-danger">
                Este campo es requerido.
              </div>
            </div>

            <div class="form-group">
              <label for="managerLastname">Apellido</label>
              <input type="text" class="form-control" id="managerLastname" formControlName="managerLastname"
                placeholder="">
              <div *ngIf="registerForm.get('managerLastname')?.invalid && registerForm.get('managerLastname')?.touched"
                class="text-danger">
                Este campo es requerido.
              </div>
            </div>

            <div class="form-group mb-2">
              <label for="managerDocumentType">Documento de identidad</label>
              <select class="form-control" id="managerDocumentType" formControlName="managerDocumentType">
                  <option value="UY">Cédula UY</option>
                  <option value="AR">Cédula AR</option>
                  <option value="PASSPORT">Pasaporte</option>
                  <option value="RUT">RUT</option>
                  <option value="OTHER">Otro</option>
              </select>
              <div *ngIf="registerForm.get('managerDocumentType')?.invalid && registerForm.get('managerDocumentType')?.touched"
                  class="text-danger">
                  Tipo de documento es requerido.
              </div>
              <input type="text" class="form-control mt-2" formControlName="managerDocumentNumber"
                  placeholder="Número de documento">
              <div *ngIf="registerForm.get('managerDocumentNumber')?.invalid && registerForm.get('managerDocumentNumber')?.touched"
                  class="text-danger">
                  Ingrese su documento con digito identificador.
              </div>
              <div *ngIf="registerForm.errors?.['invalidDocument']" class="text-danger">
                  Documento inválido según las reglas de validación.
              </div>
            </div>

            </ng-container>

            <!-- Clave inicial: solo para un QF nuevo. Se la entrega la farmacia en mano. -->
            <div class="form-group" *ngIf="qfState === 'new'">
              <label for="managerPassword">Clave inicial del Químico Farmacéutico</label>
              <p-password id="managerPassword" formControlName="managerPassword" [toggleMask]="true"
                [feedback]="false" placeholder="Clave inicial"></p-password>
              <small class="form-text text-muted">
                Entregásela al Químico Farmacéutico: la va a necesitar para su primer ingreso,
                donde define su clave definitiva.
              </small>
              <div *ngIf="registerForm.get('managerPassword')?.invalid && registerForm.get('managerPassword')?.touched"
                class="text-danger">
                Mínimo 6 caracteres.
              </div>
            </div>
```

Los `[disabled]="isEditMode"` que tenían los campos de documento se sacan: ahora quien los habilita o deshabilita es `applyQfState`, y mezclar las dos formas (atributo del template y `disable()` del control) genera el warning de Angular sobre usar `disabled` con reactive forms.

**Bloquear el botón de submit** mientras el CJP esté en revisión: buscá el `<button type="submit">` del formulario y agregale `|| qfBlocksSubmit` a su `[disabled]`. Si no tiene `[disabled]`, ponele `[disabled]="qfBlocksSubmit"`.

- [ ] **Step 7: Build**

Run: `npm run build`
Expected: build exitoso, sin errores de TypeScript.

- [ ] **Step 8: Commit**

```bash
git add src/app/model src/app/services/pharmacy.service.ts src/app/pages/application/register
git commit -m "feat(qf): lookup por CJP en el registro de farmacia"
```

---

### Task 2: Gestión — modal de alta y edición de farmacia

Mismo comportamiento, pero este formulario tiene dos modos (`create` / `edit`) con validadores distintos, y en `edit` llega con el CJP ya cargado.

**Files:**
- Modify: `src/app/model/request/pharmacy-request.ts`
- Modify: `src/app/services/pharmacy.service.ts`
- Modify: `src/app/pages/application/home/pharmacy/pharmacy-update/pharmacy-update.component.ts`
- Modify: `src/app/pages/application/home/pharmacy/pharmacy-update/pharmacy-update.component.html`

- [ ] **Step 1: Modelo y servicio**

`pharmacy-request.ts` es **byte-idéntico** al de farmacias: agregale el mismo campo `managerPassword?: string` con el mismo comentario del Step 1 de la Task 1.

Crear `src/app/model/response/pharmaceutical-director-lookup-response.ts` con el mismo contenido.

En `src/app/services/pharmacy.service.ts` agregar el mismo `lookupPharmaceuticalDirector` del Step 3 de la Task 1 — **incluido el `catchError` que propaga `{status, message}`**. El resto de los métodos de este servicio tiran mensajes genéricos, pero acá el mensaje del backend es lo que se le muestra al usuario, así que este método es la excepción y conviene que el comentario lo diga.

- [ ] **Step 2: Estado y lógica en el componente**

Las mismas propiedades del Step 4 de la Task 1 (`qfState`, `qfFound`, `qfMessage`, `lastLookedUpCjp`), el mismo `onCjpBlur()`, el mismo `applyQfState()` y el mismo getter `qfBlocksSubmit`.

En `initForm()`, agregar el control después de `managerDocumentNumber`:

```typescript
      managerPassword: [''],
```

**Diferencia con Farmacias:** en modo `edit` el formulario se abre con un CJP ya cargado. Hay que resolver el estado en cuanto se cargan los datos, o los campos quedarían editables y se podría guardar información divergente de la entidad QF.

En el método que hace el `patchValue` con los datos de la farmacia (buscalo: es el que carga `pharmacyResponseCurrent`), al final, después del patch:

```typescript
    // En edición el CJP ya viene cargado: resolver el estado del QF de entrada, para que los
    // campos no queden editables mostrando datos que no son los de la entidad.
    this.onCjpBlur();
```

- [ ] **Step 3: Ajustar `onSubmit`**

Después del `if (!this.registerForm.valid) { ... return; }`:

```typescript
    if (this.qfBlocksSubmit) {
      this.messageRegister = this.qfMessage || 'Verificá el CJP del Director Técnico.';
      this.showDialog();
      return;
    }
```

Este método **ya usa `getRawValue()`**, así que los campos deshabilitados salen igual: no hay que cambiar eso.

En el objeto `newPharmacy`, después de `managerDocument`:

```typescript
      // Solo cuando el QF es nuevo. Si ya existe, mandar una clave que nadie va a usar
      // sería filtrarla al pedo.
      managerPassword: this.qfState === 'new'
        ? this.encryptPassword(formValue.managerPassword, dynamicInfo)
        : undefined,
```

⚠️ **Ojo con una diferencia importante respecto de Farmacias:** acá `password` se cifra solo en modo `create` (`isCreate ? this.encryptPassword(...) : ''`), pero `managerPassword` se cifra **en los dos modos**, porque en edición Gestión también puede declarar un D.T. nuevo. El `dynamicInfo` es el mismo para los dos campos y ya se manda siempre en `info`.

- [ ] **Step 4: El HTML**

Reemplazar el bloque "Dirección Técnica" (líneas 189-250) por el mismo del Step 6 de la Task 1, con dos diferencias:

1. El `<h3>` dice `Dirección Técnica` (con T mayúscula), respetá el original.
2. Esta app no usa `p-password` en este formulario sino un input con botón de ojo. Para no introducir un componente nuevo, el campo de clave inicial va como input plano, siguiendo el patrón que ya usa el password de este modal:

```html
            <!-- Clave inicial: solo para un QF nuevo. Se la entrega la farmacia en mano. -->
            <div class="form-group" *ngIf="qfState === 'new'">
              <label for="managerPassword">Clave inicial del Químico Farmacéutico</label>
              <div class="pw-wrap">
                <input [type]="reveal.managerPassword ? 'text' : 'password'" class="form-control"
                  id="managerPassword" formControlName="managerPassword" placeholder="Clave inicial"
                  autocomplete="new-password">
                <button type="button" class="pw-toggle" tabindex="-1"
                  (click)="reveal.managerPassword = !reveal.managerPassword"
                  [attr.aria-label]="reveal.managerPassword ? 'Ocultar contraseña' : 'Mostrar contraseña'">
                  <i class="fas" [ngClass]="reveal.managerPassword ? 'fa-eye-slash' : 'fa-eye'"></i>
                </button>
              </div>
              <small class="form-text text-muted">
                Entregásela al Químico Farmacéutico: la va a necesitar para su primer ingreso,
                donde define su clave definitiva.
              </small>
              <div *ngIf="registerForm.get('managerPassword')?.invalid && registerForm.get('managerPassword')?.touched"
                class="text-danger">
                Mínimo 6 caracteres.
              </div>
            </div>
```

Y ampliar la propiedad `reveal` del componente:

```typescript
  reveal = { password: false, passwordConfirm: false, managerPassword: false };
```

Bloquear el botón Guardar del modal con `|| qfBlocksSubmit` en su `[disabled]`.

- [ ] **Step 5: Build**

Run: `npm run build`
Expected: build exitoso.

- [ ] **Step 6: Commit**

```bash
git add src/app/model src/app/services/pharmacy.service.ts \
        src/app/pages/application/home/pharmacy/pharmacy-update
git commit -m "feat(qf): lookup por CJP en el alta y edicion de farmacia desde Gestion"
```

---

### Task 3: Validación manual contra DEV

**Files:** ninguno — es verificación.

- [ ] **Step 1: Deployar las dos apps al .98**

```bash
cd /Users/pablo/iwtg/recetalia-workspace
rsync -az --delete --exclude .git --exclude node_modules --exclude dist --exclude .angular \
  farmacias-recetalia-app/ root@138.197.150.98:/opt/recetalia/farmacias-recetalia-app/
rsync -az --delete --exclude .git --exclude node_modules --exclude dist --exclude .angular \
  gestion-recetadigital-app/ root@138.197.150.98:/opt/recetalia/gestion-recetadigital-app/
ssh root@138.197.150.98 "cd /opt/recetalia/deploy-recetalia && \
  docker compose build farmacias-recetalia-app && \
  docker compose build gestion-recetadigital-app && \
  docker compose up -d --no-deps farmacias-recetalia-app gestion-recetadigital-app"
```

⚠️ Dos landmines conocidas: **buildear los frontends en serie**, nunca en paralelo (agotan los 8 GB del server y tiran el SSH); y **nunca `docker compose up -d` a secas**, que recrea nginx y rompe PRE.

- [ ] **Step 2: Los tres casos del lookup, por API**

```bash
base=https://apipre.recetalia.com/recetalia-api-rest/api/pharmacies/pharmaceutical-director-lookup
for cjp in 999999 000000 1; do
  printf "%-8s " "$cjp"; curl -s -w " [%{http_code}]\n" "$base/$cjp"
done
```

Esperado: `999999` → 200 con nombre; `000000` → 404; `1` → 400 con el mensaje de revisión.

- [ ] **Step 3: El registro de Farmacias, en el browser**

Abrí `https://farmaciaspre.recetalia.com/register` y verificá los tres estados tipeando en el campo CJPPU y saliendo del campo:

| CJP | Qué tiene que pasar |
|---|---|
| `999999` | Aparece el nombre en verde, los campos de nombre/apellido/documento quedan deshabilitados y con los datos del QF, y **no** aparece el campo de clave inicial |
| `000000` | Los campos quedan editables y **aparece** el campo de clave inicial, obligatorio |
| `1` | Mensaje rojo de "en revisión" y el botón de registro **deshabilitado** |

Verificá también que al borrar el CJP el formulario vuelva al estado inicial.

- [ ] **Step 4: El modal de Gestión**

Entrá a `https://gestionpre.recetalia.com` con `gestion@recetalia.com` / `1wtg_p4ss`, andá a Farmacias y:

1. **Editá una farmacia cuyo CJP sea uno de los 20 en revisión** (sacá uno de `qf-cjps-a-curar.csv`). Al abrir el modal, el estado tiene que resolverse solo y mostrar el aviso de revisión con el Guardar bloqueado.
2. **Editá una farmacia con un CJP sano** (por ejemplo el `999999`): tiene que mostrar el nombre en verde y los campos deshabilitados.
3. **Cambiá el CJP de una farmacia en revisión a uno libre** y guardá. Tiene que pedirte la clave inicial. Después verificá en la DB que el QF viejo se recalculó:

```bash
ssh root@138.197.150.98 "docker exec recetalia-mysql mysql -uroot -pRootDev98_p3Wn8sLzQ -N -e \"
  SELECT cjp, status FROM recetali_receta.pharmaceutical_director WHERE status='NEEDS_REVIEW';\""
```

**Dejá los datos como estaban** y confirmá el estado restaurado.

- [ ] **Step 5: Regresión**

Los 5 frontends de PRE en 200, ningún contenedor caído salvo `observatorio-cpa`, y el alta de farmacia sin CJP en revisión sigue funcionando de punta a punta.

- [ ] **Step 6: Anotar el resultado**

Registrar lo verificado en `WORK-STATUS.md` de la raíz del workspace. No hay commit: la raíz no es un repo git.

---

## Lo que queda después de este plan

- **Plan 2c** — la bandeja de curación en Gestión, consumiendo `GET /api/pharmaceutical-directors/needs-review` (el endpoint ya existe y está validado). Con eso se puede curar los 20 CJPs.
- **Plan 3** — la app del QF: pantalla de registro (`/registro`) que reemplaza a `/change-password`, más el Nº de talonario en el listado.
- **Plan 4** — Mantenimiento de Libro Negro en Farmacias, y endurecer por rol el Excel de controlados.

**Una limitación conocida que hay que resolver en el 2c:** Gestión no puede completar el `document` de un QF que lo tenga vacío. Antes escribía en la copia de la farmacia, lo que generaba divergencia en vez de arreglarla; ahora ese camino está cerrado y el único que puede cargarlo es el propio QF al registrarse. Si la curación necesita completarlo —y para varios de los 20 probablemente sí—, la bandeja tiene que poder editar la entidad QF, no la farmacia.
