# QF — Validación por Gestión — Plan 1: Backend

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) o superpowers:executing-plans para implementar este plan task-by-task. Los steps usan checkbox (`- [ ]`).

**Goal:** Que un QF nuevo no pueda entrar hasta que Gestión lo habilite, y que la clave inicial la asigne Gestión.

**Architecture:** Una columna `validatedAt` en `pharmaceutical_director`. El usuario de login deja de crearse en el alta de farmacia y pasa a crearse cuando Gestión valida. Dos endpoints nuevos para `ROLE_MANAGEMENT`: validar y reasignar clave.

**Tech Stack:** Java 21 / Spring Boot 3.3 / JPA. Tests JUnit 5 + Mockito + AssertJ, con los *test seams* que ya usan las clases (`setDepsForTest`).

**Spec:** [2026-08-02-qf-validacion-gestion-design.md](2026-08-02-qf-validacion-gestion-design.md)

---

## Contexto imprescindible

**Rama:** `recetalia-api-rest` sigue en `feat/qf-registro-y-papel` (HEAD `921d32a`, **156 tests verdes**). Working tree limpio.

**`ddl-auto: none`.** Hibernate NO crea ni altera tablas. La columna se agrega **a mano** (Task 1) y **antes** de deployar el código.

**Los tests no tocan la base.** Usan Mockito sobre los repositorios. Un test verde no prueba que el SQL ande — ese fue exactamente el bug del Plan 4a. La validación real va en la Task 8.

**El `info` del `UserRequestSecurityApiRecetalia` es obligatorio** (`@NotBlank`) aunque `registerUserBack` no lo use para descifrar. Si va null, el security-api responde "Validation failed".

**`registerUser` vs `registerUserBack`:** el primero espera la clave **cifrada AES** (la manda el front del alta de farmacia y solo `/register` la descifra con el `info`). El segundo la espera **en claro**. Gestión va a tipear la clave en claro → **`registerUserBack`**. Ver la Task 5.

### Las trampas

**`resolveForPharmacy` tiene un `catch` que borra el QF.** Hoy, si falla el registro del usuario, hace `qfRepository.delete(qf)`. Al sacar la creación del usuario ese catch queda sin sentido y **hay que eliminarlo**, o queda código que borra filas por un error que ya no puede ocurrir.

**`currentQf()` exige el estado bueno, no enumera los malos** (`PharmaceuticalDirectorServiceImpl:93`). Mantener ese criterio al sumar `validatedAt`: un estado nuevo no debe quedar habilitado por omisión.

**El alta de farmacia es pública.** `resolveForPharmacy` se llama desde ahí sin autenticación. Los endpoints nuevos son de `ROLE_MANAGEMENT` y van en `PharmaceuticalDirectorAdminController`, que ya está bajo otro path.

⚠️ **`@EnableMethodSecurity` no existe en este proyecto**, así que los `@PreAuthorize` **no se evalúan**. La autorización real está en `SecurityConfiguration` por path. Los endpoints nuevos cuelgan de `/api/pharmaceutical-directors/**` — verificar en la Task 7 que ese path exige `ROLE_MANAGEMENT`, y **no confiar en un `@PreAuthorize`**.

---

### Task 1: La columna

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/domain/model/entities/PharmaceuticalDirector.java`

- [ ] **Step 1: Aplicar la migración en DEV**

```sql
ALTER TABLE pharmaceutical_director ADD COLUMN validatedAt TIMESTAMP NULL;
UPDATE pharmaceutical_director SET validatedAt = NOW();
```

Correrlo contra el `.98`:

```bash
ssh root@138.197.150.98 "docker exec -e MYSQL_PWD='RecDev98_x7Kq2mVt' recetalia-mysql \
  mysql -urecetalia_dev recetali_receta -e \"
  ALTER TABLE pharmaceutical_director ADD COLUMN validatedAt TIMESTAMP NULL;
  UPDATE pharmaceutical_director SET validatedAt = NOW();\""
```

- [ ] **Step 2: Verificar que no quedó ninguno sin validar**

```bash
ssh root@138.197.150.98 "docker exec -e MYSQL_PWD='RecDev98_x7Kq2mVt' recetalia-mysql \
  mysql -urecetalia_dev recetali_receta -e \"
  SELECT COUNT(*) AS total, SUM(validatedAt IS NULL) AS sin_validar FROM pharmaceutical_director;\""
```

Esperado: `sin_validar = 0`. Si no es 0, **parar**: un QF activo perdería el acceso sin explicación.

- [ ] **Step 3: El campo en la entidad**

En `PharmaceuticalDirector.java`, debajo de `registeredAt` (línea ~75):

```java
  /**
   * Cuándo Gestión habilitó a este QF. NULL = todavía no puede entrar.
   * Es independiente de `status`: un QF puede estar sin validar Y con el CJP en revisión.
   */
  @Column(name = "validatedAt")
  private Instant validatedAt;
```

- [ ] **Step 4: Compilar**

Run: `./gradlew compileJava`
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/recetalia/api/application/domain/model/entities/PharmaceuticalDirector.java
git commit -m "feat(qf): columna validatedAt en pharmaceutical_director"
```

---

### Task 2: `currentQf()` exige la validación

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorServiceImpl.java:86-98`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorServiceImplTest.java`

- [ ] **Step 1: Escribir el test que falla**

Agregar a `PharmaceuticalDirectorServiceImplTest`:

```java
    @Test
    void qfSinValidar_noOpera() throws Exception {
        PharmaceuticalDirector qf = new PharmaceuticalDirector();
        qf.setCjp("999999");
        qf.setStatus(PharmaceuticalDirector.STATUS_ACTIVE);
        qf.setValidatedAt(null);   // Gestión todavía no lo habilitó

        PharmaceuticalDirectorRepository qfs = mock(PharmaceuticalDirectorRepository.class);
        CurrentUserAuthenticatedService cu = mock(CurrentUserAuthenticatedService.class);
        when(cu.getCurrentPharmaceuticalDirectorCjp()).thenReturn("999999");
        when(qfs.findByCjp("999999")).thenReturn(Optional.of(qf));

        PharmaceuticalDirectorServiceImpl svc = new PharmaceuticalDirectorServiceImpl();
        svc.setDepsForTest(mock(PharmacyRepository.class), mock(DispensationRepository.class), cu, qfs);

        assertThatThrownBy(svc::getMyPharmacies)
                .isInstanceOf(BusinessRuleException.class)
                .hasMessageContaining("habilitada");
    }

    @Test
    void qfValidado_opera() throws Exception {
        PharmaceuticalDirector qf = new PharmaceuticalDirector();
        qf.setCjp("999999");
        qf.setStatus(PharmaceuticalDirector.STATUS_ACTIVE);
        qf.setValidatedAt(java.time.Instant.now());

        PharmaceuticalDirectorRepository qfs = mock(PharmaceuticalDirectorRepository.class);
        CurrentUserAuthenticatedService cu = mock(CurrentUserAuthenticatedService.class);
        PharmacyRepository phs = mock(PharmacyRepository.class);
        when(cu.getCurrentPharmaceuticalDirectorCjp()).thenReturn("999999");
        when(qfs.findByCjp("999999")).thenReturn(Optional.of(qf));
        when(phs.findAllByManagerCJPAndDeletedAtIsNull("999999")).thenReturn(java.util.List.of());

        PharmaceuticalDirectorServiceImpl svc = new PharmaceuticalDirectorServiceImpl();
        svc.setDepsForTest(phs, mock(DispensationRepository.class), cu, qfs);

        assertThat(svc.getMyPharmacies()).isEmpty();   // no explota: pasa el guard
    }
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `./gradlew test --tests '*PharmaceuticalDirectorServiceImplTest*'`
Expected: FAIL — `qfSinValidar_noOpera` no lanza nada porque el guard todavía no mira `validatedAt`.

- [ ] **Step 3: El guard**

En `PharmaceuticalDirectorServiceImpl.currentQf()`, reemplazar el bloque de la línea 93:

```java
        if (!PharmaceuticalDirector.STATUS_ACTIVE.equals(qf.getStatus())) {
            throw new BusinessRuleException(
                    "Tu cuenta no está habilitada. Contactate con Recetalia.");
        }
        // Habilitación de Recetalia. Es independiente de `status`: un QF puede estar ACTIVE
        // y todavía no validado. Se exige el estado bueno, no se enumeran los malos.
        if (qf.getValidatedAt() == null) {
            throw new BusinessRuleException(
                    "Tu cuenta no está habilitada. Contactate con Recetalia.");
        }
        return qf;
```

- [ ] **Step 4: Correr y verificar que pasa**

Run: `./gradlew test --tests '*PharmaceuticalDirectorServiceImplTest*'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorServiceImpl.java \
        src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorServiceImplTest.java
git commit -m "feat(qf): currentQf exige validatedAt"
```

---

### Task 3: El QF nace sin usuario de login

Es el cambio central. Hoy `resolveForPharmacy` exige la clave y crea el usuario; pasa a crear solo la fila.

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java:44-103`
- Modify: `src/main/java/com/recetalia/api/application/dto/request/PharmacyRequest.java:61`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorResolveTest.java`

- [ ] **Step 1: Escribir el test que falla**

Agregar a `PharmaceuticalDirectorResolveTest`:

```java
    @Test
    void cjpNuevo_creaElQfSinUsuarioDeLogin_yLoDejaSinValidar() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        when(repo.findByCjp("123456")).thenReturn(Optional.empty());
        when(repo.save(any(PharmaceuticalDirector.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        PharmaceuticalDirector qf = newSvc(repo, port)
                .resolveForPharmacy(requestWith("123456", "Ana", "Silva", null));

        assertThat(qf.getCjp()).isEqualTo("123456");
        assertThat(qf.getValidatedAt()).isNull();          // lo habilita Gestión
        verifyNoInteractions(port);                         // NO se crea usuario de login
    }

    @Test
    void cjpNuevo_sinClave_yaNoFalla() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        when(repo.findByCjp("123456")).thenReturn(Optional.empty());
        when(repo.save(any(PharmaceuticalDirector.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        // La clave ya no es parte del alta: antes esto tiraba BusinessRuleException.
        assertThat(newSvc(repo, port).resolveForPharmacy(requestWith("123456", "Ana", "Silva", null)))
                .isNotNull();
    }
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `./gradlew test --tests '*PharmaceuticalDirectorResolveTest*'`
Expected: FAIL con `BusinessRuleException: Falta la clave inicial del Químico Farmacéutico`.

- [ ] **Step 3: Sacar la creación del usuario**

En `resolveForPharmacy`, reemplazar todo desde el chequeo de `managerPassword` hasta el `return qf;` final por:

```java
    PharmaceuticalDirector qf = new PharmaceuticalDirector();
    qf.setCjp(cjp);
    qf.setName(trimToNull(request.getManagerName()));
    qf.setLastname(trimToNull(request.getManagerLastname()));
    qf.setDocument(request.getManagerDocument());
    qf.setStatus(PharmaceuticalDirector.STATUS_ACTIVE);
    // Contacto opcional: si la farmacia lo declara, Gestión puede avisarle al QF
    // directamente en vez de pasar por la farmacia.
    qf.setEmail(trimToNull(request.getManagerEmail()));
    // `validatedAt` queda NULL: el QF existe pero todavía no puede entrar. El usuario de
    // login NO se crea acá — lo crea Gestión al validar. Mientras tanto no hay con qué
    // loguearse, que es exactamente el punto: el alta de farmacia es pública y no puede
    // regalar acceso al módulo de control.
    qf = qfRepository.save(qf);
    logger.info("QF creado para CJP {}, pendiente de validación", cjp);
    return qf;
  }
```

⚠️ Con esto desaparece el `try/catch` que hacía `qfRepository.delete(qf)`. **Eso es intencional**: ya no hay una llamada externa que pueda fallar después del `save`.

- [ ] **Step 4: Sacar `managerPassword` del request**

En `PharmacyRequest.java`, borrar la línea 61 (`private String managerPassword;`).

Compilar para que el compilador liste todos los usos:

Run: `./gradlew compileJava compileTestJava`
Expected: errores en cada lugar que todavía llama a `getManagerPassword()`/`setManagerPassword(...)`. Borrar esas líneas. En `PharmaceuticalDirectorResolveTest`, el helper `requestWith(...)` deja de setearla — dejar el parámetro pero ignorarlo, o quitarlo de los 4 call sites.

- [ ] **Step 5: Correr toda la suite**

Run: `./gradlew build`
Expected: BUILD SUCCESSFUL. **Van a fallar tests viejos** que verificaban que se creaba el usuario o que faltaba la clave — esos tests probaban el comportamiento que estamos cambiando: borrarlos o adaptarlos, no "arreglarlos" a la fuerza.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(qf): el QF nace sin usuario de login, lo crea Gestion al validar"
```

---

### Task 4: Contacto opcional del QF

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/dto/request/PharmacyRequest.java`

- [ ] **Step 1: El campo**

En `PharmacyRequest.java`, donde estaba `managerPassword`:

```java
  /** Email del Químico Farmacéutico. OPCIONAL: sirve para que Gestión lo contacte al validarlo. */
  private String managerEmail;
```

La entidad `PharmaceuticalDirector` **ya tiene** `email` (línea 53) y `phone` (57) — no hay que agregarlos.

- [ ] **Step 2: Compilar**

Run: `./gradlew compileJava`
Expected: BUILD SUCCESSFUL (la Task 3 Step 3 ya usa `getManagerEmail()`).

- [ ] **Step 3: Commit**

```bash
git add src/main/java/com/recetalia/api/application/dto/request/PharmacyRequest.java
git commit -m "feat(qf): email opcional del QF en el alta de farmacia"
```

---

### Task 5: Validar y asignar la clave

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/PharmaceuticalDirectorRegistrationService.java`
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java`
- Create: `src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorValidateTest.java`

- [ ] **Step 1: Escribir el test que falla**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.domain.repository.PharmaceuticalDirectorRepository;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.SecurityApiRecetaliaPort;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.dto.UserRequestSecurityApiRecetalia;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class PharmaceuticalDirectorValidateTest {

    private PharmaceuticalDirectorRegistrationServiceImpl newSvc(
            PharmaceuticalDirectorRepository repo, SecurityApiRecetaliaPort port) {
        PharmaceuticalDirectorRegistrationServiceImpl svc = new PharmaceuticalDirectorRegistrationServiceImpl();
        svc.setDepsForTest(repo, port, null);
        svc.setQfConfigForTest("qf.recetalia.com");
        return svc;
    }

    private PharmaceuticalDirector qf(String cjp, java.time.Instant validatedAt) {
        PharmaceuticalDirector q = new PharmaceuticalDirector();
        q.setCjp(cjp);
        q.setStatus(PharmaceuticalDirector.STATUS_ACTIVE);
        q.setValidatedAt(validatedAt);
        return q;
    }

    @Test
    void validar_creaElUsuarioConCambioObligatorio_yMarcaLaFecha() throws Exception {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmaceuticalDirector q = qf("123456", null);
        when(repo.findByCjp("123456")).thenReturn(Optional.of(q));
        when(repo.save(any(PharmaceuticalDirector.class))).thenAnswer(i -> i.getArgument(0));

        newSvc(repo, port).validate("123456", "ClaveTemporal1");

        ArgumentCaptor<UserRequestSecurityApiRecetalia> cap =
                ArgumentCaptor.forClass(UserRequestSecurityApiRecetalia.class);
        verify(port).registerUserBack(cap.capture());
        assertThat(cap.getValue().getEmail()).isEqualTo("123456@qf.recetalia.com");
        assertThat(cap.getValue().getPassword()).isEqualTo("ClaveTemporal1");
        assertThat(cap.getValue().getRole()).isEqualTo("ROLE_PHARMACEUTICAL_DIRECTOR");
        assertThat(cap.getValue().getMustChangePassword()).isTrue();
        assertThat(q.getValidatedAt()).isNotNull();
    }

    @Test
    void siFallaElSecurityApi_noQuedaValidado() throws Exception {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmaceuticalDirector q = qf("123456", null);
        when(repo.findByCjp("123456")).thenReturn(Optional.of(q));
        doThrow(new RuntimeException("boom")).when(port).registerUserBack(any());

        assertThatThrownBy(() -> newSvc(repo, port).validate("123456", "ClaveTemporal1"))
                .isInstanceOf(RuntimeException.class);

        // No puede quedar "validado" alguien que no puede entrar.
        assertThat(q.getValidatedAt()).isNull();
        verify(repo, never()).save(any());
    }

    @Test
    void reasignarClave_usaRenewPassword_yNoPisaLaFechaDeValidacion() throws Exception {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        java.time.Instant original = java.time.Instant.parse("2026-01-01T00:00:00Z");
        PharmaceuticalDirector q = qf("123456", original);
        when(repo.findByCjp("123456")).thenReturn(Optional.of(q));

        newSvc(repo, port).reassignPassword("123456", "OtraClave2");

        verify(port).renewPassword(any(UserRequestSecurityApiRecetalia.class));
        verify(port, never()).registerUserBack(any());
        assertThat(q.getValidatedAt()).isEqualTo(original);
    }
}
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `./gradlew test --tests '*PharmaceuticalDirectorValidateTest*'`
Expected: FAIL — no compila: `validate`, `reassignPassword` y `registerUserBack` no existen.

- [ ] **Step 3: El método en el puerto**

En `SecurityApiRecetaliaPort.java`:

```java
    /** Alta con la clave EN CLARO (la tipea Gestión). registerUser la espera cifrada AES. */
    public UserResponseSecurityApiRecetalia registerUserBack(UserRequestSecurityApiRecetalia request);
```

Implementarlo en el adapter siguiendo el patrón de `registerUser`, apuntando a `/registerBack` del security-api.

- [ ] **Step 4: Los métodos del servicio**

En la interfaz `PharmaceuticalDirectorRegistrationService`:

```java
  /** Habilita al QF y le crea el usuario de login con la clave que asigna Gestión. */
  void validate(String cjp, String password) throws ResourceNotFoundException;

  /** Reasigna la clave de un QF ya validado. */
  void reassignPassword(String cjp, String password) throws ResourceNotFoundException;
```

En el `Impl`:

```java
  @Override
  @Transactional
  public void validate(String cjp, String password) throws ResourceNotFoundException {
    PharmaceuticalDirector qf = requireQf(cjp);
    if (qf.getValidatedAt() != null) {
      throw new BusinessRuleException("El QF con CJP " + cjp + " ya está habilitado.");
    }
    String email = cjp + "@" + qfEmailDomain;
    // registerUserBack y NO registerUser: la clave la tipea Gestión en claro; registerUser
    // la espera cifrada AES y guardaría el texto tal cual como password.
    // El `info` es @NotBlank aunque este camino no lo use para descifrar.
    securityApiRecetaliaPort.registerUserBack(new UserRequestSecurityApiRecetalia(
        email, email, password, "ROLE_PHARMACEUTICAL_DIRECTOR", "qf-recetalia-app", "000", true));
    // Recién acá: si el security-api falla, no puede quedar "validado" alguien sin acceso.
    qf.setValidatedAt(Instant.now());
    qfRepository.save(qf);
    logger.info("QF {} habilitado por Gestión", cjp);
  }

  @Override
  @Transactional
  public void reassignPassword(String cjp, String password) throws ResourceNotFoundException {
    PharmaceuticalDirector qf = requireQf(cjp);
    if (qf.getValidatedAt() == null) {
      throw new BusinessRuleException("El QF con CJP " + cjp + " todavía no fue habilitado.");
    }
    String email = cjp + "@" + qfEmailDomain;
    securityApiRecetaliaPort.renewPassword(new UserRequestSecurityApiRecetalia(
        email, email, password, "ROLE_PHARMACEUTICAL_DIRECTOR", "qf-recetalia-app", "000", true));
    logger.info("Clave reasignada al QF {}", cjp);
  }

  private PharmaceuticalDirector requireQf(String cjp) throws ResourceNotFoundException {
    String normalized = trimToNull(cjp);
    if (normalized == null) throw new ResourceNotFoundException("CJP vacío");
    return qfRepository.findByCjp(normalized)
        .orElseThrow(() -> new ResourceNotFoundException("No hay QF con CJP :: " + normalized));
  }
```

- [ ] **Step 5: Correr y verificar que pasa**

Run: `./gradlew test --tests '*PharmaceuticalDirectorValidateTest*'`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(qf): validar y reasignar clave desde Gestion"
```

---

### Task 6: El listado de pendientes

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/domain/repository/PharmaceuticalDirectorRepository.java`
- Modify: `src/main/java/com/recetalia/api/application/service/PharmaceuticalDirectorRegistrationService.java` + `impl/`

- [ ] **Step 1: La query**

En `PharmaceuticalDirectorRepository`:

```java
  /** Pendientes de habilitación por Gestión. */
  List<PharmaceuticalDirector> findAllByValidatedAtIsNullOrderByCjpAsc();
```

- [ ] **Step 2: El método del servicio**

Reusar el mapeo a `PharmaceuticalDirectorReviewRow` que ya usa `listByStatus`. En la interfaz:

```java
  /** QF pendientes de habilitación, con sus farmacias asociadas. */
  List<PharmaceuticalDirectorReviewRow> listPendingValidation();
```

En el `Impl`, copiar el cuerpo de `listByStatus` cambiando la query por `findAllByValidatedAtIsNullOrderByCjpAsc()`.

- [ ] **Step 3: Compilar**

Run: `./gradlew build`
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(qf): listado de QF pendientes de validacion"
```

---

### Task 7: Los endpoints

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/controller/PharmaceuticalDirectorAdminController.java`
- Check: `src/main/java/com/recetalia/api/application/infrastructure/config/SecurityConfiguration.java`

- [ ] **Step 1: Verificar la autorización del path**

⚠️ **Primero esto.** Buscar en `SecurityConfiguration` qué exige `/api/pharmaceutical-directors/**`:

```bash
grep -n "pharmaceutical-directors" src/main/java/com/recetalia/api/application/infrastructure/config/SecurityConfiguration.java
```

Tiene que exigir el rol de Gestión. Si no aparece, cae en el `anyRequest().authenticated()` → **cualquier usuario logueado podría validar QFs**. En ese caso agregar la regla explícita. **No confiar en un `@PreAuthorize`**: `@EnableMethodSecurity` no está activo y no se evalúa.

- [ ] **Step 2: El request**

Create `src/main/java/com/recetalia/api/application/dto/request/QfPasswordRequest.java`:

```java
package com.recetalia.api.application.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;

/** Clave que Gestión le asigna a un QF. Viaja en claro: la tipea el operador. */
@Data
public class QfPasswordRequest {
  @NotBlank
  @Size(min = 8, message = "La clave debe tener al menos 8 caracteres")
  private String password;
}
```

- [ ] **Step 3: Los endpoints**

En `PharmaceuticalDirectorAdminController`:

```java
  /** Bandeja de habilitación: los QF que todavía no puede usar nadie. */
  @GetMapping("/pending-validation")
  public ResponseEntity<GenericResponse<List<PharmaceuticalDirectorReviewRow>>> pendingValidation() {
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS,
        service.listPendingValidation()));
  }

  /** Habilita al QF y le crea el usuario de login con la clave asignada. */
  @PostMapping("/{cjp}/validate")
  public ResponseEntity<GenericResponse<Boolean>> validate(
      @PathVariable String cjp,
      @RequestBody @Valid QfPasswordRequest request) throws ResourceNotFoundException {
    service.validate(cjp, request.getPassword());
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, true));
  }

  /** Reasigna la clave de un QF ya habilitado. */
  @PostMapping("/{cjp}/reassign-password")
  public ResponseEntity<GenericResponse<Boolean>> reassignPassword(
      @PathVariable String cjp,
      @RequestBody @Valid QfPasswordRequest request) throws ResourceNotFoundException {
    service.reassignPassword(cjp, request.getPassword());
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, true));
  }
```

⚠️ Un `@Valid` roto **no** devuelve un mensaje útil: `GlobalExceptionHandler` no extiende `ResponseEntityExceptionHandler`, así que cae en el catch-all y vuelve como 500 *"Error interno del servidor"*. La pantalla tiene que validar el mínimo de 8 caracteres del lado del cliente (va en el Plan 2).

- [ ] **Step 4: Build completo**

Run: `./gradlew build`
Expected: BUILD SUCCESSFUL, todos los tests verdes.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(qf): endpoints de validacion y reasignacion de clave"
```

---

### Task 8: Validación real en DEV

Los tests mockean los repositorios: **no prueban ni el SQL ni el security-api**. Esto sí.

- [ ] **Step 1: Deploy**

```bash
rsync -az --delete --exclude='.git' --exclude='build' --exclude='.gradle' \
  recetalia-api-rest/ root@138.197.150.98:/opt/recetalia/recetalia-api-rest/
ssh root@138.197.150.98 'cd /opt/recetalia/deploy-recetalia && \
  docker compose build recetalia-api-rest && \
  docker compose up -d --no-deps recetalia-api-rest'
```

⚠️ `--no-deps` y nombrando el servicio: un `up -d` a secas recrea nginx y rompe PRE.

- [ ] **Step 2: Que los 220 sigan operando**

El QF de prueba `999999@qf.recetalia.com` (clave `Recetalia2026!`) tiene que seguir entrando y viendo sus 3 farmacias:

```bash
QFTOK=$(curl -s -X POST "https://apipre.recetalia.com/security-api-recetalia/api/auth/loginBack" \
  -H "Content-Type: application/json" \
  -d '{"email":"999999@qf.recetalia.com","password":"Recetalia2026!","info":"000"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -s -H "Authorization: Bearer $QFTOK" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmaceutical-director/pharmacies"
```

Esperado: `SUCCESS` con 3 farmacias. **Si falla, la migración quedó a medias.**

- [ ] **Step 3: El circuito nuevo**

Con un token de Gestión (`gestion@recetalia.com`):

1. `GET /api/pharmaceutical-directors/pending-validation` → lista vacía (todos validados por la migración).
2. Crear una farmacia con un CJP inexistente (ej. `777001`) desde `farmaciaspre.recetalia.com/register/`.
3. `GET .../pending-validation` → aparece el CJP `777001`.
4. Intentar loguear `777001@qf.recetalia.com` → **falla**: el usuario no existe.
5. `POST /api/pharmaceutical-directors/777001/validate` con `{"password":"Temporal2026"}` → `SUCCESS`.
6. Loguear `777001@qf.recetalia.com` / `Temporal2026` → entra, y el token trae `mustChangePassword: true`.
7. `POST .../777001/reassign-password` con otra clave → `SUCCESS`, y la anterior deja de servir.

- [ ] **Step 4: Que no se rompió lo de antes**

- La bandeja de `NEEDS_REVIEW` sigue listando.
- El Libro Negro y el listado de verdes del QF siguen andando (comparten `currentQf()`).
- Un alta de farmacia con un CJP **existente** sigue reusando el QF sin pedir clave.

- [ ] **Step 5: Commit del estado validado**

```bash
git commit --allow-empty -m "chore(qf): validacion de la Fase 2 backend en DEV"
```

---

## Lo que NO va en este plan

Va en el **Plan 2 (pantallas)**: la solapa "Pendientes de validación" con el modal de clave en Gestión, sacar el campo de clave de los dos formularios de farmacia, el campo de email opcional, y el aviso *"El acceso del Químico Farmacéutico será habilitado por Recetalia"*.

**Hasta que el Plan 2 esté hecho, el alta de farmacia desde la UI va a seguir mandando `managerPassword`** — el backend lo ignora, no rompe. Pero un QF nuevo creado desde la UI queda pendiente y **sin forma de validarlo salvo por curl**. No dar por terminada la feature con el Plan 1 solo.
