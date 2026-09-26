# Prestador: cuenta de login desde Gestión — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que Gestión cree la cuenta de login del prestador (creación dual entidad + usuario en security-api) y pueda resetear su contraseña; esa única cuenta sirve para consulta (app) y para la API que recibe recetas.

**Architecture:** Backend hexagonal en `recetalia-api-rest`: `MedicalProviderServiceImpl.createMedicalProvider` se extiende para llamar al puerto existente `SecurityApiRecetaliaPort.registerUser` (con rollback), igual que `PharmacyServiceImpl`. Se agrega reset password vía `renewPassword`. Frontend: nueva sección "Prestadores" en `gestion-recetadigital-app`, espejando la sección `franchise` (PrimeNG `DynamicDialog`), con cifrado AES del password como `medic-add`.

**Tech Stack:** Java 21 / Spring Boot 3.3 / Gradle · Angular 18.2 / PrimeNG 17 / crypto-js.

**Diseño de referencia:** `doc/plans/2026-06-01-prestador-user-dual-creation-design.md`

---

## Mapa de archivos

### Backend — recetalia-api-rest
- Modify `dto/request/MedicalProviderRequest.java` — agregar campo `info`.
- Modify `service/MedicalProviderService.java` — agregar `resetPassword(...)` a la interface.
- Modify `service/impl/MedicalProviderServiceImpl.java` — inyectar `SecurityApiRecetaliaPort`; creación dual en `createMedicalProvider`; implementar `resetPassword`.
- Modify `controller/MedicalProviderController.java` — endpoint `POST /api/medical-providers/{id}/reset-password`.
- Create `dto/request/ResetPasswordRequest.java` — `{ password, info }`.
- Test `src/test/java/com/recetalia/api/application/service/impl/MedicalProviderServiceImplTest.java`.

### Frontend — gestion-recetadigital-app
- Modify `model/request/medical-provider-request.ts` — agregar `info`.
- Modify `services/medical-provider.service.ts` — agregar `resetPassword(id, payload)`.
- Create `shared/password-crypto.ts` — util AES (centraliza lo que hoy se duplica).
- Create `pages/application/home/medical-provider/medical-provider-list/medical-provider-list.component.{ts,html}`.
- Create `pages/application/home/medical-provider/medical-provider-update/medical-provider-update.component.{ts,html}`.
- Modify `pages/application/home/home.module.ts` — declarar los 2 componentes.
- Modify `pages/application/home/home-routing.module.ts` — ruta `medical-providers`.
- Modify `pages/application/home/components/sidebar/sidebar.component.html` — ítem "Prestadores".

### Comandos
- Backend: `cd recetalia-api-rest && ./gradlew test --tests MedicalProviderServiceImplTest` · `./gradlew build`
- Frontend: `cd gestion-recetadigital-app && npx ng build`

---

## FASE 1 — Backend (recetalia-api-rest)

### Task 1: Campo `info` en MedicalProviderRequest

**Files:** Modify `src/main/java/com/recetalia/api/application/dto/request/MedicalProviderRequest.java`

- [ ] **Step 1:** Agregar el campo `info` (string del cifrado AES, igual que `PharmacyRequest`). Justo después del campo `password` agregar:
```java
  private String info;
```
Si la clase usa Lombok (`@Data`/`@Getter`), el getter `getInfo()` se genera solo. Si NO usa Lombok, agregar también:
```java
  public String getInfo() { return info; }
  public void setInfo(String info) { this.info = info; }
```
(Verificar las anotaciones de clase arriba del archivo y seguir ese estilo.)

- [ ] **Step 2: Compilar** — Run: `./gradlew compileJava` · Expected: BUILD SUCCESSFUL.
- [ ] **Step 3: Commit**
```bash
git add src/main/java/com/recetalia/api/application/dto/request/MedicalProviderRequest.java
git commit -m "feat(prestador): campo info en MedicalProviderRequest (cifrado AES)"
```

---

### Task 2: ResetPasswordRequest DTO

**Files:** Create `src/main/java/com/recetalia/api/application/dto/request/ResetPasswordRequest.java`

- [ ] **Step 1:** Crear el DTO (mismo estilo Lombok que el resto de `dto/request`):
```java
package com.recetalia.api.application.dto.request;

import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class ResetPasswordRequest {
    private String password; // cifrado AES desde el front
    private String info;      // dynamicInfo del cifrado
}
```
> Si los DTOs del proyecto NO usan Lombok, reemplazar las anotaciones por getters/setters explícitos.

- [ ] **Step 2: Compilar** — Run: `./gradlew compileJava` · Expected: BUILD SUCCESSFUL.
- [ ] **Step 3: Commit**
```bash
git add src/main/java/com/recetalia/api/application/dto/request/ResetPasswordRequest.java
git commit -m "feat(prestador): ResetPasswordRequest DTO"
```

---

### Task 3: Interface — método resetPassword

**Files:** Modify `src/main/java/com/recetalia/api/application/service/MedicalProviderService.java`

- [ ] **Step 1:** Agregar a la interface (junto a los métodos existentes):
```java
    void resetPassword(String id, String encryptedPassword, String info) throws com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;
```
- [ ] **Step 2: Compilar** — Run: `./gradlew compileJava` · Expected: FAIL (impl no implementa el método todavía) — eso es esperado; se resuelve en Task 4. Si preferís que compile, hacé Task 4 a continuación antes de correr el build.
- [ ] **Step 3:** (sin commit aislado; se commitea junto con Task 4)

---

### Task 4: MedicalProviderServiceImpl — creación dual + resetPassword (TDD)

**Files:**
- Modify `src/main/java/com/recetalia/api/application/service/impl/MedicalProviderServiceImpl.java`
- Test `src/test/java/com/recetalia/api/application/service/impl/MedicalProviderServiceImplTest.java`

Patrón a espejar (`PharmacyServiceImpl.create`, ya en el repo):
```java
pharmacy = pharmacyRepository.save(pharmacy);
try {
  securityApiRecetaliaPort.registerUser(new UserRequestSecurityApiRecetalia(
      request.getName(), request.getEmail(), request.getPassword(), "ROLE_PHARMACY", "farmacias-recetalia-app", request.getInfo()));
} catch (RuntimeException e) {
  pharmacyRepository.delete(pharmacy);
  throw new RuntimeException("Error registering pharmacy in security API: " + e.getMessage());
}
```

- [ ] **Step 1: Escribir el test que falla**
```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.MedicalProvider;
import com.recetalia.api.application.domain.repository.MedicalProviderRepository;
import com.recetalia.api.application.dto.mapper.request.MedicalProviderRequestMapper;
import com.recetalia.api.application.dto.mapper.response.MedicalProviderResponseMapper;
import com.recetalia.api.application.dto.request.MedicalProviderRequest;
import com.recetalia.api.application.dto.response.MedicalProviderResponse;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.SecurityApiRecetaliaPort;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.dto.UserRequestSecurityApiRecetalia;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.*;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class MedicalProviderServiceImplTest {

    @Mock MedicalProviderRepository repo;
    @Mock MedicalProviderRequestMapper requestMapper;
    @Mock MedicalProviderResponseMapper responseMapper;
    @Mock SecurityApiRecetaliaPort securityPort;
    @InjectMocks MedicalProviderServiceImpl service;

    private MedicalProviderRequest req() {
        MedicalProviderRequest r = new MedicalProviderRequest();
        r.setName("MEDICARE TEST");
        r.setEmail("test-prestador@recetalia.com");
        r.setPassword("ENC_PASS");
        r.setInfo("abc1234567");
        return r;
    }

    @Test
    void createRegistersUserInSecurityApi() {
        MedicalProvider saved = new MedicalProvider();
        when(requestMapper.toEntity(any())).thenReturn(saved);
        when(repo.save(saved)).thenReturn(saved);
        when(responseMapper.toDto(saved)).thenReturn(new MedicalProviderResponse());

        service.createMedicalProvider(req());

        ArgumentCaptor<UserRequestSecurityApiRecetalia> cap = ArgumentCaptor.forClass(UserRequestSecurityApiRecetalia.class);
        verify(securityPort).registerUser(cap.capture());
        assertThat(cap.getValue().getEmail()).isEqualTo("test-prestador@recetalia.com");
        assertThat(cap.getValue().getRole()).isEqualTo("ROLE_MEDICAL_PROVIDER");
        verify(repo, never()).delete(any());
    }

    @Test
    void createRollsBackWhenSecurityFails() {
        MedicalProvider saved = new MedicalProvider();
        when(requestMapper.toEntity(any())).thenReturn(saved);
        when(repo.save(saved)).thenReturn(saved);
        when(securityPort.registerUser(any())).thenThrow(new RuntimeException("email exists"));

        assertThatThrownBy(() -> service.createMedicalProvider(req()))
                .isInstanceOf(RuntimeException.class);
        verify(repo).delete(saved);
    }

    @Test
    void resetPasswordCallsRenew() throws Exception {
        MedicalProvider mp = new MedicalProvider();
        mp.setName("MEDICARE");
        mp.setEmail("test-prestador@recetalia.com");
        when(repo.findById("p1")).thenReturn(java.util.Optional.of(mp));

        service.resetPassword("p1", "ENC_NEW", "info123456");

        ArgumentCaptor<UserRequestSecurityApiRecetalia> cap = ArgumentCaptor.forClass(UserRequestSecurityApiRecetalia.class);
        verify(securityPort).renewPassword(cap.capture());
        assertThat(cap.getValue().getEmail()).isEqualTo("test-prestador@recetalia.com");
        assertThat(cap.getValue().getPassword()).isEqualTo("ENC_NEW");
        assertThat(cap.getValue().getInfo()).isEqualTo("info123456");
    }
}
```

- [ ] **Step 2: Correr — debe fallar** — Run: `./gradlew test --tests MedicalProviderServiceImplTest` · Expected: FAIL (compila contra una impl que aún no inyecta el puerto ni implementa resetPassword).

- [ ] **Step 3: Editar `MedicalProviderServiceImpl`**

3a. Agregar import e inyección del puerto (junto a los `@Autowired` existentes):
```java
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.SecurityApiRecetaliaPort;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.dto.UserRequestSecurityApiRecetalia;
```
```java
  @Autowired
  private SecurityApiRecetaliaPort securityApiRecetaliaPort;
```

3b. Reemplazar el cuerpo de `createMedicalProvider` por:
```java
  @Override
  public MedicalProviderResponse createMedicalProvider(MedicalProviderRequest request) {
    MedicalProvider medicalProvider = requestMapper.toEntity(request);
    medicalProvider = medicalProviderRepository.save(medicalProvider);
    try {
      securityApiRecetaliaPort.registerUser(new UserRequestSecurityApiRecetalia(
          request.getName(), request.getEmail(), request.getPassword(),
          "ROLE_MEDICAL_PROVIDER", "security-api-recetalia", request.getInfo()));
    } catch (RuntimeException e) {
      medicalProviderRepository.delete(medicalProvider);
      throw new RuntimeException("Error registering medical provider in security API: " + e.getMessage());
    }
    return responseMapper.toDto(medicalProvider);
  }
```

3c. Agregar el método `resetPassword`:
```java
  @Override
  public void resetPassword(String id, String encryptedPassword, String info) throws ResourceNotFoundException {
    MedicalProvider mp = medicalProviderRepository.findById(id)
        .orElseThrow(() -> new ResourceNotFoundException("MedicalProvider not found for this id :: " + id));
    securityApiRecetaliaPort.renewPassword(new UserRequestSecurityApiRecetalia(
        mp.getName(), mp.getEmail(), encryptedPassword,
        "ROLE_MEDICAL_PROVIDER", "security-api-recetalia", info));
  }
```
> Verificar el orden de parámetros del constructor `UserRequestSecurityApiRecetalia(username, email, password, role, applicationApiKey, info)` (es el que usa `PharmacyServiceImpl`).

- [ ] **Step 4: Correr — debe pasar** — Run: `./gradlew test --tests MedicalProviderServiceImplTest` · Expected: PASS (3 tests).

- [ ] **Step 5: Commit**
```bash
git add src/main/java/com/recetalia/api/application/service/MedicalProviderService.java \
        src/main/java/com/recetalia/api/application/service/impl/MedicalProviderServiceImpl.java \
        src/test/java/com/recetalia/api/application/service/impl/MedicalProviderServiceImplTest.java
git commit -m "feat(prestador): creación dual + resetPassword en MedicalProviderServiceImpl (TDD)"
```

---

### Task 5: Endpoint reset-password en el controller

**Files:** Modify `src/main/java/com/recetalia/api/application/controller/MedicalProviderController.java`

- [ ] **Step 1:** Agregar el endpoint (mismo estilo `GenericResponse`/`ResponseEntity` que los demás métodos del controller). Imports necesarios: `ResetPasswordRequest`, `ResponseStatus`, `GenericResponse`.
```java
  @PostMapping("/{id}/reset-password")
  public ResponseEntity<GenericResponse<Void>> resetPassword(
      @PathVariable String id,
      @RequestBody com.recetalia.api.application.dto.request.ResetPasswordRequest request) throws ResourceNotFoundException {
    medicalProviderService.resetPassword(id, request.getPassword(), request.getInfo());
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, null));
  }
```
> Usar el nombre real del bean de servicio inyectado en el controller (revisar el campo: suele ser `medicalProviderService`). Reusar los imports de `GenericResponse`/`ResponseStatus` ya presentes en el archivo.

- [ ] **Step 2: Build completo** — Run: `./gradlew build` · Expected: BUILD SUCCESSFUL (context load incluido).
- [ ] **Step 3: Commit**
```bash
git add src/main/java/com/recetalia/api/application/controller/MedicalProviderController.java
git commit -m "feat(prestador): endpoint POST /api/medical-providers/{id}/reset-password"
```

---

## FASE 2 — Frontend (gestion-recetadigital-app)

### Task 6: Util de cifrado + modelo + service

**Files:**
- Create `src/app/shared/password-crypto.ts`
- Modify `src/app/model/request/medical-provider-request.ts`
- Modify `src/app/services/medical-provider.service.ts`

- [ ] **Step 1: Crear util AES** (centraliza el cifrado que hoy se duplica en `medic-add`/`pharmacy`):
```typescript
import * as CryptoJS from 'crypto-js';

export function generateDynamicInfo(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  }).slice(0, 10);
}

function padOrTruncateKey(key: string): string {
  const maxLength = 32;
  return key.length > maxLength ? key.slice(0, maxLength) : key.padEnd(maxLength, '0');
}

export function encryptPassword(password: string, dynamicInfo: string): string {
  const finalKey = padOrTruncateKey('ahjsdfhjbqer56243' + dynamicInfo);
  return CryptoJS.AES.encrypt(password, CryptoJS.enc.Utf8.parse(finalKey), {
    mode: CryptoJS.mode.ECB,
    padding: CryptoJS.pad.Pkcs7,
  }).toString();
}
```
> `crypto-js` ya es dependencia del proyecto (lo usan `medic-add`/`pharmacy`).

- [ ] **Step 2: Agregar `info` al request** en `medical-provider-request.ts`:
```typescript
    info?: string;
```
(dentro de la interface `MedicalProviderRequest`, junto a `password`).

- [ ] **Step 3: Agregar `resetPassword` al service** `medical-provider.service.ts` (mismo patrón map/catchError):
```typescript
  resetPassword(id: string, payload: { password: string; info: string }): Observable<void> {
    return this.http.post<ApiResponse<void>>(`${this.apiUrl}/${id}/reset-password`, payload).pipe(
      map((response: ApiResponse<void>) => {
        if (response.status === 'SUCCESS') { return; }
        throw new Error('Error response from the API');
      }),
      catchError(error => {
        console.error('API request failed:', error);
        return throwError(() => new Error('Failed to reset password'));
      })
    );
  }
```

- [ ] **Step 4: Commit**
```bash
git add src/app/shared/password-crypto.ts src/app/model/request/medical-provider-request.ts src/app/services/medical-provider.service.ts
git commit -m "feat(prestador): util AES + info + resetPassword en el service"
```

---

### Task 7: MedicalProviderListComponent (espeja franchise-list)

**Files:**
- Create `src/app/pages/application/home/medical-provider/medical-provider-list/medical-provider-list.component.ts`
- Create `src/app/pages/application/home/medical-provider/medical-provider-list/medical-provider-list.component.html`

- [ ] **Step 1: Componente** (`standalone: false`; abre el form de alta/edición vía `DialogService`; botón de reset password abre el mismo form en modo `reset`):
```typescript
import { Component, OnInit, NgZone } from '@angular/core';
import { DialogService } from 'primeng/dynamicdialog';
import { MedicalProviderResponse } from '../../../../../model/response/medical-provider-response';
import { MedicalProviderService } from '../../../../../services/medical-provider.service';
import { MedicalProviderUpdateComponent } from '../medical-provider-update/medical-provider-update.component';

@Component({
  selector: 'app-medical-provider-list',
  standalone: false,
  templateUrl: './medical-provider-list.component.html',
  styleUrls: [],
})
export class MedicalProviderListComponent implements OnInit {
  providers: MedicalProviderResponse[] = [];
  loading = false;

  constructor(
    private service: MedicalProviderService,
    private zone: NgZone,
    private dialogService: DialogService,
  ) {}

  ngOnInit(): void { this.load(); }

  load(): void {
    this.loading = true;
    this.service.getAll().subscribe({
      next: data => this.zone.run(() => { this.providers = data; this.loading = false; }),
      error: () => { this.loading = false; },
    });
  }

  openCreate(): void {
    const ref = this.dialogService.open(MedicalProviderUpdateComponent, {
      header: 'Crear prestador', style: { width: '640px', maxWidth: '92vw' },
      contentStyle: { 'max-height': '82vh', overflow: 'auto' }, dismissableMask: true,
      data: { mode: 'create' },
    });
    ref.onClose.subscribe(r => { if (r) this.load(); });
  }

  openEdit(p: MedicalProviderResponse): void {
    const ref = this.dialogService.open(MedicalProviderUpdateComponent, {
      header: `Editar prestador - ${p.name}`, style: { width: '640px', maxWidth: '92vw' },
      contentStyle: { 'max-height': '82vh', overflow: 'auto' }, dismissableMask: true,
      data: { id: p.id, mode: 'edit' },
    });
    ref.onClose.subscribe(r => { if (r) this.load(); });
  }

  openResetPassword(p: MedicalProviderResponse): void {
    this.dialogService.open(MedicalProviderUpdateComponent, {
      header: `Resetear contraseña - ${p.name}`, style: { width: '480px', maxWidth: '92vw' },
      dismissableMask: true, data: { id: p.id, mode: 'reset' },
    });
  }
}
```

- [ ] **Step 2: Template**:
```html
<div class="content-table mt-3">
  <h2>Prestadores</h2>
  <div class="d-flex justify-content-end mb-2">
    <button class="btn btn-success" (click)="openCreate()">Crear prestador</button>
  </div>
  <p-table [value]="providers" [loading]="loading" class="custom-table">
    <ng-template pTemplate="header">
      <tr><th>Nombre</th><th>Email</th><th>RUT</th><th>Estado</th><th style="width:160px">Acciones</th></tr>
    </ng-template>
    <ng-template pTemplate="body" let-p>
      <tr>
        <td>{{ p.name }}</td>
        <td>{{ p.email }}</td>
        <td>{{ p.rut }}</td>
        <td>{{ p.status }}</td>
        <td>
          <button type="button" pButton icon="pi pi-pencil" class="p-button-rounded p-button-warning p-button-text"
            (click)="openEdit(p)" pTooltip="Editar"></button>
          <button type="button" pButton icon="pi pi-key" class="p-button-rounded p-button-help p-button-text"
            (click)="openResetPassword(p)" pTooltip="Resetear contraseña"></button>
        </td>
      </tr>
    </ng-template>
  </p-table>
</div>
```

- [ ] **Step 3: Commit** (compila al declararlo en Task 9)
```bash
git add src/app/pages/application/home/medical-provider/medical-provider-list
git commit -m "feat(prestador): MedicalProviderListComponent"
```

---

### Task 8: MedicalProviderUpdateComponent (alta/edición/reset)

**Files:**
- Create `src/app/pages/application/home/medical-provider/medical-provider-update/medical-provider-update.component.ts`
- Create `src/app/pages/application/home/medical-provider/medical-provider-update/medical-provider-update.component.html`

- [ ] **Step 1: Componente** (3 modos: `create` | `edit` | `reset`; cifra el password con el util AES):
```typescript
import { Component, OnInit } from '@angular/core';
import { FormBuilder, FormGroup, Validators } from '@angular/forms';
import { DynamicDialogRef, DynamicDialogConfig } from 'primeng/dynamicdialog';
import { MedicalProviderService } from '../../../../../services/medical-provider.service';
import { MedicalProviderRequest } from '../../../../../model/request/medical-provider-request';
import { generateDynamicInfo, encryptPassword } from '../../../../../shared/password-crypto';

@Component({
  selector: 'app-medical-provider-update',
  standalone: false,
  templateUrl: './medical-provider-update.component.html',
  styleUrls: [],
})
export class MedicalProviderUpdateComponent implements OnInit {
  form!: FormGroup;
  mode: 'create' | 'edit' | 'reset' = 'create';
  loading = false;

  constructor(
    private fb: FormBuilder,
    private service: MedicalProviderService,
    public ref: DynamicDialogRef,
    public config: DynamicDialogConfig,
  ) {}

  ngOnInit(): void {
    this.mode = this.config?.data?.mode ?? 'create';
    if (this.mode === 'reset') {
      this.form = this.fb.group({ password: ['', [Validators.required, Validators.minLength(4)]] });
      return;
    }
    this.form = this.fb.group({
      medicalProviderTypeId: ['', Validators.required],
      name: ['', Validators.required],
      email: ['', [Validators.required, Validators.email]],
      password: ['', this.mode === 'create' ? [Validators.required, Validators.minLength(4)] : []],
      businessName: [''],
      rut: [''],
      phone: [''],
      status: ['ACTIVE', Validators.required],
    });
    if (this.mode === 'edit') { this.loadProvider(this.config.data.id); }
  }

  private loadProvider(id: string): void {
    this.loading = true;
    this.service.getById(id).subscribe({
      next: p => {
        this.form.patchValue({
          medicalProviderTypeId: p.medicalProviderTypeId, name: p.name, email: p.email,
          businessName: p.businessName, rut: p.rut, phone: p.phone, status: p.status,
        });
        this.loading = false;
      },
      error: () => { this.loading = false; },
    });
  }

  submit(): void {
    if (this.form.invalid) { this.form.markAllAsTouched(); return; }
    this.loading = true;

    if (this.mode === 'reset') {
      const info = generateDynamicInfo();
      const enc = encryptPassword(this.form.value.password, info);
      this.service.resetPassword(this.config.data.id, { password: enc, info }).subscribe({
        next: () => { this.loading = false; this.ref.close(true); },
        error: () => { this.loading = false; },
      });
      return;
    }

    const v = this.form.value;
    const payload: MedicalProviderRequest = {
      medicalProviderTypeId: v.medicalProviderTypeId, name: v.name?.trim(), email: v.email?.trim(),
      businessName: v.businessName, rut: v.rut, phone: v.phone, status: v.status, password: '',
    };
    if (this.mode === 'create') {
      const info = generateDynamicInfo();
      payload.password = encryptPassword(v.password, info);
      payload.info = info;
    }
    const req$ = this.mode === 'create'
      ? this.service.create(payload)
      : this.service.update(this.config.data.id, payload);
    req$.subscribe({
      next: () => { this.loading = false; this.ref.close(true); },
      error: () => { this.loading = false; },
    });
  }

  close(): void { this.ref.close(); }
}
```

- [ ] **Step 2: Template**:
```html
<form [formGroup]="form" (ngSubmit)="submit()" class="p-fluid">
  <ng-container *ngIf="mode !== 'reset'">
    <div class="field"><label>Tipo (ID)</label><input pInputText formControlName="medicalProviderTypeId"></div>
    <div class="field"><label>Nombre</label><input pInputText formControlName="name"></div>
    <div class="field"><label>Email</label><input pInputText type="email" formControlName="email"></div>
    <div class="field" *ngIf="mode==='create'"><label>Contraseña</label><input pInputText type="password" formControlName="password"></div>
    <div class="field"><label>Razón social</label><input pInputText formControlName="businessName"></div>
    <div class="field"><label>RUT</label><input pInputText formControlName="rut"></div>
    <div class="field"><label>Teléfono</label><input pInputText formControlName="phone"></div>
    <div class="field"><label>Estado</label>
      <select class="form-select" formControlName="status"><option value="ACTIVE">ACTIVE</option><option value="INACTIVE">INACTIVE</option></select>
    </div>
  </ng-container>
  <div class="field" *ngIf="mode==='reset'"><label>Nueva contraseña</label><input pInputText type="password" formControlName="password"></div>

  <div class="d-flex justify-content-end gap-2 mt-3">
    <button type="button" class="btn btn-secondary" (click)="close()">Cancelar</button>
    <button type="submit" class="btn btn-success" [disabled]="loading">{{ mode==='reset' ? 'Resetear' : 'Guardar' }}</button>
  </div>
</form>
```

- [ ] **Step 3: Commit** (compila al declararlo en Task 9)
```bash
git add src/app/pages/application/home/medical-provider/medical-provider-update
git commit -m "feat(prestador): MedicalProviderUpdateComponent (alta/edición/reset)"
```

---

### Task 9: Wiring — módulo + ruta + menú

**Files:**
- Modify `src/app/pages/application/home/home.module.ts`
- Modify `src/app/pages/application/home/home-routing.module.ts`
- Modify `src/app/pages/application/home/components/sidebar/sidebar.component.html`

- [ ] **Step 1: home.module.ts** — agregar imports y declarar los 2 componentes:
```typescript
import { MedicalProviderListComponent } from './medical-provider/medical-provider-list/medical-provider-list.component';
import { MedicalProviderUpdateComponent } from './medical-provider/medical-provider-update/medical-provider-update.component';
```
Agregar `MedicalProviderListComponent, MedicalProviderUpdateComponent` al array `declarations`. (PrimeNG `DynamicDialogModule`, `TableModule` ya están importados; `DialogService` ya está en `providers`.)

- [ ] **Step 2: home-routing.module.ts** — import + ruta hija:
```typescript
import { MedicalProviderListComponent } from "./medical-provider/medical-provider-list/medical-provider-list.component";
```
Agregar dentro de `children`:
```typescript
      { path: "medical-providers", component: MedicalProviderListComponent },
```

- [ ] **Step 3: sidebar.component.html** — agregar el ítem (p.ej. después de "Medicamentos DNMA"):
```html
    <li class="nav-item">
      <a class="nav-link" routerLink="medical-providers" routerLinkActive="active" (click)="closeSidebar()">
        <i class="fas fa-hospital"></i> <span>Prestadores</span>
      </a>
    </li>
```

- [ ] **Step 4: Build** — Run: `npx ng build` · Expected: build OK (sin errores de template/DI).
- [ ] **Step 5: Verificación manual** — `npm start`, login en Gestión, entrar a "Prestadores": crear un prestador de prueba, editar, resetear password.
- [ ] **Step 6: Commit**
```bash
git add src/app/pages/application/home/home.module.ts \
        src/app/pages/application/home/home-routing.module.ts \
        src/app/pages/application/home/components/sidebar/sidebar.component.html
git commit -m "feat(prestador): sección Prestadores en Gestión (ruta + menú + módulo)"
```

---

## Smoke test end-to-end (post-deploy)

- [ ] Crear un prestador de prueba desde Gestión (con email/password).
- [ ] Login en `medical-provider-app` con esas credenciales → entra (consulta).
- [ ] `POST /api/prescriptions/upsert-and-create` con el JWT de esa cuenta → 200 (push). (Reusa el flujo de prueba del prestador.)
- [ ] Resetear la contraseña desde Gestión → login con la nueva clave funciona.

## Criterios de éxito (del spec)

- [ ] Alta de prestador desde Gestión crea entidad **y** usuario de login (`ROLE_MEDICAL_PROVIDER`), con rollback ante fallo.
- [ ] La cuenta sirve para consulta (app) y push (`/upsert-and-create`).
- [ ] Gestión resetea la contraseña del prestador.
- [ ] `MedicalProviderServiceImplTest` (3 tests) en verde.

## Self-review (hecho)

- **Cobertura del spec:** creación dual (Task 4), reset password (Task 4+5+6+8), sección nueva en Gestión (Tasks 7-9), `info` agregado backend (Task 1) y frontend (Task 6). ✅
- **Sin placeholders:** código completo en cada step; las únicas verificaciones inline (estilo Lombok del DTO, nombre del bean del service en el controller, orden de args del constructor `UserRequestSecurityApiRecetalia`) son chequeos rápidos contra archivos existentes, no contenido faltante. ✅
- **Consistencia de tipos:** `resetPassword(String id, String encryptedPassword, String info)` igual en interface (Task 3), impl (Task 4), controller (Task 5), service TS (Task 6) y componente (Task 8); `info` agregado en ambos `MedicalProviderRequest` (Java Task 1 / TS Task 6). ✅
- **Fuera de alcance respetado:** sin baja de login, sin API-key, sin tabla/rol nuevo. ✅
