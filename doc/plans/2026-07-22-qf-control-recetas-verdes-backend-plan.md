# QF — Control de Recetas Verdes — Plan 1: Backend (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Habilitar en el backend el perfil Químico Farmacéutico (QF / regente / D.T.): rol nuevo, login por CJP con password genérico + cambio forzado, alta automática del QF al afiliar/editar sucursales, endpoints para que el QF liste sus farmacias y sus recetas verdes dispensadas y las controle ("firme"), y un export Excel de "Medicamentos controlados por Farmacia".

**Architecture:** Dos APIs Spring Boot. `security-api-recetalia` (Flyway, puerto 8091) suma el rol `ROLE_PHARMACEUTICAL_DIRECTOR`, la aplicación `qf-recetalia-app` y el flag `users.mustChangePassword`. `recetalia-api-rest` (JPA, `ddl-auto=none`, puerto 8094) suma las columnas de control D.T. en `dispensation`, la creación dual del usuario QF (keyed por CJP), y los endpoints scopeados al QF + el Excel. El QF se identifica por CJP; su usuario de login se guarda con `email = username = {cjp}@qf.recetalia.com` (el frontend arma ese email a partir del CJP tipeado). Las farmacias del QF = `pharmacy.managerCJP = cjp`.

**Tech Stack:** Java 21, Spring Boot 3.3.x, Spring Data JPA/Hibernate, Flyway (solo security-api, deshabilitada en runtime → SQL manual), Apache POI 5.2.3, JUnit 5. Gradle (`./gradlew`).

**Design de referencia:** `doc/plans/2026-07-22-qf-control-recetas-verdes-design.md`.

**Reglas del repo (verificadas):**
- `recetalia-api-rest`: `spring.jpa.hibernate.ddl-auto: none`, sin Flyway → **todo cambio de esquema es ALTER TABLE manual** en la DB.
- `security-api-recetalia`: `spring.flyway.enabled: false` → las migrations **no** corren al arrancar; el SQL se aplica **manualmente** en la DB (además de versionar el archivo).
- Doble prefijo: el JWT lleva `role="ROLE_X"` y el converter de api-rest agrega otro `ROLE_` → la authority real es `ROLE_ROLE_X`.
- `SecurityApiRecetaliaPortImpl.registerUser` pega a `/api/auth/register` (que **descifra** el password) y **pisa** `username = email`. Para el QF (password genérico en claro) se agrega un método que pega a `/api/auth/registerBack` (sin descifrar).
- CJP en el ejemplo del Libro Negro es numérico (`136175`, `96479`) → `136175@qf.recetalia.com` es un email válido y `@Email` lo acepta.

**Rama de trabajo:** crear `feat/qf-control-recetas-verdes` en `security-api-recetalia` y en `recetalia-api-rest` (desde `2.x.y`). **Sin merge hasta OK explícito de Pablo.**

---

## File Structure

**security-api-recetalia**
- Create: `src/main/resources/db/migration/V5__qf_role_and_app.sql` — seed rol + app (versionado; se aplica manual).
- Modify: `src/main/java/.../domain/model/entities/User.java` — campo `mustChangePassword`.
- Modify: `src/main/java/.../dto/request/UserRequest.java` — campo `mustChangePassword`.
- Modify: `src/main/java/.../dto/response/TokenResponse.java` — campo `mustChangePassword`.
- Modify: `src/main/java/.../service/impl/UserServiceImpl.java` — set/clear + exponer flag.
- Test: `src/test/java/.../service/impl/UserServiceImplMustChangePasswordTest.java`.

**recetalia-api-rest**
- Modify: `src/main/java/.../domain/model/entities/Dispensation.java` — columnas `dtControl*`.
- Modify: `src/main/java/.../infrastructure/adapter/restsecurityapirecetalia/dto/UserRequestSecurityApiRecetalia.java` — campo `mustChangePassword` + constructores.
- Modify: `src/main/java/.../infrastructure/adapter/restsecurityapirecetalia/SecurityApiRecetaliaPort.java` — método `registerUserBack`.
- Modify: `src/main/java/.../infrastructure/adapter/restsecurityapirecetalia/impl/SecurityApiRecetaliaPortImpl.java` — impl `registerUserBack`.
- Modify: `src/main/java/.../service/impl/PharmacyServiceImpl.java` — `ensurePharmaceuticalDirectorUser(...)`.
- Modify: `src/main/resources/application.yml` — `qf.default-password`, `qf.email-domain`.
- Modify: `src/main/java/.../service/impl/CurrentUserAuthenticatedServiceImpl.java` — `getCurrentPharmaceuticalDirectorCjp()`.
- Modify: `src/main/java/.../service/CurrentUserAuthenticatedService.java` — firma nueva.
- Modify: `src/main/java/.../dto/response/DispensationSearchRow.java` — getters `dtControl*` + `medicalProviderName`.
- Modify: `src/main/java/.../domain/repository/DispensationRepository.java` — SELECTs nuevos + `applyDtControl`.
- Modify: `src/main/java/.../domain/repository/PharmacyRepository.java` — `findAllByManagerCJPAndDeletedAtIsNull`.
- Create: `src/main/java/.../controller/PharmaceuticalDirectorController.java`.
- Create: `src/main/java/.../service/PharmaceuticalDirectorService.java` (+ `impl/PharmaceuticalDirectorServiceImpl.java`).
- Modify: `src/main/java/.../infrastructure/config/SecurityConfiguration.java` — matcher rol nuevo.
- Modify: `src/main/java/.../infrastructure/config/WebConfig.java` — CORS origin.
- Create: `src/main/java/.../service/ControlledMedicationsExcelService.java` (+ impl) y endpoint en `DispensationController.java`.
- Create: `src/main/java/.../domain/repository/PharmacyHeaderRepository.java` (o método en `PharmacyRepository`) — datos de cabecera del Excel.
- Tests bajo `src/test/java/...` por tarea.

---

## PARTE A — security-api-recetalia

### Task 1: Seed del rol `ROLE_PHARMACEUTICAL_DIRECTOR` y la app `qf-recetalia-app`

**Files:**
- Create: `security-api-recetalia/src/main/resources/db/migration/V5__qf_role_and_app.sql`

Contexto: `V2__data.sql` siembra roles con ids 1..11 y apps con ids 1 (`security-api-recetalia`), 2 (`medics-recetalia-app`). Se agrega rol id 12 y app id 3. Flyway está deshabilitada → el archivo queda versionado pero el SQL se aplica **manualmente** en la `securitydb` de PRE.

- [ ] **Step 1: Escribir la migration**

```sql
-- V5__qf_role_and_app.sql
-- Químico Farmacéutico (regente / Director Técnico). Ver doc/plans/2026-07-22-qf-control-recetas-verdes-design.md
INSERT INTO roles (id, name) VALUES (12, 'ROLE_PHARMACEUTICAL_DIRECTOR');
INSERT INTO applications (id, apiKey, name) VALUES (3, 'qf-recetalia-app', 'qf-recetalia-app');
```

- [ ] **Step 2: Verificar el nombre real de las columnas de `applications`**

Run: `grep -nE "apiKey|name|@Column" security-api-recetalia/src/main/java/com/recetalia/security/api/application/domain/model/entities/Application.java`
Expected: confirmar que las columnas son `apiKey` y `name` (ajustar el INSERT si difiere). Confirmar en `Role.java` que son `id`, `name`.

- [ ] **Step 3: Compilar**

Run: `cd security-api-recetalia && ./gradlew compileJava`
Expected: BUILD SUCCESSFUL (el `.sql` no rompe compilación; es solo versionado).

- [ ] **Step 4: Commit**

```bash
cd security-api-recetalia
git add src/main/resources/db/migration/V5__qf_role_and_app.sql
git commit -m "feat(qf): seed ROLE_PHARMACEUTICAL_DIRECTOR + qf-recetalia-app application"
```

> El SQL se aplicará a la `securitydb` de PRE en el Plan 4 (deploy). No se aplica en esta fase.

---

### Task 2: Flag `mustChangePassword` en `users` + exponerlo en el login

**Files:**
- Modify: `security-api-recetalia/src/main/java/com/recetalia/security/api/application/domain/model/entities/User.java`
- Modify: `security-api-recetalia/src/main/java/com/recetalia/security/api/application/dto/request/UserRequest.java`
- Modify: `security-api-recetalia/src/main/java/com/recetalia/security/api/application/dto/response/TokenResponse.java`
- Modify: `security-api-recetalia/src/main/java/com/recetalia/security/api/application/service/impl/UserServiceImpl.java`
- Test: `security-api-recetalia/src/test/java/com/recetalia/security/api/application/service/impl/UserServiceImplMustChangePasswordTest.java`

- [ ] **Step 1: Agregar el campo a la entidad `User`**

En `User.java`, junto a los otros `@Column` (mirar cómo está declarado `isActive` para copiar el estilo Lombok/JPA):

```java
@org.hibernate.annotations.ColumnDefault("0")
@jakarta.persistence.Column(name = "mustChangePassword", nullable = false)
private boolean mustChangePassword = false;
```

- [ ] **Step 2: Agregar el campo al DTO `UserRequest`** (opcional en el JSON; ausente → false)

En `UserRequest.java` (es un `@Data`/POJO con getters/setters):

```java
/** Cuando true, el usuario debe cambiar su contraseña en el primer login (perfil QF). */
private Boolean mustChangePassword;
```

- [ ] **Step 3: Agregar el campo a `TokenResponse`**

`TokenResponse` es `@Data @AllArgsConstructor`. Agregar el campo al final:

```java
private String token;
private String refreshToken;
private String username;
private String role;
private boolean mustChangePassword;
```

- [ ] **Step 4: Ajustar `UserServiceImpl`** (set en register, clear en renew, exponer en authenticate/refresh)

En `registerUser(...)`, después de `user.setApplication(application);` y antes de `userRepository.save(user);`:

```java
user.setMustChangePassword(Boolean.TRUE.equals(userRequest.getMustChangePassword()));
```

En `renewPassword(...)`, después de `user.setPassword(newPassword);`:

```java
user.setMustChangePassword(false); // acaba de fijar una contraseña nueva
```

En `authenticate(...)`, reemplazar el `return`:

```java
return new TokenResponse(token, null, user.getUsername(), role, user.isMustChangePassword());
```

En `refreshToken(...)`, ambos `new TokenResponse(...)` pasan a 5 args con `user.isMustChangePassword()` como último argumento.

- [ ] **Step 5: Escribir el test (falla primero)**

```java
package com.recetalia.security.api.application.service.impl;

import com.recetalia.security.api.application.domain.model.entities.User;
import com.recetalia.security.api.application.dto.response.TokenResponse;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

class UserServiceImplMustChangePasswordTest {

    @Test
    void tokenResponse_carriesMustChangePasswordFlag() {
        // Contrato del DTO: el 5º argumento es el flag y se expone tal cual.
        TokenResponse r = new TokenResponse("tkn", null, "136175@qf.recetalia.com", "ROLE_PHARMACEUTICAL_DIRECTOR", true);
        assertThat(r.isMustChangePassword()).isTrue();
    }

    @Test
    void user_defaultsMustChangePasswordToFalse() {
        assertThat(new User().isMustChangePassword()).isFalse();
    }
}
```

- [ ] **Step 6: Correr el test → debe fallar a compilar/pasar antes de los cambios**

Run: `cd security-api-recetalia && ./gradlew test --tests "*UserServiceImplMustChangePasswordTest"`
Expected: FAIL de compilación (constructor de 5 args / `isMustChangePassword` inexistentes) hasta aplicar Steps 1-4.

- [ ] **Step 7: Correr el test → debe pasar**

Run: `cd security-api-recetalia && ./gradlew test --tests "*UserServiceImplMustChangePasswordTest"`
Expected: PASS.

- [ ] **Step 8: Build completo**

Run: `cd security-api-recetalia && ./gradlew build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 9: Registrar el ALTER manual para PRE (Plan 4)**

Agregar al final de `V5__qf_role_and_app.sql`:

```sql
ALTER TABLE users ADD COLUMN mustChangePassword TINYINT(1) NOT NULL DEFAULT 0;
```

- [ ] **Step 10: Commit**

```bash
cd security-api-recetalia
git add -A
git commit -m "feat(qf): mustChangePassword flag on users + expose in login TokenResponse"
```

---

## PARTE B — recetalia-api-rest

### Task 3: Columnas de control D.T. en `Dispensation`

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/domain/model/entities/Dispensation.java`

- [ ] **Step 1: Agregar los campos** (junto a `condvtaId`, línea ~104)

```java
@Column(name = "dtControlAt")
private Instant dtControlAt;

@Column(name = "dtControlName", length = 300)
private String dtControlName;

@Column(name = "dtControlCjp", length = 150)
private String dtControlCjp;
```

- [ ] **Step 2: Compilar**

Run: `cd recetalia-api-rest && ./gradlew compileJava`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Registrar el ALTER manual** (para aplicar en PRE en el Plan 4)

Crear/append en `recetalia-api-rest/doc/specs/ddl-qf-control.sql`:

```sql
-- recetali_receta — control D.T. (Químico Farmacéutico) sobre dispensaciones verdes
ALTER TABLE dispensation ADD COLUMN dtControlAt   DATETIME(6) NULL;
ALTER TABLE dispensation ADD COLUMN dtControlName VARCHAR(300) NULL;
ALTER TABLE dispensation ADD COLUMN dtControlCjp  VARCHAR(150) NULL;
```

- [ ] **Step 4: Commit**

```bash
cd recetalia-api-rest
git add -A
git commit -m "feat(qf): dtControl columns on Dispensation entity + DDL script"
```

---

### Task 4: Método `registerUserBack` en el port a security-api + campo `mustChangePassword` en el DTO

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/infrastructure/adapter/restsecurityapirecetalia/dto/UserRequestSecurityApiRecetalia.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/infrastructure/adapter/restsecurityapirecetalia/SecurityApiRecetaliaPort.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/infrastructure/adapter/restsecurityapirecetalia/impl/SecurityApiRecetaliaPortImpl.java`

- [ ] **Step 1: Agregar `mustChangePassword` al DTO sin romper los 6-arg callers**

Reemplazar `@AllArgsConstructor` por dos constructores explícitos (mantiene los llamadores existentes de franquicia/farmacia/prestador):

```java
package com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class UserRequestSecurityApiRecetalia {

    @NotBlank private String username;
    @NotBlank @Email private String email;
    @NotBlank private String password;   // en /register va cifrado; en /registerBack va en claro
    @NotBlank private String role;
    @NotBlank private String applicationApiKey;
    @NotBlank private String info;

    /** Solo se usa en el alta del QF vía /registerBack. Ausente/false para el resto. */
    private Boolean mustChangePassword;

    public UserRequestSecurityApiRecetalia(String username, String email, String password,
                                           String role, String applicationApiKey, String info) {
        this(username, email, password, role, applicationApiKey, info, null);
    }

    public UserRequestSecurityApiRecetalia(String username, String email, String password,
                                           String role, String applicationApiKey, String info,
                                           Boolean mustChangePassword) {
        this.username = username;
        this.email = email;
        this.password = password;
        this.role = role;
        this.applicationApiKey = applicationApiKey;
        this.info = info;
        this.mustChangePassword = mustChangePassword;
    }
}
```

- [ ] **Step 2: Declarar `registerUserBack` en el port**

En `SecurityApiRecetaliaPort.java`:

```java
UserResponseSecurityApiRecetalia registerUserBack(UserRequestSecurityApiRecetalia request);
```

- [ ] **Step 3: Implementar `registerUserBack` (pega a `/registerBack`, sin descifrar, sin pisar username)**

En `SecurityApiRecetaliaPortImpl.java` agregar:

```java
@Override
public UserResponseSecurityApiRecetalia registerUserBack(UserRequestSecurityApiRecetalia userRequest) {
    String url = securityApiRecetaliaUrl + "/api/auth/registerBack";
    HttpHeaders headers = new HttpHeaders();
    HttpEntity<UserRequestSecurityApiRecetalia> requestEntity = new HttpEntity<>(userRequest, headers);
    ResponseEntity<GenericResponseSecurityApiRecetalia<UserResponseSecurityApiRecetalia>> response =
        restTemplate.exchange(url, HttpMethod.POST, requestEntity, new ParameterizedTypeReference<>() {});
    if (response.getBody() != null && response.getBody().getStatus().equals(ResponseStatus.SUCCESS)) {
        return response.getBody().getAnswer();
    }
    throw new RuntimeException("Failed to register user (back)");
}
```

Nota: a diferencia de `registerUser`, **no** se hace `userRequest.setUsername(userRequest.getEmail())` — igual acá username y email ya vienen iguales (el synthetic email). `/registerBack` no descifra el password.

- [ ] **Step 4: Compilar**

Run: `cd recetalia-api-rest && ./gradlew compileJava`
Expected: BUILD SUCCESSFUL (los callers de 6 args siguen compilando).

- [ ] **Step 5: Commit**

```bash
cd recetalia-api-rest
git add -A
git commit -m "feat(qf): registerUserBack port + mustChangePassword field in security DTO"
```

---

### Task 5: Alta dual del usuario QF al crear/editar sucursales (keyed por CJP)

**Files:**
- Modify: `recetalia-api-rest/src/main/resources/application.yml`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/PharmacyServiceImpl.java`
- Test: `recetalia-api-rest/src/test/java/com/recetalia/api/application/service/impl/PharmacyServiceQfUserTest.java`

- [ ] **Step 1: Config del password genérico y del dominio del email QF**

En `application.yml` (nivel raíz, junto a otras props del proyecto):

```yaml
qf:
  default-password: ${QF_DEFAULT_PASSWORD:Recetalia2026}
  email-domain: ${QF_EMAIL_DOMAIN:qf.recetalia.com}
```

- [ ] **Step 2: Escribir el test (falla primero)**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.SecurityApiRecetaliaPort;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.dto.UserRequestSecurityApiRecetalia;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.web.client.HttpClientErrorException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

class PharmacyServiceQfUserTest {

    @Test
    void ensureQfUser_registersWithCjpEmailRoleAndMustChange() {
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmacyServiceImpl svc = new PharmacyServiceImpl();
        svc.securityApiRecetaliaPortForTest(port);
        svc.setQfConfigForTest("Recetalia2026", "qf.recetalia.com");

        svc.ensurePharmaceuticalDirectorUser("  136175 ");

        ArgumentCaptor<UserRequestSecurityApiRecetalia> cap = ArgumentCaptor.forClass(UserRequestSecurityApiRecetalia.class);
        verify(port).registerUserBack(cap.capture());
        UserRequestSecurityApiRecetalia req = cap.getValue();
        assertThat(req.getEmail()).isEqualTo("136175@qf.recetalia.com");
        assertThat(req.getUsername()).isEqualTo("136175@qf.recetalia.com");
        assertThat(req.getPassword()).isEqualTo("Recetalia2026");
        assertThat(req.getRole()).isEqualTo("ROLE_PHARMACEUTICAL_DIRECTOR");
        assertThat(req.getApplicationApiKey()).isEqualTo("qf-recetalia-app");
        assertThat(req.getMustChangePassword()).isTrue();
    }

    @Test
    void ensureQfUser_noCjp_isNoop() {
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmacyServiceImpl svc = new PharmacyServiceImpl();
        svc.securityApiRecetaliaPortForTest(port);
        svc.setQfConfigForTest("Recetalia2026", "qf.recetalia.com");

        svc.ensurePharmaceuticalDirectorUser("   ");
        svc.ensurePharmaceuticalDirectorUser(null);

        verifyNoInteractions(port);
    }

    @Test
    void ensureQfUser_alreadyExists_isSwallowed() {
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        when(port.registerUserBack(any())).thenThrow(new RuntimeException("Email already exists."));
        PharmacyServiceImpl svc = new PharmacyServiceImpl();
        svc.securityApiRecetaliaPortForTest(port);
        svc.setQfConfigForTest("Recetalia2026", "qf.recetalia.com");

        svc.ensurePharmaceuticalDirectorUser("136175"); // no debe propagar
        verify(port).registerUserBack(any());
    }
}
```

> Nota de diseño: `PharmacyServiceImpl` usa inyección por `@Autowired` de campo. Para poder testear sin contexto Spring, agregar en la clase dos setters *package-private* de test (`securityApiRecetaliaPortForTest`, `setQfConfigForTest`) — Step 3. Es el patrón mínimo; si el equipo prefiere `@SpringBootTest` con `@MockBean`, adaptar.

- [ ] **Step 3: Implementar `ensurePharmaceuticalDirectorUser` en `PharmacyServiceImpl`**

Agregar los `@Value` y el método (y los setters de test). Cerca de los otros `@Value`:

```java
@Value("${qf.default-password}")
private String qfDefaultPassword;

@Value("${qf.email-domain}")
private String qfEmailDomain;

// --- setters de test (package-private) ---
void securityApiRecetaliaPortForTest(com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.SecurityApiRecetaliaPort p) { this.securityApiRecetaliaPort = p; }
void setQfConfigForTest(String pwd, String domain) { this.qfDefaultPassword = pwd; this.qfEmailDomain = domain; }

/**
 * Asegura el usuario de login del Químico Farmacéutico (regente) para un CJP dado.
 * Identidad = CJP. Email/username sintéticos = {cjp}@{dominio}. Idempotente: si ya existe,
 * el "Email already exists" de security-api se ignora (varias sucursales comparten CJP).
 */
public void ensurePharmaceuticalDirectorUser(String managerCJP) {
    String cjp = trimToNull(managerCJP);
    if (cjp == null) return;
    String email = cjp + "@" + qfEmailDomain;
    var req = new com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.dto.UserRequestSecurityApiRecetalia(
        email, email, qfDefaultPassword, "ROLE_PHARMACEUTICAL_DIRECTOR", "qf-recetalia-app", "0", true);
    try {
        securityApiRecetaliaPort.registerUserBack(req);
        logger.info("Usuario QF asegurado para CJP {}", cjp);
    } catch (RuntimeException e) {
        String msg = e.getMessage();
        if (msg != null && (msg.contains("already exists"))) {
            // Ya existe el QF para ese CJP (otra sucursal lo creó). No-op.
            return;
        }
        // No romper el alta/edición de la sucursal por un fallo del alta del QF: log y seguir.
        logger.error("No se pudo asegurar el usuario QF para CJP {}: {}", cjp, msg);
    }
}
```

> `trimToNull` y `logger` ya existen en la clase.

- [ ] **Step 4: Invocar desde `create(...)` y `update(...)`**

En `create(...)`, después del bloque `try { securityApiRecetaliaPort.registerUser(...ROLE_PHARMACY...) }` que ya existe (tras crear el usuario de la farmacia), y antes del email de bienvenida:

```java
// Alta del QF (regente) si el request trae CJP. Best-effort: no revierte el alta de la farmacia.
ensurePharmaceuticalDirectorUser(request.getManagerCJP());
```

En `update(...)`, dentro del `if (role.equals("ROLE_MANAGEMENT"))`, después de `entity.setManagerCJP(...)` y del `pharmacyRepository.save(entity)` (usar el valor persistido), agregar tras `Pharmacy saved = pharmacyRepository.save(entity);`:

```java
// Si Gestión asignó/actualizó el regente (CJP), asegurar su usuario QF.
ensurePharmaceuticalDirectorUser(saved.getManagerCJP());
```

- [ ] **Step 5: Verificar el getter del request**

Run: `grep -n "getManagerCJP" recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/request/PharmacyRequest.java`
Expected: existe `getManagerCJP()`. (Si el POST de alta pública `/api/pharmacies` no incluye CJP, `ensure...` es no-op y el QF se crea recién cuando Gestión edita la sucursal con el regente — comportamiento correcto.)

- [ ] **Step 6: Correr los tests → deben pasar**

Run: `cd recetalia-api-rest && ./gradlew test --tests "*PharmacyServiceQfUserTest"`
Expected: PASS (3 tests).

- [ ] **Step 7: Build**

Run: `cd recetalia-api-rest && ./gradlew build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 8: Commit**

```bash
cd recetalia-api-rest
git add -A
git commit -m "feat(qf): dual-create pharmaceutical-director user (by CJP) on pharmacy create/update"
```

---

### Task 6: Extracción del CJP del token en api-rest

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/CurrentUserAuthenticatedService.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/CurrentUserAuthenticatedServiceImpl.java`

El usuario QF tiene `mail = {cjp}@{dominio}`. El CJP = parte antes de `@`.

- [ ] **Step 1: Declarar en la interfaz**

En `CurrentUserAuthenticatedService.java`:

```java
String getCurrentPharmaceuticalDirectorCjp() throws com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;
```

- [ ] **Step 2: Implementar**

En `CurrentUserAuthenticatedServiceImpl.java`:

```java
@Override
public String getCurrentPharmaceuticalDirectorCjp() throws ResourceNotFoundException {
    Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
    if (authentication instanceof JwtAuthenticationToken jwtToken) {
        String mail = jwtToken.getToken().getClaim("mail");
        if (mail != null && mail.contains("@")) {
            return mail.substring(0, mail.indexOf('@')).trim();
        }
    }
    throw new ResourceNotFoundException("No CJP claim for pharmaceutical director");
}
```

- [ ] **Step 3: Compilar**

Run: `cd recetalia-api-rest && ./gradlew compileJava`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
cd recetalia-api-rest
git add -A
git commit -m "feat(qf): resolve current pharmaceutical-director CJP from JWT mail claim"
```

---

### Task 7: Proyección `DispensationSearchRow` + query con `dtControl*` y `medicalProviderName`

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/response/DispensationSearchRow.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java`

- [ ] **Step 1: Agregar getters a la proyección**

En `DispensationSearchRow.java`, al final de la interfaz:

```java
  // Control D.T. (Químico Farmacéutico)
  Instant getDtControlAt();
  String  getDtControlName();
  String  getDtControlCjp();

  // Prestador (para el Excel de controlados)
  String  getMedicalProviderName();
```

- [ ] **Step 2: Agregar los SELECT en la query principal `searchDispensations`**

En el `value = """ ... """` del `@Query`, dentro del SELECT, agregar antes del `FROM dispensation d`:

```sql
      ,d.dtControlAt   AS dtControlAt
      ,d.dtControlName AS dtControlName
      ,d.dtControlCjp  AS dtControlCjp
      ,mp.name         AS medicalProviderName
```

> `mp` (medical_provider) ya está en el `LEFT JOIN medical_provider mp ON mp.id = m.medicalProviderId`. El `countQuery` **no** se toca (no proyecta columnas).

- [ ] **Step 3: Agregar el método de control idempotente al repositorio**

En `DispensationRepository.java`:

```java
@Modifying
@Transactional
@Query("""
   update Dispensation d
      set d.dtControlAt = CURRENT_TIMESTAMP,
          d.dtControlName = :name,
          d.dtControlCjp = :cjp
    where d.id = :id and d.dtControlAt is null and d.deletedAt is null
""")
int applyDtControl(@Param("id") String id, @Param("name") String name, @Param("cjp") String cjp);
```

Devuelve 1 si controló, 0 si ya estaba controlada o no existe (idempotente).

- [ ] **Step 4: Compilar**

Run: `cd recetalia-api-rest && ./gradlew compileJava`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit**

```bash
cd recetalia-api-rest
git add -A
git commit -m "feat(qf): expose dtControl + medicalProviderName in dispensation search + applyDtControl"
```

---

### Task 8: Endpoints del QF (farmacias, verdes dispensadas, controlar)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/domain/repository/PharmacyRepository.java`
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/PharmaceuticalDirectorService.java`
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorServiceImpl.java`
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/controller/PharmaceuticalDirectorController.java`
- Test: `recetalia-api-rest/src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorServiceImplTest.java`

- [ ] **Step 1: Repo — farmacias por CJP**

En `PharmacyRepository.java` agregar:

```java
java.util.List<com.recetalia.api.application.domain.model.entities.Pharmacy>
    findAllByManagerCJPAndDeletedAtIsNull(String managerCJP);
```

Run para confirmar que `Pharmacy` tiene `deletedAt`:
`grep -n "deletedAt" recetalia-api-rest/src/main/java/com/recetalia/api/application/domain/model/entities/Pharmacy.java`
Expected: existe. (Si no existiera, usar `findAllByManagerCJP`.)

- [ ] **Step 2: Interfaz del servicio**

```java
package com.recetalia.api.application.service;

import com.recetalia.api.application.dto.response.DispensationSearchRow;
import com.recetalia.api.application.dto.response.PharmacyResponse;
import com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import java.time.Instant;
import java.util.List;

public interface PharmaceuticalDirectorService {
    /** Farmacias del QF autenticado (por CJP del token). */
    List<PharmacyResponse> getMyPharmacies() throws ResourceNotFoundException;

    /** Recetas verdes dispensadas de una farmacia del QF. Valida pertenencia por CJP. */
    Page<DispensationSearchRow> getGreenDispensations(String pharmacyId, Instant fromTs, Instant toTs, Pageable pageable)
        throws ResourceNotFoundException;

    /** Firma/controla una dispensación. Valida pertenencia. Idempotente. Devuelve true si controló ahora. */
    boolean controlDispensation(String dispensationId) throws ResourceNotFoundException;
}
```

- [ ] **Step 3: Implementación**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.Dispensation;
import com.recetalia.api.application.domain.model.entities.Pharmacy;
import com.recetalia.api.application.domain.repository.DispensationRepository;
import com.recetalia.api.application.domain.repository.PharmacyRepository;
import com.recetalia.api.application.dto.mapper.response.PharmacyResponseMapper;
import com.recetalia.api.application.dto.response.DispensationSearchRow;
import com.recetalia.api.application.dto.response.PharmacyResponse;
import com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;
import com.recetalia.api.application.service.CurrentUserAuthenticatedService;
import com.recetalia.api.application.service.PharmaceuticalDirectorService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.List;
import java.util.stream.Collectors;

@Service
public class PharmaceuticalDirectorServiceImpl implements PharmaceuticalDirectorService {

    @Autowired private PharmacyRepository pharmacyRepository;
    @Autowired private DispensationRepository dispensationRepository;
    @Autowired private PharmacyResponseMapper pharmacyResponseMapper;
    @Autowired private CurrentUserAuthenticatedService currentUser;

    @Override
    public List<PharmacyResponse> getMyPharmacies() throws ResourceNotFoundException {
        String cjp = currentUser.getCurrentPharmaceuticalDirectorCjp();
        return pharmacyRepository.findAllByManagerCJPAndDeletedAtIsNull(cjp).stream()
                .map(pharmacyResponseMapper::toDto)
                .collect(Collectors.toList());
    }

    @Override
    public Page<DispensationSearchRow> getGreenDispensations(String pharmacyId, Instant fromTs, Instant toTs, Pageable pageable)
            throws ResourceNotFoundException {
        assertPharmacyBelongsToCurrentQf(pharmacyId);
        return dispensationRepository.searchDispensations(
                pharmacyId, null, null, null, null, null, null, null,
                null, "11", fromTs, toTs, pageable);
    }

    @Override
    public boolean controlDispensation(String dispensationId) throws ResourceNotFoundException {
        String cjp = currentUser.getCurrentPharmaceuticalDirectorCjp();
        Dispensation d = dispensationRepository.findWithGraphByIdAndDeletedAtIsNull(dispensationId)
                .orElseThrow(() -> new ResourceNotFoundException("Dispensation not found :: " + dispensationId));
        Pharmacy ph = d.getPharmacy();
        if (ph == null || ph.getManagerCJP() == null || !ph.getManagerCJP().trim().equals(cjp)) {
            throw new ResourceNotFoundException("Dispensation not controllable by this pharmaceutical director");
        }
        String name = buildQfName(ph);
        int updated = dispensationRepository.applyDtControl(dispensationId, name, cjp);
        return updated == 1;
    }

    private void assertPharmacyBelongsToCurrentQf(String pharmacyId) throws ResourceNotFoundException {
        String cjp = currentUser.getCurrentPharmaceuticalDirectorCjp();
        Pharmacy ph = pharmacyRepository.findById(pharmacyId)
                .orElseThrow(() -> new ResourceNotFoundException("Pharmacy not found :: " + pharmacyId));
        if (ph.getManagerCJP() == null || !ph.getManagerCJP().trim().equals(cjp)) {
            throw new ResourceNotFoundException("Pharmacy not assigned to this pharmaceutical director");
        }
    }

    /** Nombre del QF = manager de la farmacia (regente). */
    private String buildQfName(Pharmacy ph) {
        String n = ph.getManagerName() == null ? "" : ph.getManagerName().trim();
        String l = ph.getManagerLastname() == null ? "" : ph.getManagerLastname().trim();
        return (n + " " + l).trim();
    }
}
```

- [ ] **Step 4: Controller**

```java
package com.recetalia.api.application.controller;

import com.recetalia.api.application.dto.enums.ResponseStatus;
import com.recetalia.api.application.dto.response.DispensationSearchRow;
import com.recetalia.api.application.dto.response.GenericResponse;
import com.recetalia.api.application.dto.response.PharmacyResponse;
import com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;
import com.recetalia.api.application.service.PharmaceuticalDirectorService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;

@RestController
@RequestMapping("/api/pharmaceutical-director")
public class PharmaceuticalDirectorController {

    @Autowired
    private PharmaceuticalDirectorService service;

    @GetMapping("/pharmacies")
    public ResponseEntity<GenericResponse<List<PharmacyResponse>>> myPharmacies() throws ResourceNotFoundException {
        return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, service.getMyPharmacies()));
    }

    @GetMapping("/green-dispensations")
    public ResponseEntity<GenericResponse<Page<DispensationSearchRow>>> greenDispensations(
            @RequestParam String pharmacyId,
            @RequestParam(required = false) LocalDate startDate,
            @RequestParam(required = false) LocalDate endDate,
            Pageable pageable) throws ResourceNotFoundException {
        Instant fromTs = (startDate != null) ? startDate.atStartOfDay(ZoneId.systemDefault()).toInstant() : null;
        Instant toTs = (endDate != null) ? endDate.atStartOfDay(ZoneId.systemDefault()).plusDays(1).minusNanos(1).toInstant() : null;
        Page<DispensationSearchRow> page = service.getGreenDispensations(pharmacyId, fromTs, toTs, pageable);
        return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, page));
    }

    @PostMapping("/dispensations/{id}/control")
    public ResponseEntity<GenericResponse<Boolean>> control(@PathVariable String id) throws ResourceNotFoundException {
        boolean controlled = service.controlDispensation(id);
        return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, controlled));
    }
}
```

- [ ] **Step 5: Test unitario del servicio (mock repos + current user)**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.Dispensation;
import com.recetalia.api.application.domain.model.entities.Pharmacy;
import com.recetalia.api.application.domain.repository.DispensationRepository;
import com.recetalia.api.application.domain.repository.PharmacyRepository;
import com.recetalia.api.application.dto.mapper.response.PharmacyResponseMapper;
import com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;
import com.recetalia.api.application.service.CurrentUserAuthenticatedService;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class PharmaceuticalDirectorServiceImplTest {

    private PharmaceuticalDirectorServiceImpl newService(PharmacyRepository pr, DispensationRepository dr,
                                                         CurrentUserAuthenticatedService cu) {
        PharmaceuticalDirectorServiceImpl s = new PharmaceuticalDirectorServiceImpl();
        // inyección por reflexión de los @Autowired de campo
        org.springframework.test.util.ReflectionTestUtils.setField(s, "pharmacyRepository", pr);
        org.springframework.test.util.ReflectionTestUtils.setField(s, "dispensationRepository", dr);
        org.springframework.test.util.ReflectionTestUtils.setField(s, "pharmacyResponseMapper", mock(PharmacyResponseMapper.class));
        org.springframework.test.util.ReflectionTestUtils.setField(s, "currentUser", cu);
        return s;
    }

    @Test
    void control_ownedPharmacy_controlsOnce() throws Exception {
        var cu = mock(CurrentUserAuthenticatedService.class);
        when(cu.getCurrentPharmaceuticalDirectorCjp()).thenReturn("136175");
        var pr = mock(PharmacyRepository.class);
        var dr = mock(DispensationRepository.class);
        Pharmacy ph = new Pharmacy();
        ph.setManagerCJP("136175"); ph.setManagerName("Ana"); ph.setManagerLastname("Pérez");
        Dispensation d = new Dispensation(); d.setPharmacy(ph);
        when(dr.findWithGraphByIdAndDeletedAtIsNull("d1")).thenReturn(Optional.of(d));
        when(dr.applyDtControl("d1", "Ana Pérez", "136175")).thenReturn(1);

        assertThat(newService(pr, dr, cu).controlDispensation("d1")).isTrue();
        verify(dr).applyDtControl("d1", "Ana Pérez", "136175");
    }

    @Test
    void control_foreignPharmacy_rejected() throws Exception {
        var cu = mock(CurrentUserAuthenticatedService.class);
        when(cu.getCurrentPharmaceuticalDirectorCjp()).thenReturn("999");
        var pr = mock(PharmacyRepository.class);
        var dr = mock(DispensationRepository.class);
        Pharmacy ph = new Pharmacy(); ph.setManagerCJP("136175");
        Dispensation d = new Dispensation(); d.setPharmacy(ph);
        when(dr.findWithGraphByIdAndDeletedAtIsNull("d1")).thenReturn(Optional.of(d));

        assertThatThrownBy(() -> newService(pr, dr, cu).controlDispensation("d1"))
                .isInstanceOf(ResourceNotFoundException.class);
        verify(dr, never()).applyDtControl(any(), any(), any());
    }
}
```

> Confirmar que `Pharmacy` tiene setters (`@Setter` Lombok). Si `new Pharmacy()` requiere id, usar el no-args constructor JPA (existe).

- [ ] **Step 6: Correr los tests → deben pasar**

Run: `cd recetalia-api-rest && ./gradlew test --tests "*PharmaceuticalDirectorServiceImplTest"`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
cd recetalia-api-rest
git add -A
git commit -m "feat(qf): pharmaceutical-director endpoints (my pharmacies, green dispensations, control)"
```

---

### Task 9: Seguridad (matcher del rol nuevo) + CORS del nuevo origin

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/infrastructure/config/SecurityConfiguration.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/infrastructure/config/WebConfig.java`

- [ ] **Step 1: Matcher del rol (doble prefijo)**

En `SecurityConfiguration.filterChain`, junto al matcher de `/api/control-dashboard/**`:

```java
.requestMatchers("/api/pharmaceutical-director/**").hasAuthority("ROLE_ROLE_PHARMACEUTICAL_DIRECTOR")
```

- [ ] **Step 2: CORS origin**

En `WebConfig.corsConfigurationSource()`, agregar a `setAllowedOrigins(...)` (sin barra final; los browsers mandan el Origin sin `/`):

```java
"https://qfpre.doctorconsultas.com"
```

> Nota: la lista actual tiene dominios `.uy` con barra final que no matchean el Origin real; el CORS efectivo lo resuelve nginx en el deploy (Plan 4). Igual se agrega el origin acá por correctitud.

- [ ] **Step 3: Build**

Run: `cd recetalia-api-rest && ./gradlew build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
cd recetalia-api-rest
git add -A
git commit -m "feat(qf): secure /api/pharmaceutical-director + allow qfpre origin (CORS)"
```

---

### Task 10: Export Excel "Medicamentos controlados por Farmacia"

Replica el layout del archivo de referencia: cabecera (Farmacia/Rut/Dirección/Departamento/Localidad) en A2:B6, tabla desde fila 9.

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/domain/repository/PharmacyRepository.java` — proyección de cabecera.
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/response/PharmacyHeaderRow.java`
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/ControlledMedicationsExcelService.java` (+ `impl/...Impl.java`)
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/controller/DispensationController.java` — endpoint export.

- [ ] **Step 1: Proyección de cabecera + query**

Crear `PharmacyHeaderRow.java`:

```java
package com.recetalia.api.application.dto.response;

public interface PharmacyHeaderRow {
    String getName();
    String getRut();
    String getAddressStreet();
    String getAddressNumber();
    String getLocalityName();
    String getDepartmentName();
}
```

En `PharmacyRepository.java` agregar:

```java
@org.springframework.data.jpa.repository.Query(value = """
   SELECT ph.name AS name, ph.rut AS rut,
          ph.addressStreet AS addressStreet, ph.addressNumber AS addressNumber,
          l.name AS localityName, r.name AS departmentName
     FROM pharmacy ph
     LEFT JOIN localities l ON l.id = ph.addressLocalityId
     LEFT JOIN regions r ON r.id = l.region_id
    WHERE ph.id = :id
""", nativeQuery = true)
com.recetalia.api.application.dto.response.PharmacyHeaderRow findHeaderById(
    @org.springframework.data.repository.query.Param("id") String id);
```

> Los nombres `localities`, `localities.region_id`, `regions.name` los usa el mapa del dashboard (ver CLAUDE.md de api-rest) → existen. Verificar el nombre de la columna calle/numero contra `Pharmacy.java` (`addressStreet`, `addressNumber`).

- [ ] **Step 2: Interfaz + impl del servicio Excel**

Interfaz `ControlledMedicationsExcelService.java`:

```java
package com.recetalia.api.application.service;

import org.apache.poi.ss.usermodel.Workbook;
import java.time.Instant;

public interface ControlledMedicationsExcelService {
    Workbook build(String pharmacyId, Instant fromTs, Instant toTs);
}
```

Impl `ControlledMedicationsExcelServiceImpl.java`:

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.repository.DispensationRepository;
import com.recetalia.api.application.domain.repository.PharmacyRepository;
import com.recetalia.api.application.dto.response.DispensationSearchRow;
import com.recetalia.api.application.dto.response.PharmacyHeaderRow;
import com.recetalia.api.application.service.ControlledMedicationsExcelService;
import com.recetalia.api.application.service.impl.DnmaDatabaseServiceImpl;
import org.apache.poi.ss.usermodel.*;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class ControlledMedicationsExcelServiceImpl implements ControlledMedicationsExcelService {

    private static final DateTimeFormatter D = DateTimeFormatter.ofPattern("dd-MM-yyyy").withZone(ZoneId.systemDefault());
    private static final DateTimeFormatter DT = DateTimeFormatter.ofPattern("dd-MM-yyyy HH:mm").withZone(ZoneId.systemDefault());
    private static final String[] COLS = {
        "Codigo Unico + Fecha Prescripción", "Prestador", "Nombre Paciente + Cedula",
        "Nombre Medico + CJP", "Medicamento", "Sucursal Dispensada",
        "Fecha + Hora Dispensada", "Fecha Control D.T.", "Nombre + CJP D.T."
    };

    @Autowired private PharmacyRepository pharmacyRepository;
    @Autowired private DispensationRepository dispensationRepository;
    @Autowired private DnmaDatabaseServiceImpl dnma;

    @Override
    public Workbook build(String pharmacyId, Instant fromTs, Instant toTs) {
        PharmacyHeaderRow h = pharmacyRepository.findHeaderById(pharmacyId);
        List<DispensationSearchRow> rows = fetchAllGreen(pharmacyId, fromTs, toTs);
        Map<String, String> productNames = resolveProductNames(rows);

        Workbook wb = new XSSFWorkbook();
        Sheet sheet = wb.createSheet("Controlados");
        CellStyle bold = wb.createCellStyle();
        Font f = wb.createFont(); f.setBold(true); bold.setFont(f);

        // Cabecera A2:B6
        writeKV(sheet, 1, "Farmacia", h != null ? nz(h.getName()) : "", bold);
        writeKV(sheet, 2, "Rut", h != null ? nz(h.getRut()) : "", bold);
        writeKV(sheet, 3, "Dirección", h != null ? (nz(h.getAddressStreet()) + " " + nz(h.getAddressNumber())).trim() : "", bold);
        writeKV(sheet, 4, "Departamento", h != null ? nz(h.getDepartmentName()) : "", bold);
        writeKV(sheet, 5, "Localidad", h != null ? nz(h.getLocalityName()) : "", bold);

        // Header de tabla en fila 9 (index 8)
        Row header = sheet.createRow(8);
        for (int i = 0; i < COLS.length; i++) {
            Cell c = header.createCell(i); c.setCellValue(COLS[i]); c.setCellStyle(bold);
        }

        int r = 9;
        for (DispensationSearchRow row : rows) {
            Row out = sheet.createRow(r++);
            out.createCell(0).setCellValue(nz(row.getPrescriptionCode()) + " " + fmtD(row.getPrescriptionCreatedAt()));
            out.createCell(1).setCellValue(row.getMedicalProviderName() != null && !row.getMedicalProviderName().isBlank()
                    ? row.getMedicalProviderName() : "Particular");
            out.createCell(2).setCellValue((nz(row.getPatientName()) + " " + nz(row.getPatientLastName())).trim()
                    + " CI " + docNumber(row.getPatientDocument()));
            out.createCell(3).setCellValue((nz(row.getMedicName()) + " " + nz(row.getMedicLastname())).trim()
                    + " CJP " + nz(row.getMedicCJP()));
            out.createCell(4).setCellValue(nz(productNames.get(row.getDispensationProductId())));
            out.createCell(5).setCellValue(nz(row.getPharmacyName()));
            out.createCell(6).setCellValue(fmtDT(row.getDispensationUpdatedAt() != null ? row.getDispensationUpdatedAt() : row.getDispensationCreatedAt()));
            out.createCell(7).setCellValue(row.getDtControlAt() != null ? fmtD(row.getDtControlAt()) : "");
            out.createCell(8).setCellValue(row.getDtControlAt() != null
                    ? (nz(row.getDtControlName()) + " " + nz(row.getDtControlCjp())).trim() : "");
        }
        for (int i = 0; i < COLS.length; i++) sheet.autoSizeColumn(i);
        return wb;
    }

    private List<DispensationSearchRow> fetchAllGreen(String pharmacyId, Instant fromTs, Instant toTs) {
        List<DispensationSearchRow> all = new ArrayList<>();
        int page = 0; Page<DispensationSearchRow> p;
        do {
            p = dispensationRepository.searchDispensations(
                pharmacyId, null, null, null, null, null, null, null,
                null, "11", fromTs, toTs, PageRequest.of(page++, 500));
            all.addAll(p.getContent());
        } while (p.hasNext() && page < 100); // tope de 50k filas
        return all;
    }

    /** Resuelve nombre del medicamento dispensado vía DNMA (AMPP → AMPP_DSC; si no, AMP → AMP_DSC). */
    private Map<String, String> resolveProductNames(List<DispensationSearchRow> rows) {
        List<String> ids = rows.stream().map(DispensationSearchRow::getDispensationProductId)
                .filter(Objects::nonNull).distinct().collect(Collectors.toList());
        Map<String, String> out = new HashMap<>();
        if (ids.isEmpty()) return out;
        // AMPP
        for (Map<String, String> m : dnma.fetchAmppDetails(ids)) {
            out.putIfAbsent(m.get("AMPP_Id"), m.get("AMPP_DSC"));
        }
        // AMP para los que no resolvieron a nivel AMPP
        List<String> rest = ids.stream().filter(id -> !out.containsKey(id)).collect(Collectors.toList());
        if (!rest.isEmpty()) {
            Map<String, Map<String, String>> amp = dnma.fetchAmpDetails(rest);
            amp.forEach((id, det) -> out.putIfAbsent(id, det.get("ampDsc")));
        }
        return out;
    }

    private void writeKV(Sheet s, int rowIdx, String k, String v, CellStyle bold) {
        Row row = s.createRow(rowIdx);
        Cell kc = row.createCell(0); kc.setCellValue(k); kc.setCellStyle(bold);
        row.createCell(1).setCellValue(v);
    }
    private String nz(String s) { return s == null ? "" : s; }
    private String fmtD(Instant i) { return i == null ? "" : D.format(i); }
    private String fmtDT(Instant i) { return i == null ? "" : DT.format(i); }

    /** patientDocument viene como JSON (DocumentConverter). Extrae el número de forma tolerante. */
    private String docNumber(String documentJson) {
        if (documentJson == null) return "";
        int idx = documentJson.indexOf("\"number\"");
        if (idx < 0) return documentJson.replaceAll("[^0-9A-Za-z.-]", "");
        int colon = documentJson.indexOf(':', idx);
        int q1 = documentJson.indexOf('"', colon + 1);
        int q2 = documentJson.indexOf('"', q1 + 1);
        return (q1 >= 0 && q2 > q1) ? documentJson.substring(q1 + 1, q2) : "";
    }
}
```

- [ ] **Step 2b: Verificar las firmas de `DnmaDatabaseServiceImpl`**

Run: `grep -nE "public .*fetchAmppDetails|public .*fetchAmpDetails|AMPP_Id|AMPP_DSC|ampDsc" recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/DnmaDatabaseServiceImpl.java`
Expected: `fetchAmppDetails(List<String>) : List<Map<String,String>>` con claves `AMPP_Id`/`AMPP_DSC`; `fetchAmpDetails(List<String>) : Map<String,Map<String,String>>` con clave `ampDsc`. Ajustar los nombres de clave en el Step 2 si difieren (usar los reales del método).

- [ ] **Step 3: Endpoint en `DispensationController`**

Agregar imports `org.apache.poi.ss.usermodel.Workbook`, `java.io.ByteArrayOutputStream`, `org.springframework.http.*`, y autowire del servicio + método:

```java
@Autowired
private com.recetalia.api.application.service.ControlledMedicationsExcelService controlledMedicationsExcelService;

@GetMapping("/controlled-medications/excel")
public ResponseEntity<byte[]> controlledMedicationsExcel(
        @RequestParam String pharmacyId,
        @RequestParam(required = false) java.time.LocalDate startDate,
        @RequestParam(required = false) java.time.LocalDate endDate) throws java.io.IOException {
    Instant fromTs = (startDate != null) ? startDate.atStartOfDay(ZoneId.systemDefault()).toInstant() : null;
    Instant toTs = (endDate != null) ? endDate.atStartOfDay(ZoneId.systemDefault()).plusDays(1).minusNanos(1).toInstant() : null;
    try (org.apache.poi.ss.usermodel.Workbook wb = controlledMedicationsExcelService.build(pharmacyId, fromTs, toTs);
         java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream()) {
        wb.write(bos);
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(org.springframework.http.MediaType.parseMediaType(
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"));
        headers.setContentDispositionFormData("attachment", "medicamentos-controlados.xlsx");
        return new ResponseEntity<>(bos.toByteArray(), headers, HttpStatus.OK);
    }
}
```

> Este endpoint es para la app de Farmacias (ROLE_PHARMACY / ROLE_PHARMACY_ADMIN). Queda bajo `.anyRequest().authenticated()` (sin matcher específico) → cualquier usuario autenticado con token válido puede pedirlo con un `pharmacyId`. En el Plan 3 el front lo llama con el `pharmacyId` de la propia farmacia. (Endurecer por rol/propiedad es una mejora futura documentada.)

- [ ] **Step 4: Build**

Run: `cd recetalia-api-rest && ./gradlew build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit**

```bash
cd recetalia-api-rest
git add -A
git commit -m "feat(qf): controlled-medications Excel export (Libro Negro format)"
```

---

## Verificación de integración (local / dev)

> Requiere el rol/app sembrados y las columnas creadas en la DB apuntada por `application.yml`. En local, aplicar los ALTER de Task 2/3 y los INSERT de Task 1 en la DB de dev antes de probar. En PRE se hace en el Plan 4.

- [ ] **V1: Build de ambos repos**

Run: `cd security-api-recetalia && ./gradlew build && cd ../recetalia-api-rest && ./gradlew build`
Expected: ambos BUILD SUCCESSFUL.

- [ ] **V2: Login del QF por CJP** (tras crear un QF vía alta/edición de sucursal con `managerCJP`)

Run (ajustar host/CJP):
```bash
curl -s -X POST "$SEC/api/auth/loginBack" -H 'Content-Type: application/json' \
  -d '{"email":"136175@qf.recetalia.com","password":"Recetalia2026","info":"0"}' | jq
```
Expected: `status: SUCCESS`, `answer.role: "ROLE_PHARMACEUTICAL_DIRECTOR"`, `answer.mustChangePassword: true`.

- [ ] **V3: Farmacias del QF**

Run:
```bash
curl -s "$API/api/pharmaceutical-director/pharmacies" -H "Authorization: Bearer $TOKEN" | jq '.answer | length'
```
Expected: cuenta ≥ 1 (las sucursales con ese CJP).

- [ ] **V4: Verdes dispensadas + control**

Run:
```bash
curl -s "$API/api/pharmaceutical-director/green-dispensations?pharmacyId=$PH&startDate=2025-01-01&endDate=2026-12-31" -H "Authorization: Bearer $TOKEN" | jq '.answer.content[0]'
curl -s -X POST "$API/api/pharmaceutical-director/dispensations/$DID/control" -H "Authorization: Bearer $TOKEN" | jq
```
Expected: la primera lista sólo condvta `11`; el control devuelve `answer: true` la 1ª vez y `false` (idempotente) la 2ª. Tras controlar, el mismo row trae `dtControlAt` no nulo.

- [ ] **V5: Excel de controlados**

Run:
```bash
curl -s "$API/api/dispensations/controlled-medications/excel?pharmacyId=$PH&startDate=2025-01-01&endDate=2026-12-31" -H "Authorization: Bearer $TOKEN" -o /tmp/controlados.xlsx
python3 -c "import openpyxl; wb=openpyxl.load_workbook('/tmp/controlados.xlsx'); ws=wb.active; [print([c.value for c in r]) for r in ws.iter_rows(min_row=1,max_row=12)]"
```
Expected: A2:B6 con Farmacia/Rut/Dirección/Departamento/Localidad; fila 9 con las 9 cabeceras; filas de datos con Fecha Control D.T. y Nombre+CJP D.T. llenos sólo en las controladas.

---

## Self-Review (cobertura del spec)

- Rol nuevo + app → Task 1. `mustChangePassword` → Task 2 (security) consumido por Plan 2.
- Columnas de control D.T. → Task 3. Alta dual por CJP → Task 5. Login por CJP → email sintético (Task 5) + extracción (Task 6).
- Listado de farmacias del QF → Task 8. Verdes dispensadas → Task 7 (query) + Task 8 (endpoint). Firmar → Task 7 (`applyDtControl`) + Task 8.
- Excel formato Libro Negro → Task 10. Seguridad del rol + CORS → Task 9.
- **Fuera de esta fase (Plan 2/3/4):** app QF Angular, módulo/listado en Farmacias + botón de export, forzado visual del cambio de contraseña, DNS/nginx/cert/CORS de `qfpre.doctorconsultas.com`, aplicación de migrations/DDL/INSERTs en PRE.

**Puntos a validar durante ejecución (no bloqueantes, ajustar inline):**
- Nombres reales de columnas en `Application.java`/`Pharmacy.java` (Steps que lo indican).
- Claves reales de `DnmaDatabaseServiceImpl.fetchAmpp/AmpDetails` (Task 10 Step 2b).
- Que el POST público `/api/pharmacies` traiga o no `managerCJP` (define si el QF se crea en alta o recién al editar en Gestión).
