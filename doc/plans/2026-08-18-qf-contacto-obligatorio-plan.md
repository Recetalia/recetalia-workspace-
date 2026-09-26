# Contacto obligatorio del Químico Farmacéutico — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el registro público de farmacia exija email y celular del Químico Farmacéutico, y que Gestión pueda cargarle o corregirle el contacto a los 221 QF que hoy no lo tienen.

**Architecture:** El alta pública de farmacia (`POST /api/pharmacies`) pasa a mandar `managerEmail` + `managerPhone` siempre, incluso cuando el CJP ya existe. El backend aplica *fill-if-empty*: sólo escribe el dato si el QF no lo tenía, de modo que una farmacia no puede pisar el contacto de un QF que ya declaró otra. Gestión, en cambio, sí sobrescribe: es la autoridad del dato, vía un endpoint nuevo `POST /api/pharmaceutical-directors/{cjp}/contact` y un modal calcado del de "Reasignar clave".

**Tech Stack:** Angular 18.2 (NgModule, Karma/Jasmine, `angular-phone-number-input` + `libphonenumber-js`), Spring Boot 3.3 / Java 21 (JPA, Lombok, JUnit 5 + Mockito + AssertJ), MySQL 8.

---

## Hechos verificados que condicionan el plan

Medidos el 2026-08-18 contra el código y la base de PRE. No re-derivarlos:

1. **La columna `pharmaceutical_director.phone` YA EXISTE** (`text`, nullable) y está 100 % vacía (223/223). El proyecto **no tiene Flyway ni Liquibase** (`ddl-auto: none`, ALTERs a mano). Reusarla ⇒ **este plan no necesita ninguna migración de esquema en PRE ni en PROD**. No crear una columna `celular`.
2. La entidad ya mapea `phone` como `@Lob @Convert(PhoneConverter.class)`, y `PhoneConverter.convertToEntityAttribute` ya tolera NULL. No hay que tocar el converter.
3. **`PharmacyRequest` está compartido** entre `POST /api/pharmacies` (alta pública) y `PUT /api/pharmacies/{id}` (edición desde Gestión — `PharmacyController.java:49` y `:64`, ambos `@Valid`).
4. **`GlobalExceptionHandler` NO maneja `MethodArgumentNotValidException`**: cae en el handler genérico de `Exception` y devuelve **500 "Error interno del servidor"** sin decir qué campo falló.
   → **Consecuencia (1) + (3) + (4): NO agregar `@NotBlank` ni `@Email` a `managerEmail` en `PharmacyRequest`.** Rompería la edición de farmacia desde Gestión con un 500 opaco. La obligatoriedad se impone en el formulario; el backend sólo persiste. Está decidido, no re-discutir.
5. `SecurityConfiguration.java:86` ya protege `"/api/pharmaceutical-directors/**"` con `hasAuthority("ROLE_ROLE_MANAGEMENT")` (doble prefijo `ROLE_ROLE_`, no es un typo). **El endpoint nuevo queda protegido solo: no hay que tocar SecurityConfiguration.**
6. El endpoint nuevo usa **POST y no PATCH**, para no depender de que PATCH esté habilitado en la config de CORS: los dos endpoints hermanos (`validate`, `reassign-password`) ya son POST y funcionan.
7. Ambos fronts ya traen `angular-phone-number-input` y `libphonenumber-js` en su `package.json`. No hay dependencias nuevas.
8. **`String.strip()` NO saca el espacio duro (U+00A0).** Medido el 2026-08-18 con un `NbspCheck.java` sobre `"ana@qf.uy "`: `trim()` deja largo 10, `strip()` deja largo 10, y sólo `replaceAll("^[\\p{Z}\\s]+|[\\p{Z}\\s]+$", "")` deja 9. La causa es que `Character.isWhitespace(' ')` devuelve **`false`** —el NBSP es deliberadamente "no whitespace"— y `strip()` se define sobre `isWhitespace`. Importa porque el NBSP es justo lo que aparece al pegar un email desde Excel/Sheets, que es como se van a cargar los 221 QF: sin esto el mail se guarda inenviable y sin ningún síntoma. El helper `trimToNull` del servicio usa el regex `\p{Z}`, **no** `strip()`. No "simplificarlo" a `strip()` después.
9. **`farmacias-recetalia-app` arranca con 16 tests rotos de antes.** Medido el 2026-08-18 corriendo la suite en el tag `2.2.0`: **27 tests, 16 FAILED / 11 SUCCESS**. Son todos `X should create` de componentes (`HomeComponent`, `SidebarComponent`, `Prescription*`, `Medicine*`…) que fallan con `NG0304: '<x>' is not a known element` — TestBeds sin declarar sus módulos. **No los arregla este plan.** Sirven como línea base: después de las Tareas 5-6 la suite da **29 tests, 16 FAILED / 13 SUCCESS**, o sea +2 nuevos verdes y ni una regresión. Si en el futuro el número de FAILED sube de 16, eso sí es regresión.
10. Esto **revierte dos decisiones escritas** en `doc/plans/2026-08-02-qf-validacion-gestion-design.md:26` ("Email del QF: opcional" y "Only email, no teléfono — desproporcionado"). El motivo del descarte era el costo de tocar el tipo `Phone`; con la columna ya existente ese costo desapareció. La Tarea 9 corrige el documento.

---

## File Structure

### `recetalia-api-rest`

| Archivo | Acción | Responsabilidad |
|---|---|---|
| `dto/request/PharmacyRequest.java` | Modificar (~línea 57) | Sumar `managerPhone` |
| `dto/request/QfContactRequest.java` | **Crear** | Body del endpoint de contacto |
| `dto/response/PharmaceuticalDirectorReviewRow.java` | Modificar | Sumar `phone` para que la bandeja lo muestre |
| `service/PharmaceuticalDirectorRegistrationService.java` | Modificar | Firma de `updateContact` |
| `service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java` | Modificar | *fill-if-empty* en `resolveForPharmacy`; `updateContact`; mapear `phone` en `toReviewRows` |
| `controller/PharmaceuticalDirectorAdminController.java` | Modificar | `POST /{cjp}/contact` |
| `test/.../PharmaceuticalDirectorResolveTest.java` | Modificar | Casos de contacto en el alta |
| `test/.../PharmaceuticalDirectorContactTest.java` | **Crear** | Casos de `updateContact` |

### `farmacias-recetalia-app`

| Archivo | Acción | Responsabilidad |
|---|---|---|
| `shared/utils/phone-payload.util.ts` | **Crear** | Función pura string E.164 → objeto `Phone` |
| `shared/utils/phone-payload.util.spec.ts` | **Crear** | Sus tests |
| `model/request/pharmacy-request.ts` | Modificar | Tipo `PhonePayload` + `managerPhone` |
| `pages/application/register/register.component.ts` | Modificar | Validadores, uso del util, payload |
| `pages/application/register/register.component.html` | Modificar | Campos y labels |

### `gestion-recetadigital-app`

| Archivo | Acción | Responsabilidad |
|---|---|---|
| `model/response/pharmaceutical-director-review-row.ts` | Modificar | Tipo `Phone` + campo `phone` |
| `services/pharmaceutical-director.service.ts` | Modificar | `updateContact()` |
| `services/pharmaceutical-director.service.spec.ts` | **Crear** | Test de `updateContact()` |
| `.../pharmaceutical-director-list.component.ts` | Modificar | Estado y handlers del modal de contacto |
| `.../pharmaceutical-director-list.component.html` | Modificar | Columna Celular, botón y modal |

**Orden obligatorio:** backend (Tareas 1-4) → fronts (5-8). Los fronts consumen el contrato del backend; al revés no compila la prueba manual.

---

## Task 1: `managerPhone` en el alta de farmacia (backend)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/request/PharmacyRequest.java:57`
- Test: `recetalia-api-rest/src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorResolveTest.java`

- [ ] **Step 1: Escribir el test que falla**

Agregar al final de `PharmaceuticalDirectorResolveTest`, antes del `}` de cierre de la clase:

```java
    @Test
    void cjpNuevo_guardaElCelularDeclaradoPorLaFarmacia() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        when(repo.findByCjp("51697")).thenReturn(Optional.empty());
        when(repo.save(any(PharmaceuticalDirector.class))).thenAnswer(i -> i.getArgument(0));

        PharmacyRequest request = requestWith("51697", "JUAN", "PEREZ");
        request.setManagerEmail("juan@qf.uy");
        request.setManagerPhone(phone("+59899123456"));

        PharmaceuticalDirector qf = newSvc(repo, port).resolveForPharmacy(request);

        assertThat(qf.getEmail()).isEqualTo("juan@qf.uy");
        assertThat(qf.getPhone()).isNotNull();
        assertThat(qf.getPhone().getInternational()).isEqualTo("+59899123456");
    }
```

Y agregar este helper justo debajo del método `requestWith`:

```java
    private com.recetalia.api.application.domain.model.Phone phone(String international) {
        com.recetalia.api.application.domain.model.Phone p =
                new com.recetalia.api.application.domain.model.Phone();
        p.setCountryCode("UY");
        p.setNational(international.replace("+598", ""));
        p.setInternational(international);
        p.setType("mobile");
        p.setValidated(true);
        return p;
    }
```

- [ ] **Step 2: Correr el test y verificar que NO compila**

```bash
cd recetalia-api-rest && ./gradlew test --tests '*PharmaceuticalDirectorResolveTest'
```

Esperado: **error de compilación** `cannot find symbol: method setManagerPhone(Phone)`.

- [ ] **Step 3: Agregar el campo al DTO**

En `PharmacyRequest.java`, inmediatamente después del bloque de `managerEmail` (línea 57):

```java
  @Schema(description = "Celular de contacto del Químico Farmacéutico declarado por la farmacia")
  private Phone managerPhone;
```

`Phone` ya está importado (línea 4). **No agregar `@NotNull` ni `@Email` a este DTO** — ver el hecho verificado 4: lo comparte `PUT /api/pharmacies/{id}` y un `@Valid` roto vuelve como 500 opaco.

- [ ] **Step 4: Persistir el contacto en el alta de QF nuevo**

En `PharmaceuticalDirectorRegistrationServiceImpl.java`, reemplazar las líneas 72-74:

```java
    // Contacto opcional: si la farmacia lo declara, Gestión puede avisarle al QF
    // directamente en vez de pasar por la farmacia.
    qf.setEmail(trimToNull(request.getManagerEmail()));
```

por:

```java
    // Contacto del QF: el formulario público ahora lo exige, pero el DTO no lo valida
    // (lo comparte la edición de farmacia de Gestión), así que acá puede llegar null.
    qf.setEmail(trimToNull(request.getManagerEmail()));
    qf.setPhone(request.getManagerPhone());
```

- [ ] **Step 5: Correr el test y verificar que pasa**

```bash
cd recetalia-api-rest && ./gradlew test --tests '*PharmaceuticalDirectorResolveTest'
```

Esperado: **BUILD SUCCESSFUL**, 7 tests.

- [ ] **Step 6: Commit**

```bash
cd recetalia-api-rest
git add src/main/java/com/recetalia/api/application/dto/request/PharmacyRequest.java \
        src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java \
        src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorResolveTest.java
git commit -m "feat(qf): el alta de farmacia guarda el celular del quimico farmaceutico

La columna pharmaceutical_director.phone ya existia y estaba 100% vacia: se reusa
en vez de crear una columna nueva, asi el cambio no necesita ALTER TABLE en un
proyecto sin Flyway.

managerEmail/managerPhone NO llevan @NotBlank: PharmacyRequest lo comparte
PUT /api/pharmacies/{id}, y GlobalExceptionHandler no traduce los errores de
@Valid, asi que la edicion de farmacia desde Gestion volveria como un 500 opaco.
La obligatoriedad se impone en el formulario."
```

---

## Task 2: Fill-if-empty cuando el QF ya existe (backend)

Hoy `resolveForPharmacy` devuelve el QF existente **sin tocarlo** (líneas 61-63). Con el formulario pidiendo contacto siempre, hay que completar los huecos sin pisar lo que ya haya.

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java:61-63`
- Test: `recetalia-api-rest/src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorResolveTest.java`

- [ ] **Step 1: Escribir los dos tests que fallan**

```java
    @Test
    void qfExistenteSinContacto_seCompletaConLoQueDeclaraLaFarmacia() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmaceuticalDirector existente = new PharmaceuticalDirector("qf-1");
        existente.setCjp("51697");
        existente.setName("JUAN");
        existente.setLastname("PEREZ");
        when(repo.findByCjp("51697")).thenReturn(Optional.of(existente));
        when(repo.save(any(PharmaceuticalDirector.class))).thenAnswer(i -> i.getArgument(0));

        PharmacyRequest request = requestWith("51697", "JUAN", "PEREZ");
        request.setManagerEmail("  juan@qf.uy ");
        request.setManagerPhone(phone("+59899123456"));

        PharmaceuticalDirector qf = newSvc(repo, port).resolveForPharmacy(request);

        assertThat(qf.getEmail()).isEqualTo("juan@qf.uy");
        assertThat(qf.getPhone().getInternational()).isEqualTo("+59899123456");
        verify(repo).save(existente);
        verifyNoInteractions(port);   // completar contacto no toca la clave
    }

    @Test
    void qfExistenteConContacto_noSePisaConLoQueDeclaraOtraFarmacia() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmaceuticalDirector existente = new PharmaceuticalDirector("qf-1");
        existente.setCjp("51697");
        existente.setEmail("elbueno@qf.uy");
        existente.setPhone(phone("+59899000000"));
        when(repo.findByCjp("51697")).thenReturn(Optional.of(existente));

        PharmacyRequest request = requestWith("51697", "JUAN", "PEREZ");
        request.setManagerEmail("tipeado-mal@qf.uy");
        request.setManagerPhone(phone("+59899999999"));

        PharmaceuticalDirector qf = newSvc(repo, port).resolveForPharmacy(request);

        assertThat(qf.getEmail()).isEqualTo("elbueno@qf.uy");
        assertThat(qf.getPhone().getInternational()).isEqualTo("+59899000000");
        verify(repo, never()).save(any());   // nada que escribir
    }
```

- [ ] **Step 2: Correr y verificar que el primero falla**

```bash
cd recetalia-api-rest && ./gradlew test --tests '*PharmaceuticalDirectorResolveTest'
```

Esperado: `qfExistenteSinContacto_seCompletaConLoQueDeclaraLaFarmacia` **FALLA** con `expected: "juan@qf.uy" but was: null`. El segundo ya pasa (hoy no se escribe nunca).

- [ ] **Step 3: Implementar el fill-if-empty**

Reemplazar las líneas 61-63 (`// El QF ya fue dado de alta...` / `return qf;`) por:

```java
      // El QF ya fue dado de alta por otra farmacia: sus datos de identidad se reusan TAL
      // CUAL y su clave no se toca. El contacto es la única excepción, y sólo hacia arriba:
      // se completa lo que falte. Pisarlo dejaría que una farmacia con un dato mal tipeado
      // borre el contacto bueno que declaró otra.
      boolean completado = false;
      if (trimToNull(qf.getEmail()) == null && trimToNull(request.getManagerEmail()) != null) {
        qf.setEmail(trimToNull(request.getManagerEmail()));
        completado = true;
      }
      if (qf.getPhone() == null && request.getManagerPhone() != null) {
        qf.setPhone(request.getManagerPhone());
        completado = true;
      }
      if (completado) {
        qf = qfRepository.save(qf);
        logger.info("Contacto del QF {} completado desde el alta de una farmacia", cjp);
      }
      return qf;
```

- [ ] **Step 4: Correr los tests y verificar que pasan**

```bash
cd recetalia-api-rest && ./gradlew test --tests '*PharmaceuticalDirector*'
```

Esperado: **BUILD SUCCESSFUL**. Verificar en particular que el test preexistente `qfExistente_seReusaYNoSePisaNadaNiSeTocaElUsuario` **sigue pasando** — su `requestWith(...)` no setea contacto, así que `completado` queda en `false` y su `verify(repo, never()).save(any())` se mantiene.

- [ ] **Step 5: Commit**

```bash
cd recetalia-api-rest
git add src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java \
        src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorResolveTest.java
git commit -m "feat(qf): completar el contacto del QF existente sin pisarlo

El formulario ahora pide email y celular siempre, tambien cuando el CJP ya
existe. Se completa solo lo que falte: una farmacia no puede sobrescribir el
contacto que declaro otra."
```

---

## Task 3: Endpoint de edición de contacto para Gestión (backend)

A diferencia del alta pública, acá **sí se sobrescribe**: Gestión es la autoridad del dato.

**Files:**
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/request/QfContactRequest.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/PharmaceuticalDirectorRegistrationService.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/controller/PharmaceuticalDirectorAdminController.java`
- Create: `recetalia-api-rest/src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorContactTest.java`

- [ ] **Step 1: Escribir el test que falla**

Crear `PharmaceuticalDirectorContactTest.java`:

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.Phone;
import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.domain.repository.PharmaceuticalDirectorRepository;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.SecurityApiRecetaliaPort;
import com.recetalia.api.application.infrastructure.exception.BusinessRuleException;
import com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class PharmaceuticalDirectorContactTest {

    private PharmaceuticalDirectorRegistrationServiceImpl newSvc(
            PharmaceuticalDirectorRepository repo, SecurityApiRecetaliaPort port) {
        PharmaceuticalDirectorRegistrationServiceImpl svc = new PharmaceuticalDirectorRegistrationServiceImpl();
        svc.setDepsForTest(repo, port, null);
        svc.setQfConfigForTest("qf.recetalia.com");
        return svc;
    }

    private Phone phone(String international) {
        Phone p = new Phone();
        p.setCountryCode("UY");
        p.setInternational(international);
        p.setType("mobile");
        p.setValidated(true);
        return p;
    }

    @Test
    void gestionCargaElContactoDeUnQfQueNoLoTenia() throws Exception {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("099893");
        when(repo.findByCjp("099893")).thenReturn(Optional.of(qf));
        when(repo.save(any(PharmaceuticalDirector.class))).thenAnswer(i -> i.getArgument(0));

        newSvc(repo, port).updateContact("099893", "  ana@qf.uy ", phone("+59899123456"));

        assertThat(qf.getEmail()).isEqualTo("ana@qf.uy");
        assertThat(qf.getPhone().getInternational()).isEqualTo("+59899123456");
        verify(repo).save(qf);
        verifyNoInteractions(port);   // el contacto no tiene nada que ver con la clave
    }

    @Test
    void gestionSiPisaElContactoExistente() throws Exception {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("099893");
        qf.setEmail("viejo@qf.uy");
        when(repo.findByCjp("099893")).thenReturn(Optional.of(qf));
        when(repo.save(any(PharmaceuticalDirector.class))).thenAnswer(i -> i.getArgument(0));

        newSvc(repo, port).updateContact("099893", "nuevo@qf.uy", null);

        // Gestion es la autoridad del dato: acá sí se sobrescribe (a diferencia del alta).
        assertThat(qf.getEmail()).isEqualTo("nuevo@qf.uy");
    }

    @Test
    void emailConFormatoInvalido_seRechazaConMensajeUtil() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("099893");
        when(repo.findByCjp("099893")).thenReturn(Optional.of(qf));

        assertThatThrownBy(() -> newSvc(repo, port).updateContact("099893", "no-es-un-mail", null))
                .isInstanceOf(BusinessRuleException.class)
                .hasMessageContaining("formato");

        verify(repo, never()).save(any());
    }

    @Test
    void emailVacio_borraElContactoEnVezDeGuardarCadenaVacia() throws Exception {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("099893");
        qf.setEmail("viejo@qf.uy");
        when(repo.findByCjp("099893")).thenReturn(Optional.of(qf));
        when(repo.save(any(PharmaceuticalDirector.class))).thenAnswer(i -> i.getArgument(0));

        newSvc(repo, port).updateContact("099893", "   ", null);

        assertThat(qf.getEmail()).isNull();
    }

    @Test
    void cjpInexistente_da404() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        when(repo.findByCjp("nope")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> newSvc(repo, port).updateContact("nope", "a@b.uy", null))
                .isInstanceOf(ResourceNotFoundException.class);
    }
}
```

- [ ] **Step 2: Correr y verificar que no compila**

```bash
cd recetalia-api-rest && ./gradlew test --tests '*PharmaceuticalDirectorContactTest'
```

Esperado: **error de compilación** `cannot find symbol: method updateContact`.

- [ ] **Step 3: Declarar el método en la interfaz**

En `PharmaceuticalDirectorRegistrationService.java`, agregar el import y el método antes del `}` final:

```java
import com.recetalia.api.application.domain.model.Phone;
```

```java
  /**
   * Gestión carga o corrige el contacto del QF. A diferencia de `resolveForPharmacy`, acá SÍ
   * se sobrescribe: Gestión es la autoridad del dato, la farmacia sólo lo declara.
   */
  void updateContact(String cjp, String email, Phone phone) throws ResourceNotFoundException;
```

- [ ] **Step 4: Implementar el método**

En `PharmaceuticalDirectorRegistrationServiceImpl.java`, agregar el import:

```java
import com.recetalia.api.application.domain.model.Phone;
```

y agregar el método justo después de `reassignPassword` (línea 276), antes de `requireQf`:

```java
  /**
   * El formato del email se valida acá y no con @Email en el DTO a propósito:
   * GlobalExceptionHandler no traduce MethodArgumentNotValidException, así que un @Valid roto
   * vuelve como 500 "Error interno del servidor" y el operador no se entera de qué corregir.
   * BusinessRuleException sí tiene handler y llega con el texto puesto.
   */
  private static final java.util.regex.Pattern EMAIL_RE =
      java.util.regex.Pattern.compile("^[^@\\s]+@[^@\\s.]+\\.[^@\\s]+$");

  @Override
  @Transactional
  public void updateContact(String cjp, String email, Phone phone) throws ResourceNotFoundException {
    PharmaceuticalDirector qf = requireQf(cjp);
    String normalized = trimToNull(email);
    if (normalized != null && !EMAIL_RE.matcher(normalized).matches()) {
      throw new BusinessRuleException("El email \"" + normalized + "\" no tiene formato válido.");
    }
    qf.setEmail(normalized);
    qf.setPhone(phone);
    qfRepository.save(qf);
    logger.info("Contacto actualizado para el QF {}", qf.getCjp());
  }
```

- [ ] **Step 5: Correr los tests y verificar que pasan**

```bash
cd recetalia-api-rest && ./gradlew test --tests '*PharmaceuticalDirectorContactTest'
```

Esperado: **BUILD SUCCESSFUL**, 5 tests.

- [ ] **Step 6: Crear el DTO del body**

Crear `QfContactRequest.java`:

```java
package com.recetalia.api.application.dto.request;

import com.recetalia.api.application.domain.model.Phone;
import lombok.Data;

/**
 * Contacto que Gestión le carga o corrige a un QF.
 *
 * Sin anotaciones de Bean Validation a propósito: este proyecto no traduce
 * MethodArgumentNotValidException, así que un @Valid roto volvería como 500 sin decir qué
 * campo. El formato lo valida el servicio con BusinessRuleException, que sí tiene handler.
 */
@Data
public class QfContactRequest {
  private String email;
  private Phone phone;
}
```

- [ ] **Step 7: Exponer el endpoint**

En `PharmaceuticalDirectorAdminController.java`, agregar el import:

```java
import com.recetalia.api.application.dto.request.QfContactRequest;
```

y el método antes del `}` de cierre de la clase:

```java
  /**
   * Carga o corrige el contacto de un QF. POST y no PATCH para no depender de que PATCH esté
   * habilitado en la config de CORS: los dos endpoints hermanos ya son POST.
   *
   * Sin @Valid: ver el comentario de QfContactRequest.
   */
  @PostMapping("/{cjp}/contact")
  public ResponseEntity<GenericResponse<String>> updateContact(
      @PathVariable String cjp, @RequestBody QfContactRequest request)
      throws ResourceNotFoundException {
    service.updateContact(cjp, request.getEmail(), request.getPhone());
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, "Contacto actualizado"));
  }
```

No hay que tocar `SecurityConfiguration`: `"/api/pharmaceutical-directors/**"` ya exige `ROLE_ROLE_MANAGEMENT` (línea 86).

- [ ] **Step 8: Compilar todo y correr la suite entera**

```bash
cd recetalia-api-rest && ./gradlew build
```

Esperado: **BUILD SUCCESSFUL**.

- [ ] **Step 9: Commit**

```bash
cd recetalia-api-rest
git add src/main/java/com/recetalia/api/application/dto/request/QfContactRequest.java \
        src/main/java/com/recetalia/api/application/service/PharmaceuticalDirectorRegistrationService.java \
        src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java \
        src/main/java/com/recetalia/api/application/controller/PharmaceuticalDirectorAdminController.java \
        src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorContactTest.java
git commit -m "feat(qf): Gestion puede cargar y corregir el contacto del quimico

POST /api/pharmaceutical-directors/{cjp}/contact. Es la via para los 221 QF que
quedaron sin email tras la migracion.

POST y no PATCH para no depender de la config de CORS. El formato del email se
valida en el servicio con BusinessRuleException y no con @Email en el DTO:
MethodArgumentNotValidException no tiene handler y volveria como un 500 mudo."
```

---

## Task 4: Devolver el celular en la bandeja de Gestión (backend)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/response/PharmaceuticalDirectorReviewRow.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java:222`

- [ ] **Step 1: Agregar el campo al DTO**

En `PharmaceuticalDirectorReviewRow.java`, agregar el import y el campo debajo de `email`:

```java
import com.recetalia.api.application.domain.model.Phone;
```

```java
  /** Celular de contacto. NULL si nunca se declaró. */
  private Phone phone;
```

- [ ] **Step 2: Mapearlo**

En `PharmaceuticalDirectorRegistrationServiceImpl.toReviewRows`, después de `row.setEmail(qf.getEmail());` (línea 222):

```java
      row.setPhone(qf.getPhone());
```

- [ ] **Step 3: Compilar**

```bash
cd recetalia-api-rest && ./gradlew build
```

Esperado: **BUILD SUCCESSFUL**.

- [ ] **Step 4: Commit**

```bash
cd recetalia-api-rest
git add src/main/java/com/recetalia/api/application/dto/response/PharmaceuticalDirectorReviewRow.java \
        src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java
git commit -m "feat(qf): la bandeja de Gestion devuelve el celular del quimico"
```

---

## Task 5: Util de teléfono en `farmacias-recetalia-app`

Hoy el armado del objeto `Phone` está inline en `onSubmit` y, si el número no parsea, hace `console.error('Invalid phone number')` y **el usuario no ve nada**: aprieta "Registrar" y no pasa absolutamente nada. Al necesitar el mismo armado dos veces, se extrae a un util puro — mismo patrón que el `shared/utils/dispensation-cap.util.ts` que ya existe en este repo con su spec.

**Files:**
- Create: `farmacias-recetalia-app/src/app/shared/utils/phone-payload.util.ts`
- Test: `farmacias-recetalia-app/src/app/shared/utils/phone-payload.util.spec.ts`

- [ ] **Step 1: Escribir el test que falla**

Crear `phone-payload.util.spec.ts`:

```typescript
import { toPhonePayload } from './phone-payload.util';

describe('toPhonePayload', () => {
  it('arma el objeto que espera el backend a partir de un E.164 uruguayo', () => {
    expect(toPhonePayload('+59899123456')).toEqual({
      countryCode: 'UY',
      national: '99123456',
      international: '+598 99 123 456',
      type: 'mobile',
      validated: true,
    });
  });

  it('devuelve null si el numero no parsea, para que el llamador avise', () => {
    expect(toPhonePayload('123')).toBeNull();
    expect(toPhonePayload('')).toBeNull();
    expect(toPhonePayload(null)).toBeNull();
    expect(toPhonePayload(undefined)).toBeNull();
  });
});
```

- [ ] **Step 2: Correr y verificar que falla**

```bash
cd farmacias-recetalia-app && npm test -- --watch=false --browsers=ChromeHeadless
```

Esperado: **FAIL** — `Cannot find module './phone-payload.util'`.

- [ ] **Step 3: Implementar el util**

Crear `phone-payload.util.ts`:

```typescript
import { parsePhoneNumberFromString } from 'libphonenumber-js';

/** La forma exacta en que el backend guarda un teléfono (entidad `Phone`, JSON en columna text). */
export interface PhonePayload {
  countryCode: string;
  national: string;
  international: string;
  type: string;
  validated: boolean;
}

/**
 * `angular-phone-number-input` entrega un string E.164; el backend espera el objeto.
 *
 * Devuelve `null` en vez de tirar cuando el número no parsea: antes esto era un
 * `console.error` dentro de `onSubmit` y el formulario quedaba mudo — el usuario apretaba
 * "Registrar" y no pasaba nada, sin ningún mensaje.
 */
export function toPhonePayload(raw: string | null | undefined): PhonePayload | null {
  const parsed = parsePhoneNumberFromString((raw ?? '').toString().trim());
  if (!parsed) {
    return null;
  }
  return {
    countryCode: parsed.country || '',
    national: parsed.nationalNumber || '',
    international: parsed.formatInternational() || '',
    type: 'mobile',
    validated: true,
  };
}
```

- [ ] **Step 4: Correr y verificar que pasa**

```bash
cd farmacias-recetalia-app && npm test -- --watch=false --browsers=ChromeHeadless
```

Esperado: **SUCCESS**, incluidos los 2 tests nuevos.

- [ ] **Step 5: Commit**

```bash
cd farmacias-recetalia-app
git add src/app/shared/utils/phone-payload.util.ts src/app/shared/utils/phone-payload.util.spec.ts
git commit -m "refactor(register): extraer el armado del payload de telefono a un util

Hace falta dos veces (telefono de la farmacia y celular del QF). De paso devuelve
null en vez de un console.error mudo: hoy un numero invalido deja el boton de
registro sin efecto y sin mensaje."
```

---

## Task 6: Campos obligatorios en el registro de farmacia

**Files:**
- Modify: `farmacias-recetalia-app/src/app/model/request/pharmacy-request.ts`
- Modify: `farmacias-recetalia-app/src/app/pages/application/register/register.component.ts`
- Modify: `farmacias-recetalia-app/src/app/pages/application/register/register.component.html`

- [ ] **Step 1: Actualizar el DTO**

En `pharmacy-request.ts`, agregar el import y reemplazar el tipo inline de `phone`:

```typescript
import { PhonePayload } from '../../shared/utils/phone-payload.util';
```

Reemplazar el bloque:

```typescript
  phone: {
    countryCode: string;
    national: string;
    international: string;
    type: string;
    validated: boolean;
  };
```

por:

```typescript
  phone: PhonePayload;
```

y agregar, debajo de `managerEmail?: string;`:

```typescript
  managerPhone?: PhonePayload | null;
```

- [ ] **Step 2: Validadores del formulario**

En `register.component.ts`, reemplazar la línea 73:

```typescript
      managerEmail: [''],
```

por:

```typescript
      managerEmail: ['', [Validators.required, Validators.email]],
      managerPhone: ['', Validators.required],
```

- [ ] **Step 3: Dejar de borrar el contacto al cambiar de estado**

Los campos ahora se piden siempre, así que el reset por estado ya no aplica. Borrar las líneas 164-168 de `register.component.ts`:

```typescript
    // El email del QF solo tiene sentido para un QF nuevo. Si el estado cambió (p.ej. se
    // corrigió el CJP y resultó existir), no arrastrar lo que se había tipeado.
    if (state !== 'new') {
      this.registerForm.get('managerEmail')?.reset('');
    }
```

Dejar en su lugar este comentario, dentro de `applyQfState`, justo antes del `}` de cierre del método:

```typescript
    // El contacto del QF NO se resetea ni se saca de required al cambiar de estado: se pide
    // siempre. Si el QF ya existía y ya tenía contacto, el backend descarta lo que se tipee
    // (fill-if-empty); es deliberado — la farmacia declara, no corrige.
```

- [ ] **Step 4: Usar el util y mandar el contacto**

Agregar el import en `register.component.ts`:

```typescript
import { toPhonePayload } from '../../../shared/utils/phone-payload.util';
```

y borrar el import ahora sin uso:

```typescript
import { parsePhoneNumberFromString } from 'libphonenumber-js';
```

Reemplazar todo el bloque de las líneas 188-247 (desde el comentario `// The formValue.phone will have...` hasta el `}` que cierra el `else { console.error('Invalid phone number'); }`) por:

```typescript
      const phone = toPhonePayload(formValue.phone);
      if (!phone) {
        this.messageRegister = 'El teléfono de la farmacia no es un número válido.';
        this.showDialog();
        return;
      }

      const managerPhone = toPhonePayload(formValue.managerPhone);
      if (!managerPhone) {
        this.messageRegister = 'El celular del Químico Farmacéutico no es un número válido.';
        this.showDialog();
        return;
      }

      const newPharmacy: PharmacyRequest = {
        name: formValue.name,
        businessName: formValue.businessName,
        rut: formValue.rut,
        email: formValue.email,
        password: encryptedPassword,
        phone: phone,
        managerName: formValue.managerName,
        managerLastname: formValue.managerLastname,
        managerCJP: formValue.managerCJP,
        managerDocument: {
          number: formValue.managerDocumentNumber,
          type: formValue.managerDocumentType
        },
        // El QF nace sin usuario de login: lo habilita Gestión y le asigna la clave.
        // El alta pública sólo deja su contacto, para que Gestión pueda ubicarlo.
        managerEmail: formValue.managerEmail?.trim() || null,
        managerPhone: managerPhone,
        addressCountryId: formValue.region?.id,
        addressLocalityId: formValue.locality?.id,
        addressStreet: formValue.addressStreet,
        addressNumber: formValue.addressNumber,
        addressComments: formValue.addressComments,
        status: 'INACTIVE',
        info: dynamicInfo,
        franchiseId: formValue.franchise?.id,
      };

      this.pharmacyService.create(newPharmacy).subscribe({
        next: () => {
          this.messageRegister = 'Farmacia creada con éxito.';
          this.showDialog();
          this.registerForm.reset();
        },
        error: (error) => {
          this.messageRegister = error?.message || 'No se pudo completar el registro. Intentá nuevamente.';
          this.showDialog();
        }
      });
```

- [ ] **Step 5: Mover y renombrar los campos en el HTML**

En `register.component.html`, reemplazar el bloque de las líneas 239-244:

```html
            <!-- Contacto del QF nuevo. El acceso no se define acá: lo habilita Gestión. -->
            <div class="form-group" *ngIf="qfState === 'new'">
              <label for="managerEmail">Email del Químico Farmacéutico (opcional)</label>
              <input type="email" id="managerEmail" class="form-control" formControlName="managerEmail"
                     placeholder="Para que Recetalia pueda contactarlo" />
            </div>
```

por:

```html
            <!-- Contacto del QF: se pide SIEMPRE, exista o no el CJP. Es el dato con el que
                 Gestión lo ubica para pasarle la clave. El acceso no se define acá. -->
            <div class="form-group">
              <label for="managerEmail">Email del Químico Farmacéutico</label>
              <input type="email" id="managerEmail" class="form-control" formControlName="managerEmail"
                     placeholder="Para que Recetalia pueda contactarlo" />
              <div *ngIf="registerForm.get('managerEmail')?.invalid && registerForm.get('managerEmail')?.touched"
                class="text-danger">
                <span *ngIf="registerForm.get('managerEmail')?.errors?.['required']">
                  El email del Químico Farmacéutico es requerido.
                </span>
                <span *ngIf="registerForm.get('managerEmail')?.errors?.['email']">
                  El email no tiene un formato válido.
                </span>
              </div>
            </div>

            <div class="form-group">
              <label for="managerPhone">Celular del QF</label>
              <angular-phone-number-input formControlName="managerPhone" [defaultCountry]="'UY'"
                [preferredCountries]="['UY', 'AR', 'CO', 'PE', 'MX']"
                [error]="registerForm.get('managerPhone')?.touched && registerForm.get('managerPhone')?.invalid">
              </angular-phone-number-input>
              <div *ngIf="registerForm.get('managerPhone')?.invalid && registerForm.get('managerPhone')?.touched"
                class="text-danger">
                El celular del Químico Farmacéutico es requerido.
              </div>
            </div>
```

- [ ] **Step 6: Renombrar el label de Datos de acceso**

En `register.component.html` línea 262, reemplazar:

```html
              <label for="email">Email</label>
```

por:

```html
              <label for="email">Email de la Farmacia</label>
```

- [ ] **Step 7: Compilar y correr los tests**

```bash
cd farmacias-recetalia-app && npm run build && npm test -- --watch=false --browsers=ChromeHeadless
```

Esperado: build **OK** (sin errores de `strictTemplates`) y tests **SUCCESS**.

- [ ] **Step 8: Commit**

```bash
cd farmacias-recetalia-app
git add src/app/model/request/pharmacy-request.ts \
        src/app/pages/application/register/register.component.ts \
        src/app/pages/application/register/register.component.html
git commit -m "feat(register): email y celular del QF obligatorios; email de la farmacia

- El email del QF deja de ser opcional y se pide siempre, tambien cuando el CJP
  ya existe: es el dato con el que Gestion ubica al quimico para darle la clave.
- Campo nuevo 'Celular del QF' en Direccion tecnica.
- 'Email' pasa a 'Email de la Farmacia' en Datos de acceso, que es de quien es."
```

---

## Task 7: `updateContact` en el servicio de Gestión

**Files:**
- Modify: `gestion-recetadigital-app/src/app/model/response/pharmaceutical-director-review-row.ts`
- Modify: `gestion-recetadigital-app/src/app/services/pharmaceutical-director.service.ts`
- Test: `gestion-recetadigital-app/src/app/services/pharmaceutical-director.service.spec.ts`

- [ ] **Step 1: Escribir el test que falla**

Crear `pharmaceutical-director.service.spec.ts`:

```typescript
import { TestBed } from '@angular/core/testing';
import { HttpClientTestingModule, HttpTestingController } from '@angular/common/http/testing';
import { PharmaceuticalDirectorService } from './pharmaceutical-director.service';
import { environment } from '../../environments/environment';

describe('PharmaceuticalDirectorService', () => {
  let service: PharmaceuticalDirectorService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [HttpClientTestingModule],
      providers: [PharmaceuticalDirectorService],
    });
    service = TestBed.inject(PharmaceuticalDirectorService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('POSTea el contacto al endpoint del CJP y desenvuelve la respuesta', () => {
    let ok: boolean | undefined;
    const phone = {
      countryCode: 'UY', national: '99123456',
      international: '+598 99 123 456', type: 'mobile', validated: true,
    };
    service.updateContact('099893', 'ana@qf.uy', phone).subscribe(r => (ok = r));

    const req = httpMock.expectOne(
      `${environment.apiUrl}/pharmaceutical-directors/099893/contact`);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({ email: 'ana@qf.uy', phone });
    req.flush({ status: 'SUCCESS', answer: 'Contacto actualizado', serverDateTime: 'x' });

    expect(ok).toBeTrue();
  });

  it('escapa el CJP en la URL', () => {
    service.updateContact('a/b', null, null).subscribe();
    const req = httpMock.expectOne(
      `${environment.apiUrl}/pharmaceutical-directors/a%2Fb/contact`);
    req.flush({ status: 'SUCCESS', answer: 'ok', serverDateTime: 'x' });
  });
});
```

- [ ] **Step 2: Correr y verificar que falla**

```bash
cd gestion-recetadigital-app && npm test -- --watch=false --browsers=ChromeHeadless
```

Esperado: **FAIL** — `service.updateContact is not a function`.

- [ ] **Step 3: Agregar el tipo `Phone` al modelo**

En `pharmaceutical-director-review-row.ts`, agregar arriba del `PharmaceuticalDirectorReviewRow`:

```typescript
/** Espejo de la entidad `Phone` del backend (JSON guardado en una columna text). */
export interface Phone {
  countryCode: string;
  national: string;
  international: string;
  type: string;
  validated: boolean;
}
```

y dentro de la interfaz `PharmaceuticalDirectorReviewRow`, debajo de `email?: string | null;`:

```typescript
  phone?: Phone | null;
```

- [ ] **Step 4: Agregar el método al servicio**

En `pharmaceutical-director.service.ts`, agregar `Phone` al import existente:

```typescript
import { PharmaceuticalDirectorReviewRow, Phone } from '../model/response/pharmaceutical-director-review-row';
```

y agregar el método antes del `}` de cierre de la clase:

```typescript
  /**
   * Carga o corrige el contacto del QF. Es la vía para los ~221 habilitados que quedaron sin
   * email tras la migración: a ellos nunca se les pidió en ningún formulario.
   *
   * POST y no PATCH porque el backend expone POST — ver el comentario del controller.
   */
  updateContact(cjp: string, email: string | null, phone: Phone | null): Observable<boolean> {
    const url = `${this.baseUrl}/${encodeURIComponent(cjp)}/contact`;
    return this.http.post<ApiResponse<unknown>>(url, { email, phone }).pipe(
      map(response => {
        if (response.status === 'SUCCESS') {
          return true;
        }
        throw new Error('API responded with error: ' + response.applicationProvider);
      }),
      catchError(error => {
        console.error('Failed to update pharmaceutical director contact:', error);
        const msg = error?.error?.answer || error?.message || 'No se pudo guardar el contacto.';
        return throwError(() => new Error(msg));
      })
    );
  }
```

- [ ] **Step 5: Correr y verificar que pasa**

```bash
cd gestion-recetadigital-app && npm test -- --watch=false --browsers=ChromeHeadless
```

Esperado: **SUCCESS**, incluidos los 2 tests nuevos.

- [ ] **Step 6: Commit**

```bash
cd gestion-recetadigital-app
git add src/app/model/response/pharmaceutical-director-review-row.ts \
        src/app/services/pharmaceutical-director.service.ts \
        src/app/services/pharmaceutical-director.service.spec.ts
git commit -m "feat(qf): servicio para cargar y corregir el contacto del quimico"
```

---

## Task 8: Modal "Editar contacto" en la bandeja de Gestión

**Files:**
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/pharmaceutical-director/pharmaceutical-director-list/pharmaceutical-director-list.component.ts`
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/pharmaceutical-director/pharmaceutical-director-list/pharmaceutical-director-list.component.html`

- [ ] **Step 1: Estado y handlers en el componente**

En el `.component.ts`, agregar el import de `Phone`:

```typescript
import {
  PharmaceuticalDirectorReviewRow,
  PharmacyBrief,
  Phone
} from '../../../../../model/response/pharmaceutical-director-review-row';
```

Agregar el estado debajo del bloque del modal de clave (después de `saving = false;`, línea 51):

```typescript
  // Modal de contacto: la vía para los ~221 habilitados que quedaron sin email.
  contactDialogVisible = false;
  contactTarget: PharmaceuticalDirectorReviewRow | null = null;
  contactEmail = '';
  contactPhone = '';
  contactError = '';
  savingContact = false;
```

Agregar los métodos antes del `}` de cierre de la clase:

```typescript
  openContactDialog(row: PharmaceuticalDirectorReviewRow): void {
    this.contactTarget = row;
    this.contactEmail = row.email || '';
    this.contactPhone = row.phone?.international || '';
    this.contactError = '';
    this.savingContact = false;
    this.validatedSuccess = '';
    this.contactDialogVisible = true;
  }

  closeContactDialog(): void {
    this.contactDialogVisible = false;
    this.contactTarget = null;
    this.contactEmail = '';
    this.contactPhone = '';
    this.contactError = '';
  }

  /**
   * El celular viaja como el mismo objeto `Phone` que arma el registro de farmacia, para que
   * las dos vías guarden la misma forma. Se manda `null` —y no un objeto vacío— cuando el
   * campo queda en blanco: el converter del backend distingue NULL de "{}".
   */
  confirmContact(): void {
    const row = this.contactTarget;
    if (!row) { return; }

    const email = (this.contactEmail || '').trim();
    const raw = (this.contactPhone || '').trim();
    let phone: Phone | null = null;
    if (raw) {
      const parsed = parsePhoneNumberFromString(raw);
      if (!parsed) {
        this.contactError = 'El celular no es un número válido. Incluí el código de país (+598…).';
        return;
      }
      phone = {
        countryCode: parsed.country || '',
        national: parsed.nationalNumber || '',
        international: parsed.formatInternational() || '',
        type: 'mobile',
        validated: true,
      };
    }

    this.savingContact = true;
    this.contactError = '';

    this.service.updateContact(row.cjp, email || null, phone).subscribe({
      next: () => this.zone.run(() => {
        this.savingContact = false;
        this.closeContactDialog();
        this.validatedSuccess = `Contacto actualizado para el químico ${row.cjp}.`;
        this.loadValidated();
      }),
      error: (err) => this.zone.run(() => {
        this.savingContact = false;
        this.contactError = err?.message || 'No se pudo guardar el contacto.';
      }),
    });
  }
```

Agregar el import de `libphonenumber-js` arriba del archivo:

```typescript
import { parsePhoneNumberFromString } from 'libphonenumber-js';
```

- [ ] **Step 2: Columna Celular y botón en la tabla**

En el `.component.html`, en el header de la tabla de habilitados, agregar la columna después de `<th>Email</th>` (línea 185):

```html
            <th>Celular</th>
```

y ensanchar la última columna de acciones — reemplazar la línea 188:

```html
            <th style="width:11rem"></th>
```

por:

```html
            <th style="width:17rem"></th>
```

En el body, agregar la celda después del bloque del email (línea 199):

```html
            <td>
              <span *ngIf="row.phone?.international; else sinCelular">
                {{ row.phone?.international }}
              </span>
              <ng-template #sinCelular><span class="text-muted">—</span></ng-template>
            </td>
```

Reemplazar la celda de acciones (líneas 212-217) por:

```html
            <td class="text-nowrap">
              <button type="button" class="btn btn-sm btn-outline-secondary me-1"
                (click)="openContactDialog(row)">
                Editar contacto
              </button>
              <button type="button" class="btn btn-sm btn-outline-primary"
                (click)="openPasswordDialog(row, 'reassign')">
                Reasignar clave
              </button>
            </td>
```

Y actualizar el `colspan` del `emptymessage` (línea 223), que ahora tiene una columna más:

```html
            <td colspan="7" class="text-center text-muted py-4">
```

- [ ] **Step 3: Agregar el modal**

Al final del `.component.html`, después del `</p-dialog>` del modal de clave (línea 274):

```html
<!--
  Modal de contacto. Existe porque los ~221 QF habilitados por la migración nunca pasaron por
  un formulario que les pidiera email: no hay otra vía para cargárselo.
-->
<p-dialog [(visible)]="contactDialogVisible" header="Editar contacto del químico"
  [modal]="true" [style]="{ width: '32rem' }" [draggable]="false" [resizable]="false"
  (onHide)="closeContactDialog()">

  <div *ngIf="contactTarget">
    <p class="mb-3">
      <strong>{{ contactTarget.name }} {{ contactTarget.lastname }}</strong><br />
      <span class="text-muted">CJP {{ contactTarget.cjp }}</span>
    </p>

    <div class="mb-2">
      <label for="qf-contact-email" class="form-label">Email</label>
      <input id="qf-contact-email" type="email" class="form-control" autocomplete="off"
        [(ngModel)]="contactEmail" [disabled]="savingContact"
        placeholder="quimico@ejemplo.com" />
    </div>

    <div class="mb-2">
      <label for="qf-contact-phone" class="form-label">Celular</label>
      <input id="qf-contact-phone" type="text" class="form-control" autocomplete="off"
        [(ngModel)]="contactPhone" [disabled]="savingContact"
        placeholder="+598 99 123 456" />
      <small class="text-muted">Con código de país. Dejalo vacío para borrarlo.</small>
    </div>

    <div *ngIf="contactError" class="alert alert-danger py-2 mb-0">{{ contactError }}</div>
  </div>

  <ng-template pTemplate="footer">
    <button type="button" class="btn btn-outline-secondary" (click)="closeContactDialog()"
      [disabled]="savingContact">
      Cancelar
    </button>
    <button type="button" class="btn btn-primary" (click)="confirmContact()"
      [disabled]="savingContact">
      Guardar
    </button>
  </ng-template>
</p-dialog>
```

- [ ] **Step 4: Compilar y correr los tests**

```bash
cd gestion-recetadigital-app && npm run build && npm test -- --watch=false --browsers=ChromeHeadless
```

Esperado: build **OK** y tests **SUCCESS**.

- [ ] **Step 5: Commit**

```bash
cd gestion-recetadigital-app
git add src/app/pages/application/home/pharmaceutical-director/pharmaceutical-director-list/
git commit -m "feat(qf): editar el contacto del quimico desde la bandeja de habilitados

Los ~221 QF que quedaron habilitados por la migracion nunca pasaron por un
formulario que les pidiera email: sin esto no hay forma de cargarselo."
```

---

## Task 9: Corregir la spec que quedó desactualizada

`doc/plans/2026-08-02-qf-validacion-gestion-design.md:26` afirma que el email es opcional y que el teléfono se descarta por costo. Las dos cosas dejan de ser ciertas con este cambio.

**Files:**
- Modify: `doc/plans/2026-08-02-qf-validacion-gestion-design.md:26`

- [ ] **Step 1: Corregir la decisión en el lugar**

Reemplazar la fila de la tabla de decisiones que dice `Email del QF: opcional` por:

```markdown
| Email del QF: opcional | Pablo | ~~Si está, Gestión lo contacta directo; si no, vía la farmacia. **Only email, no teléfono**: sumarlo obliga a tocar el tipo embebido y el componente de teléfono del front — desproporcionado para un dato de contacto opcional~~ **REVERTIDO el 2026-08-18 (release 2.3.0):** email y celular pasan a ser obligatorios en el registro. El costo que motivaba el descarte no existía: la columna `pharmaceutical_director.phone` ya estaba creada y vacía, así que el cambio no necesitó migración. Ver [2026-08-18-qf-contacto-obligatorio-plan.md](2026-08-18-qf-contacto-obligatorio-plan.md). |
```

- [ ] **Step 2: NO hay commit posible — leer esto**

⚠️ **Verificado el 2026-08-18: la raíz del workspace no es un repo git** (`git rev-parse` tira `not a git repository`). Todo `doc/` —los ~40 planes y specs, incluido este archivo— **está fuera de control de versiones y vive sólo en la Mac de Pablo.** No hay nada que commitear en esta tarea.

No inventar un `git init` acá: es una decisión de Pablo, no del plan. Dejar la corrección escrita en el archivo y **avisarlo al cerrar la tarea**, para que quede la opción de versionar `doc/` o de mover estos documentos dentro de alguno de los repos.

---

## Task 10: Deploy a PRE (`.98`) y verificación

**Procedimiento verificado** (ver la memoria `infra-map`): rsync desde la Mac → build **serial** en el server → `up -d`. En `.98` el tag es `:dev` y `FRONTEND_CONFIGURATION=preprod`.

- [ ] **Step 1: Rsync de los tres repos**

```bash
cd /Users/pablo/iwtg/recetalia-workspace
for app in recetalia-api-rest farmacias-recetalia-app gestion-recetadigital-app; do
  rsync -az --delete \
    --exclude '.git' --exclude 'node_modules' --exclude 'dist' \
    --exclude '.angular' --exclude 'build' --exclude '.gradle' \
    "$app/" "root@138.197.150.98:/opt/recetalia/$app/"
done
```

- [ ] **Step 2: Build serial**

Serial y no en paralelo: los frontends en paralelo agotan los 8 GB de RAM del server.

```bash
ssh root@138.197.150.98 'cd /opt/recetalia/deploy-recetalia && \
  for s in recetalia-api-rest farmacias-recetalia-app gestion-recetadigital-app; do \
    echo "=== build $s"; docker compose build "$s" || exit 1; \
  done'
```

Esperado: tres builds **OK**, sin OOM.

- [ ] **Step 3: Levantar**

```bash
ssh root@138.197.150.98 'cd /opt/recetalia/deploy-recetalia && \
  docker compose up -d recetalia-api-rest farmacias-recetalia-app gestion-recetadigital-app && \
  docker compose ps'
```

- [ ] **Step 4: Verificar que corre el código nuevo (marcador, no fecha)**

Una fecha de build sólo prueba que se construyó después del commit, no desde él. El marcador tiene que dar **0 antes y >0 después**; y hay que correr **siempre un control positivo**, porque un grep roto también da 0.

```bash
ssh root@138.197.150.98 '
cat > /tmp/scan.py <<PY
import zipfile, sys
jar, markers = sys.argv[1], sys.argv[2].split(",")
z = zipfile.ZipFile(jar)
blob = b"".join(z.read(n) for n in z.namelist()
                if n.startswith("BOOT-INF/classes/") and n.endswith(".class"))
for m in markers:
    print("  %-25s hits=%d" % (m, blob.count(m.encode())))
PY
docker cp recetalia-api-rest:/app/app.jar /tmp/api.jar
python3 /tmp/scan.py /tmp/api.jar "Controller,updateContact,QfContactRequest"
rm -f /tmp/api.jar
echo "--- gestion (marcador: openContactDialog):"
docker exec gestion-recetadigital-app sh -c "grep -ro openContactDialog /app/dist | wc -l"
echo "--- farmacias (marcador: managerPhone):"
docker exec farmacias-recetalia-app sh -c "grep -ro managerPhone /app/dist | wc -l"'
```

⚠️ **Ese script sirve en el `.217` pero NO en el `.98`.** Corregido tras correrlo el 2026-08-18:

- **El `.98` no tiene `python3`** (sí `python` 2, `perl` y `jar`). Ahí el scan del jar va con `jar`:
  ```bash
  ssh root@138.197.150.98 '
  rm -rf /tmp/jarscan && mkdir -p /tmp/jarscan && cd /tmp/jarscan
  docker cp recetalia-api-rest:/app/app.jar /tmp/jarscan/app.jar >/dev/null 2>&1
  jar xf app.jar BOOT-INF/classes >/dev/null 2>&1
  for m in Controller updateContact QfContactRequest blankToNull; do
    printf "  %-20s hits=%s\n" "$m" "$(grep -rao "$m" BOOT-INF/classes | wc -l | tr -d " ")"
  done; cd / && rm -rf /tmp/jarscan'
  ```
- **`farmacias-recetalia-app` NO tiene `/app/dist`**: es imagen Nginx estática y su build vive en `/usr/share/nginx/html`. Gestión sí es SSR y usa `/app/dist`. Grepear la ruta equivocada devuelve `No such file or directory`, que a ojo se confunde con "0 hits".

Valores obtenidos en PRE el 2026-08-18 (todos con su control positivo en verde):

| dónde | marcador | hits |
|---|---|---|
| API | `Controller` (control positivo) | 77 |
| API | `updateContact` / `QfContactRequest` / `blankToNull` | 3 / 8 / 4 |
| gestión | `openPasswordDialog` (control positivo) | 6 |
| gestión | `openContactDialog` / `updateContact` | 4 / 4 |
| farmacias | `managerEmail` (control positivo) | 13 |
| farmacias | `managerPhone` / "Email de la Farmacia" / "Celular del QF" | 12 / 2 / 2 |

⚠️ `unzip` **no existe** en ningún contenedor ni host. Un `grep` directo sobre el `.jar` devuelve 0 siempre (ZIP deflateado) y se lee igual que "no está deployado".

- [ ] **Step 5: Prueba manual en PRE**

1. `https://farmaciaspre.recetalia.com/register` → la sección **Dirección técnica** muestra "Email del Químico Farmacéutico" (sin "(opcional)") y "Celular del QF". Dejar los dos vacíos ⇒ el botón de registro no envía y aparecen los mensajes en rojo.
2. Escribir un CJPPU que **ya exista** ⇒ los dos campos siguen visibles y obligatorios.
3. En **Datos de acceso** el label dice "Email de la Farmacia".
4. Completar un alta y verificar en la base:
   ```bash
   ssh root@138.197.150.98 'docker exec recetalia-mysql sh -c "mysql -uroot -p\$MYSQL_ROOT_PASSWORD recetali_receta -e \"SELECT cjp, email, phone FROM pharmaceutical_director WHERE cjp = <CJP_DE_PRUEBA>\\G\""'
   ```
   Esperado: `email` cargado y `phone` con el JSON `{"countryCode":"UY",...}`.
5. `https://gestionpre.recetalia.com/pharmaceutical-directors` → tab **Habilitados**: columna **Celular** nueva y botón **Editar contacto**. Cargarle email y celular a un QF, guardar, y confirmar que la fila los muestra tras el refresco.
6. Probar un email inválido (`asdf`) ⇒ mensaje **"no tiene formato válido"**, no un 500 mudo.

- [ ] **Step 6: Anotar el resultado**

Si algo de la prueba manual falla, corregir y **volver a la Tarea correspondiente** antes de seguir. No deployar a PROD con la verificación en rojo.

---

## Task 12: Ordenar la tabla de QF (agregada 2026-08-20, ya hecha)

Pablo reportó que el orden de la tabla no se entendía: creó un QF y apareció a mitad de tabla.

**Causa:** el backend devuelve `ORDER BY cjp ASC` (`findAllByValidatedAtIsNotNullOrderByCjpAsc`) y `cjp` es `varchar(150)`, así que MySQL ordena **como texto**: `120388` cae antes que `12065` porque en la 4ª posición `3` < `6`. Ninguna de las 3 solapas tenía `pSortableColumn`.

**Decisión de Pablo:** cabezales ordenables + default **Nombre A→Z, case-insensitive**.

⚠️ **El CJP se sigue ordenando como TEXTO, a propósito.** Medido en PRE sobre 224 filas: **2 CJP no son sólo dígitos y 2 empiezan con cero** (`049572409589`). Un orden numérico les come el cero y descoloca los no numéricos. No "mejorar" esto a un sort numérico.

Hecho (commits `40996e3` + `82ea2a3`, sólo `gestion-recetadigital-app`):
- `shared/utils/sort-key.util.ts` + spec (3 tests): `sortKey(...parts)` normaliza a minúscula. Hace falta porque el nombre sale de dos campos (`name`+`lastname`) y las farmacias de un método, así que no hay propiedad simple contra la cual ordenar. Los datos traen MAYÚSCULA y minúscula mezcladas: comparar crudo agrupaba todos los MAYÚSCULA primero.
- `withSortKeys()` en los tres loaders; claves en un **tipo aparte y requerido** (`PharmaceuticalDirectorRow`), no opcionales dentro del DTO de respuesta — siendo opcionales, un `this.rows = data` suelto compilaba igual y el orden volvía al del backend sin error ni test rojo.
- `applyValidatedFilter` ahora copia el array (`[...this.validatedRows]`): el `p-table` ordena **in place** y con la misma referencia le reordenaba también la fuente.

Verificado leyendo PrimeNG 17 (`primeng-table.mjs:1172-1185`): el sort inlinea `localeCompare`, así que los acentos salen bien; y `resolveFieldData` corta en `null`, así que las filas sin celular o sin fecha no rompen — quedan agrupadas arriba en ascendente. El orden elegido por el usuario **sobrevive** al filtro de texto y a `loadValidated()`, porque `ngOnChanges` sobre `value` re-dispara `sortSingle()`.

---

## Task 13: Médico sin prestador no veía sus recetas (agregada 2026-08-20, ya hecha)

Bug de **producción** reportado por Pablo: una médica abría `medicos.recetalia.com/prescriptions` y veía la tabla vacía.

**No era una lista vacía: la API devolvía 404** `MedicalProvider not visible for this user :: null`. Reproducido en PROD y en PRE con la misma cuenta.

**Causa raíz:** `MedicalProviderScopeGuard.scopeForCurrentUser` (introducido en 2.2.0, commit `b636261`, hardening del pentest) denegaba a todo `ROLE_MEDIC`/`ROLE_COSMETOLOGO` cuyo `medic.medicalProviderId` fuera NULL. Antes de 2.2.0, `PrescriptionServiceImpl` trataba un prestador nulo como "no filtrar por prestador" y el listado andaba.

**Por qué la denegación estaba mal.** El alcance de un médico es el par `(prestador, médico)` y su `medicId` **siempre** está — es su PK. Un prestador nulo no abre la consulta a la plataforma entera: la abre a "todas las de ÉL". Verificado en la query `findPrescriptionsByFilters`: `LEFT JOIN medical_provider mp` (el médico sin prestador no queda excluido por el join) + `AND (:medicalProviderId IS NULL OR TRIM(:medicalProviderId) = '' OR mp.id = :medicalProviderId)`. El recorte real lo hace `AND (:medicId IS NULL OR p.medicId = :medicId)`.

⚠️ El comportamiento viejo **estaba fijado por un test deliberado** (`medicoSinPrestador_noVeNada`, con el comentario "no cae en 'sin filtro' = todas las recetas"). Se reemplazó por tres: ve las suyas; sigue sin ver las de otro médico aunque lo pida en la URL; y **se sigue denegando al médico sin `medicId`**, que ése sí sería un alcance sin recorte.

**Impacto medido (PROD, 2026-08-20):** 144 de 479 médicos sin prestador, **40 de ellos con recetas**. En PRE, 142.

**Verificación en PRE tras el fix** (commit `a3ebf06`): la cuenta que fallaba devuelve **200 con 56 recetas** — exactamente las 56 que tiene en la base — y el Excel volvió a funcionar. Prueba de no-fuga: la plataforma tiene 7.438 recetas; pidiendo explícitamente el `medicId` de otra médica (391 recetas) y un `medicalProviderId` arbitrario, **sigue devolviendo sus 56**.

## Task 14: El listado se comía el error de la API (agregada 2026-08-20, ya hecha)

Lo que hizo que el bug anterior pasara **ocho días en producción sin reportarse**: el `subscribe` del listado sólo hacía `console.error`, así que un 404 se veía idéntico a "no tenés recetas".

Hecho en `medics-recetalia-app` (rama **`fix/listado-recetas-error-visible`**, commit `2f9d031`): el error se muestra en pantalla, y la tabla gana un `emptymessage` que distingue "no hay recetas para estos filtros" de "no se pudo cargar". `colspan="4"` — son 4 columnas visibles (Código, Paciente, Medicamento, Estado); las de Médico y Vencimiento están comentadas en el HTML.

Baseline de tests de ese repo, medida antes y después: **14 FAILED / 5 SUCCESS**, sin cambios.

---

## Task 11: Tag 2.3.0 y deploy a PROD (`.217`)

⚠️ **Actualizado 2026-08-20: son CUATRO repos, no tres.** Se sumó `medics-recetalia-app`, y su rama se llama distinto:

| Repo | Rama |
|---|---|
| `recetalia-api-rest` | `feat/qf-contacto-obligatorio` |
| `farmacias-recetalia-app` | `feat/qf-contacto-obligatorio` |
| `gestion-recetadigital-app` | `feat/qf-contacto-obligatorio` |
| `medics-recetalia-app` | **`fix/listado-recetas-error-visible`** |

⚠️ **No arrancar esta tarea sin el OK explícito de Pablo** — regla del workspace: nada se mergea ni se publica sin confirmación.

- [ ] **Step 1: Mergear a `2.x.y` y fast-forward de `main`**

Convención del workspace: merge a `2.x.y`, fast-forward de `main`, tag semver en cada repo tocado.

```bash
cd /Users/pablo/iwtg/recetalia-workspace
for app in recetalia-api-rest farmacias-recetalia-app gestion-recetadigital-app; do
  echo "=== $app"; git -C "$app" status --short; git -C "$app" log --oneline -3
done
```

Revisar que sólo estén los commits de este plan, y recién ahí mergear.

- [ ] **Step 2: Tag 2.3.0 en los tres repos**

```bash
cd /Users/pablo/iwtg/recetalia-workspace
for app in recetalia-api-rest farmacias-recetalia-app gestion-recetadigital-app; do
  git -C "$app" tag -a 2.3.0 -m "release 2.3.0 — contacto obligatorio del Quimico Farmaceutico"
  git -C "$app" push origin 2.x.y --follow-tags
done
```

`gestion-recetadigital-app` está en `main`, no en `2.x.y`: para ese repo el push es `git -C gestion-recetadigital-app push origin main --follow-tags`.

- [ ] **Step 3: Rsync a PROD**

```bash
cd /Users/pablo/iwtg/recetalia-workspace
for app in recetalia-api-rest farmacias-recetalia-app gestion-recetadigital-app; do
  rsync -az --delete \
    --exclude '.git' --exclude 'node_modules' --exclude 'dist' \
    --exclude '.angular' --exclude 'build' --exclude '.gradle' \
    "$app/" "root@159.203.26.217:/opt/recetalia/$app/"
done
```

- [ ] **Step 4: Build serial y levantar**

En `.217` el tag es `:latest` y `FRONTEND_CONFIGURATION=production` (hornea `api.recetalia.com`). Eso ya está en `/opt/recetalia/deploy-recetalia/.env` del server — **no** usar el `.env` local del repo, que dice `preprod`+`latest`, combinación que no corresponde a ningún server.

```bash
ssh root@159.203.26.217 'cd /opt/recetalia/deploy-recetalia && \
  for s in recetalia-api-rest farmacias-recetalia-app gestion-recetadigital-app; do \
    echo "=== build $s"; docker compose build "$s" || exit 1; \
  done && \
  docker compose up -d recetalia-api-rest farmacias-recetalia-app gestion-recetadigital-app && \
  docker compose ps'
```

- [ ] **Step 5: Verificar con los mismos marcadores**

Correr el bloque del Step 4 de la Tarea 10 apuntando a `159.203.26.217`. Mismos valores esperados, mismo control positivo.

- [ ] **Step 6: Smoke test de los dominios**

```bash
for h in farmacias gestion qf medicos prestadores; do
  printf "%-12s -> " "$h.recetalia.com"
  curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 20 "https://$h.recetalia.com/"
done
```

Esperado: **HTTP 200** en los cinco.

- [ ] **Step 7: Prueba manual en PROD**

Repetir los puntos 1, 3 y 5 del Step 5 de la Tarea 10 contra `farmacias.recetalia.com` y `gestion.recetalia.com`. **No** completar un alta de farmacia real en PROD: alcanza con verificar que los campos son obligatorios y que el modal de contacto guarda sobre un QF real.

---

## Notas de comportamiento conocidas

- **Si el QF ya existe y ya tiene contacto, lo que tipee la farmacia se descarta en silencio.** Es la decisión tomada (*fill-if-empty*): la farmacia declara, no corrige. El front no puede avisarlo porque el lookup público (`PharmaceuticalDirectorLookupResponse`) sólo devuelve nombre y apellido, a propósito. Si molesta en uso real, la salida es sumar `hasEmail`/`hasPhone` (booleanos, sin filtrar el dato) a ese lookup — no está en este plan.
- **Los 221 QF sin email no se completan solos.** Se van llenando a medida que las farmacias los declaren de nuevo, y a mano desde el modal de Gestión. No hay carga masiva en este plan.
- **El email del QF sigue sin usarse para mandar la clave**: la clave la asigna Gestión y se la pasa por fuera del sistema. El contacto es para ubicarlo, no para automatizar el envío.
