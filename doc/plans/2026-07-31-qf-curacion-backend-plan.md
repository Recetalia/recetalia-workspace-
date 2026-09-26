# QF — Curación de CJPs colisionados — Plan 2a: Backend

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que un QF marcado `NEEDS_REVIEW` se destrabe solo cuando se corrigen los CJPs de sus farmacias, y que Gestión pueda ver cuáles faltan curar.

**Architecture:** Un método `recomputeStatus(cjp)` en el servicio de registro del QF, invocado desde el guardado de farmacia, que re-evalúa la misma condición que usó el backfill (¿este CJP figura con más de un titular?). Más un endpoint de listado para la bandeja de Gestión.

**Tech Stack:** Java 21, Spring Boot 3.3.0, Spring Data JPA / Hibernate, MySQL, Lombok, JUnit 5 + Mockito + AssertJ, Gradle.

**Spec:** [2026-07-31-qf-registro-y-libro-negro-papel-design.md](2026-07-31-qf-registro-y-libro-negro-papel-design.md) — sección "Cómo se cura un CJP marcado".
**Plan anterior:** [2026-07-31-qf-registro-backend-plan.md](2026-07-31-qf-registro-backend-plan.md) (completo y validado en DEV).

---

## Contexto imprescindible antes de empezar

**Rama.** Se sigue en `feat/qf-registro-y-papel` de `recetalia-api-rest`, donde quedó el Plan 1 (último commit `d11f2d7`, 124 tests verdes). No crear rama nueva.

**El problema que esto resuelve.** El backfill del Plan 1 marcó con `status = 'NEEDS_REVIEW'` a los QF cuyo CJP figura con más de un titular en `pharmacy`. En DEV son 20 CJPs sobre 65 de 337 farmacias; el CJP `1` lo usan seis personas distintas como relleno. Un QF marcado no puede listar farmacias, ni ver recetas verdes, ni firmar, ni completar su registro — y como no puede registrarse, tampoco puede corregir su propio nombre. La única salida es que Gestión corrija los `managerCJP` equivocados, y que el sistema note que el conflicto desapareció.

**La condición de colisión, textual, tal como la aplicó el backfill** (`doc/migrations/2026-07-31-qf-entity.sql`):

```sql
SELECT TRIM(managerCJP)
FROM pharmacy
WHERE deletedAt IS NULL AND managerCJP IS NOT NULL AND TRIM(managerCJP) <> ''
GROUP BY TRIM(managerCJP)
HAVING COUNT(DISTINCT CONCAT(TRIM(managerName), '|', TRIM(managerLastname))) > 1
```

El recálculo tiene que usar **exactamente** esta condición. Si diverge, un QF podría quedar marcado para siempre o desmarcarse cuando no corresponde.

**No hay Flyway** (`ddl-auto: none`) y **esta vez no hace falta ningún cambio de schema**: `status` ya existe.

**Los tests no levantan Spring ni DB.** Unitarios puros con Mockito + AssertJ y seams package-private. Referencia: `PharmaceuticalDirectorResolveTest`.

**Comandos:** `./gradlew build` · `./gradlew test --tests "*Nombre*"`

---

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `domain/repository/PharmacyRepository.java` | +query que cuenta titulares distintos de un CJP |
| `domain/repository/PharmaceuticalDirectorRepository.java` | +`findAllByStatus` |
| `service/PharmaceuticalDirectorRegistrationService.java` + `impl/` | +`recomputeStatus`, +`listByStatus` |
| `service/impl/PharmacyServiceImpl.java` | invoca el recálculo al guardar |
| `dto/response/PharmaceuticalDirectorReviewRow.java` | fila de la bandeja: QF + farmacias + titulares en conflicto |
| `controller/PharmaceuticalDirectorAdminController.java` | endpoint de la bandeja, para `ROLE_MANAGEMENT` |
| `infrastructure/config/SecurityConfiguration.java` | matcher del controller nuevo |

El controller de la bandeja va **aparte** del `PharmaceuticalDirectorController` existente a propósito: aquel está bajo `/api/pharmaceutical-director/**`, que exige `ROLE_ROLE_PHARMACEUTICAL_DIRECTOR`. Este es para Gestión, con otro rol y otro path.

---

### Task 1: Contar titulares distintos de un CJP

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/domain/repository/PharmacyRepository.java`

- [ ] **Step 1: Agregar la query**

Al final de la interfaz:

```java
  /**
   * Cuántos titulares distintos (nombre+apellido normalizados) figuran para un CJP.
   * >1 significa que el CJP está compartido por personas distintas y por lo tanto no
   * identifica a nadie. Réplica exacta de la condición que usó el backfill del QF
   * (doc/migrations/2026-07-31-qf-entity.sql); si las dos divergen, un QF puede quedar
   * marcado para siempre o desmarcarse cuando no corresponde.
   */
  @Query(value = """
      SELECT COUNT(DISTINCT CONCAT(TRIM(p.managerName), '|', TRIM(p.managerLastname)))
      FROM pharmacy p
      WHERE p.deletedAt IS NULL
        AND p.managerCJP IS NOT NULL
        AND TRIM(p.managerCJP) = :cjp
      """, nativeQuery = true)
  long countDistinctManagersByCjp(@Param("cjp") String cjp);
```

Verificá que `@Query` y `@Param` ya estén importados en el archivo (el repo ya tiene queries nativas); si no, agregalos.

- [ ] **Step 2: Compilar**

Run: `./gradlew build -x test`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

```bash
git add src/main/java/com/recetalia/api/application/domain/repository/PharmacyRepository.java
git commit -m "feat(qf): query que cuenta titulares distintos por CJP"
```

---

### Task 2: Recálculo del estado del QF

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/PharmaceuticalDirectorRegistrationService.java`
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRecomputeTest.java`

- [ ] **Step 1: Escribir el test que falla**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.domain.repository.PharmaceuticalDirectorRepository;
import com.recetalia.api.application.domain.repository.PharmacyRepository;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class PharmaceuticalDirectorRecomputeTest {

    private PharmaceuticalDirectorRegistrationServiceImpl svc(
            PharmaceuticalDirectorRepository repo, PharmacyRepository pharmacies) {
        PharmaceuticalDirectorRegistrationServiceImpl s = new PharmaceuticalDirectorRegistrationServiceImpl();
        s.setDepsForTest(repo, null, pharmacies);
        return s;
    }

    private PharmaceuticalDirector qf(String cjp, String status) {
        PharmaceuticalDirector d = new PharmaceuticalDirector("qf-1");
        d.setCjp(cjp);
        d.setName("JUAN");
        d.setLastname("PEREZ");
        d.setStatus(status);
        return d;
    }

    @Test
    void conflictoResuelto_pasaDeNeedsReviewAActive() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        PharmacyRepository pharmacies = mock(PharmacyRepository.class);
        PharmaceuticalDirector d = qf("51697", PharmaceuticalDirector.STATUS_NEEDS_REVIEW);
        when(repo.findByCjp("51697")).thenReturn(Optional.of(d));
        when(pharmacies.countDistinctManagersByCjp("51697")).thenReturn(1L);

        svc(repo, pharmacies).recomputeStatus("  51697 ");

        assertThat(d.getStatus()).isEqualTo(PharmaceuticalDirector.STATUS_ACTIVE);
        verify(repo).save(d);
    }

    @Test
    void conflictoSubsistente_sigueMarcadoYNoSeGuarda() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        PharmacyRepository pharmacies = mock(PharmacyRepository.class);
        PharmaceuticalDirector d = qf("1", PharmaceuticalDirector.STATUS_NEEDS_REVIEW);
        when(repo.findByCjp("1")).thenReturn(Optional.of(d));
        when(pharmacies.countDistinctManagersByCjp("1")).thenReturn(6L);

        svc(repo, pharmacies).recomputeStatus("1");

        assertThat(d.getStatus()).isEqualTo(PharmaceuticalDirector.STATUS_NEEDS_REVIEW);
        verify(repo, never()).save(any());
    }

    @Test
    void conflictoNuevo_unQfActivoPasaAEnRevision() {
        // Alguien carga una farmacia nueva con un CJP ya usado, pero otro titular.
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        PharmacyRepository pharmacies = mock(PharmacyRepository.class);
        PharmaceuticalDirector d = qf("51697", PharmaceuticalDirector.STATUS_ACTIVE);
        when(repo.findByCjp("51697")).thenReturn(Optional.of(d));
        when(pharmacies.countDistinctManagersByCjp("51697")).thenReturn(2L);

        svc(repo, pharmacies).recomputeStatus("51697");

        assertThat(d.getStatus()).isEqualTo(PharmaceuticalDirector.STATUS_NEEDS_REVIEW);
        verify(repo).save(d);
    }

    @Test
    void qfInactivo_noSeToca() {
        // La baja es una decision explicita: el recalculo no puede revivir un QF dado de baja.
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        PharmacyRepository pharmacies = mock(PharmacyRepository.class);
        PharmaceuticalDirector d = qf("51697", "INACTIVE");
        when(repo.findByCjp("51697")).thenReturn(Optional.of(d));

        svc(repo, pharmacies).recomputeStatus("51697");

        assertThat(d.getStatus()).isEqualTo("INACTIVE");
        verify(repo, never()).save(any());
        verifyNoInteractions(pharmacies);
    }

    @Test
    void cjpVacioOInexistente_esNoop() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        PharmacyRepository pharmacies = mock(PharmacyRepository.class);
        when(repo.findByCjp("99999")).thenReturn(Optional.empty());

        svc(repo, pharmacies).recomputeStatus(null);
        svc(repo, pharmacies).recomputeStatus("   ");
        svc(repo, pharmacies).recomputeStatus("99999");

        verify(repo, never()).save(any());
        verifyNoInteractions(pharmacies);
    }
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `./gradlew test --tests "*PharmaceuticalDirectorRecomputeTest*"`
Expected: FAIL — no compila, `recomputeStatus` no existe.

- [ ] **Step 3: Declarar el método en la interfaz**

```java
  /**
   * Re-evalúa si el CJP sigue compartido por varias personas y ajusta el status del QF.
   * No-op si el CJP es vacío, si no hay QF, o si el QF está INACTIVE (baja explícita).
   */
  void recomputeStatus(String cjp);
```

- [ ] **Step 4: Implementar**

```java
  @Override
  public void recomputeStatus(String cjp) {
    String normalized = trimToNull(cjp);
    if (normalized == null) return;

    PharmaceuticalDirector qf = qfRepository.findByCjp(normalized).orElse(null);
    if (qf == null) return;

    // INACTIVE es una baja explícita: el recálculo no puede revivirla.
    if (!PharmaceuticalDirector.STATUS_ACTIVE.equals(qf.getStatus())
        && !PharmaceuticalDirector.STATUS_NEEDS_REVIEW.equals(qf.getStatus())) {
      return;
    }

    boolean colisiona = pharmacyRepository.countDistinctManagersByCjp(normalized) > 1;
    String nuevo = colisiona
        ? PharmaceuticalDirector.STATUS_NEEDS_REVIEW
        : PharmaceuticalDirector.STATUS_ACTIVE;

    if (!nuevo.equals(qf.getStatus())) {
      qf.setStatus(nuevo);
      qfRepository.save(qf);
      logger.info("QF {} pasa de estado a {}", normalized, nuevo);
    }
  }
```

- [ ] **Step 5: Correr el test y verificar que pasa**

Run: `./gradlew test --tests "*PharmaceuticalDirectorRecomputeTest*"`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/PharmaceuticalDirectorRegistrationService.java \
        src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java \
        src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRecomputeTest.java
git commit -m "feat(qf): recalculo del estado del QF segun colision de titulares"
```

---

### Task 3: Invocar el recálculo al guardar una farmacia

El recálculo tiene que correr **después** de que la farmacia quedó persistida con su CJP nuevo, porque la query mira la tabla.

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PharmacyServiceImpl.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PharmacyQfLinkTest.java`

**La restricción que manda el diseño:** el recálculo consulta la tabla `pharmacy`, así que tiene
que correr **después** del `save`. Si corriera dentro de `linkPharmaceuticalDirector` —que muta la
entidad en memoria antes de persistirla— vería el estado viejo. Por eso el link devuelve el CJP
anterior y el recálculo queda en manos del call site.

- [ ] **Step 1: Agregar el test al archivo existente**

```java
    @Test
    void devuelveElCjpAnteriorParaQueElLlamadorRecalculeDespuesDelSave() {
        PharmaceuticalDirectorRegistrationService reg = mock(PharmaceuticalDirectorRegistrationService.class);
        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("51697");
        qf.setName("JUAN");
        qf.setLastname("PEREZ");
        when(reg.resolveForPharmacy(any(PharmacyRequest.class))).thenReturn(qf);

        PharmacyServiceImpl svc = new PharmacyServiceImpl();
        svc.setQfRegistrationForTest(reg);

        Pharmacy pharmacy = new Pharmacy("ph-1");
        pharmacy.setManagerCJP("1");            // CJP viejo, colisionado
        PharmacyRequest request = new PharmacyRequest();
        request.setManagerCJP("51697");         // CJP nuevo, corregido

        String cjpAnterior = svc.linkPharmaceuticalDirector(pharmacy, request);

        assertThat(cjpAnterior).isEqualTo("1");
        assertThat(pharmacy.getManagerCJP()).isEqualTo("51697");
        // El link NO recalcula: la tabla todavía no tiene el CJP nuevo.
        verify(reg, never()).recomputeStatus(anyString());
    }

    @Test
    void sinQf_devuelveNull() {
        // Reemplaza al test viejo del mismo nombre, que asumía retorno void.
        PharmaceuticalDirectorRegistrationService reg = mock(PharmaceuticalDirectorRegistrationService.class);
        when(reg.resolveForPharmacy(any(PharmacyRequest.class))).thenReturn(null);

        PharmacyServiceImpl svc = new PharmacyServiceImpl();
        svc.setQfRegistrationForTest(reg);

        Pharmacy pharmacy = new Pharmacy("ph-1");
        pharmacy.setManagerName("ORIGINAL");

        assertThat(svc.linkPharmaceuticalDirector(pharmacy, new PharmacyRequest())).isNull();
        assertThat(pharmacy.getPharmaceuticalDirector()).isNull();
        assertThat(pharmacy.getManagerName()).isEqualTo("ORIGINAL");
    }
```

El test viejo `sinQf_noTocaLaFarmacia` queda reemplazado por el segundo: borralo para no duplicar.
Imports nuevos: `anyString` y `never` de Mockito.

- [ ] **Step 2: Correr y verificar que falla**

Run: `./gradlew test --tests "*PharmacyQfLinkTest*"`
Expected: FAIL — no compila, `linkPharmaceuticalDirector` devuelve `void`.

- [ ] **Step 3: Cambiar la firma del link**

```java
  /**
   * Vincula el QF y sincroniza la copia derivada manager*. Devuelve el CJP que la farmacia tenía
   * antes (null si no se resolvió ningún QF), para que el llamador recalcule los estados DESPUÉS
   * del save: el recálculo consulta la tabla y acá la fila todavía no está persistida.
   */
  public String linkPharmaceuticalDirector(Pharmacy pharmacy, PharmacyRequest request) {
    String cjpAnterior = pharmacy.getManagerCJP();
    PharmaceuticalDirector qf = qfRegistrationService.resolveForPharmacy(request);
    if (qf == null) return null;
    pharmacy.setPharmaceuticalDirector(qf);
    pharmacy.setManagerName(qf.getName());
    pharmacy.setManagerLastname(qf.getLastname());
    pharmacy.setManagerCJP(qf.getCjp());
    if (qf.getDocument() != null) {
      pharmacy.setManagerDocument(qf.getDocument());
    }
    return cjpAnterior;
  }

  /**
   * Recalcula el estado del CJP viejo y del nuevo. El viejo puede haber dejado de colisionar
   * justamente porque esta farmacia se fue; el nuevo puede haber empezado a colisionar porque
   * llegó. Llamar SIEMPRE después del save.
   */
  private void recomputeQfStatuses(String cjpAnterior, String cjpNuevo) {
    if (cjpAnterior != null && !cjpAnterior.trim().equals(cjpNuevo)) {
      qfRegistrationService.recomputeStatus(cjpAnterior);
    }
    qfRegistrationService.recomputeStatus(cjpNuevo);
  }
```

- [ ] **Step 4: Usarlo en los dos call sites**

En `create`, el bloque del `try` queda:

```java
    try {
      String cjpAnterior = linkPharmaceuticalDirector(pharmacy, request);
      pharmacy = pharmacyRepository.save(pharmacy);
      recomputeQfStatuses(cjpAnterior, pharmacy.getManagerCJP());
    } catch (RuntimeException e) {
      logger.error("Farmacia {} creada, pero falló el alta del QF: {}", request.getEmail(), e.getMessage());
    }
```

En `update`, dentro del `try` que ya existe:

```java
      try {
        String cjpAnterior = linkPharmaceuticalDirector(saved, request);
        saved = pharmacyRepository.save(saved);
        recomputeQfStatuses(cjpAnterior, saved.getManagerCJP());
      } catch (RuntimeException e) {
        logger.error("Farmacia {} actualizada, pero falló el vínculo con el QF: {}",
            saved.getId(), e.getMessage());
      }
```

**Nota sobre cobertura:** los dos call sites no son testeables sin levantar Spring (necesitan
`PharmacyMapper`, `EmailRestConsumer` y el repositorio real). Los tests unitarios cubren el link y
el recálculo por separado; que estén bien encadenados lo verifica la Task 5 contra DEV. Si al
implementar encontrás una forma razonable de testear el encadenamiento con los seams que hay,
sumala; si no, **no escribas un test que no prueba nada** y decilo en el reporte.

- [ ] **Step 4: Correr los tests**

Run: `./gradlew build`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/impl/PharmacyServiceImpl.java \
        src/test/java/com/recetalia/api/application/service/impl/PharmacyQfLinkTest.java
git commit -m "feat(qf): recalcular el estado del QF al guardar una farmacia"
```

---

### Task 4: Endpoint de la bandeja para Gestión

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/domain/repository/PharmaceuticalDirectorRepository.java`
- Modify: `src/main/java/com/recetalia/api/application/domain/repository/PharmacyRepository.java`
- Create: `src/main/java/com/recetalia/api/application/dto/response/PharmaceuticalDirectorReviewRow.java`
- Modify: `service/PharmaceuticalDirectorRegistrationService.java` + `impl/`
- Create: `src/main/java/com/recetalia/api/application/controller/PharmaceuticalDirectorAdminController.java`
- Modify: `src/main/java/com/recetalia/api/application/infrastructure/config/SecurityConfiguration.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorReviewListTest.java`

- [ ] **Step 1: El DTO de la fila**

```java
package com.recetalia.api.application.dto.response;

import lombok.Data;

import java.util.List;

/** Una fila de la bandeja de curación de Gestión. */
@Data
public class PharmaceuticalDirectorReviewRow {
  private String id;
  private String cjp;
  private String name;
  private String lastname;
  private String status;
  /** Farmacias que hoy declaran ese CJP. */
  private List<PharmacyBrief> pharmacies;

  @Data
  public static class PharmacyBrief {
    private String id;
    private String name;
    /** Titular que declara esa farmacia. Si difiere entre filas, ahí está el conflicto. */
    private String managerName;
    private String managerLastname;
  }
}
```

- [ ] **Step 2: Las queries**

En `PharmaceuticalDirectorRepository`:

```java
  List<PharmaceuticalDirector> findAllByStatusOrderByCjpAsc(String status);
```

En `PharmacyRepository`, si no existe ya, una que traiga las farmacias de un CJP normalizado:

```java
  @Query(value = """
      SELECT * FROM pharmacy p
      WHERE p.deletedAt IS NULL AND TRIM(p.managerCJP) = :cjp
      ORDER BY p.name
      """, nativeQuery = true)
  List<Pharmacy> findAllByTrimmedManagerCjp(@Param("cjp") String cjp);
```

- [ ] **Step 3: Escribir el test que falla**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.domain.model.entities.Pharmacy;
import com.recetalia.api.application.domain.repository.PharmaceuticalDirectorRepository;
import com.recetalia.api.application.domain.repository.PharmacyRepository;
import com.recetalia.api.application.dto.response.PharmaceuticalDirectorReviewRow;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PharmaceuticalDirectorReviewListTest {

    @Test
    void listaLosQfEnRevisionConSusFarmaciasYLosTitularesEnConflicto() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        PharmacyRepository pharmacies = mock(PharmacyRepository.class);

        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("1");
        qf.setName("MARIANA");
        qf.setLastname("SANTANA");
        qf.setStatus(PharmaceuticalDirector.STATUS_NEEDS_REVIEW);

        Pharmacy a = new Pharmacy("ph-1");
        a.setName("ALBISU");
        a.setManagerName("Marcelo");
        a.setManagerLastname("Lucas");

        Pharmacy b = new Pharmacy("ph-2");
        b.setName("BOTICA");
        b.setManagerName("Mariana");
        b.setManagerLastname("Santana");

        when(repo.findAllByStatusOrderByCjpAsc(PharmaceuticalDirector.STATUS_NEEDS_REVIEW))
                .thenReturn(List.of(qf));
        when(pharmacies.findAllByTrimmedManagerCjp("1")).thenReturn(List.of(a, b));

        PharmaceuticalDirectorRegistrationServiceImpl svc = new PharmaceuticalDirectorRegistrationServiceImpl();
        svc.setDepsForTest(repo, null, pharmacies);

        List<PharmaceuticalDirectorReviewRow> rows =
                svc.listByStatus(PharmaceuticalDirector.STATUS_NEEDS_REVIEW);

        assertThat(rows).hasSize(1);
        assertThat(rows.get(0).getCjp()).isEqualTo("1");
        assertThat(rows.get(0).getPharmacies()).hasSize(2);
        assertThat(rows.get(0).getPharmacies()).extracting("name")
                .containsExactly("ALBISU", "BOTICA");
        assertThat(rows.get(0).getPharmacies()).extracting("managerLastname")
                .containsExactly("Lucas", "Santana");
    }
}
```

- [ ] **Step 4: Verificar rojo, después implementar**

En la interfaz:

```java
  /** Lista los QF con un status dado, con las farmacias que declaran su CJP. Para Gestión. */
  List<PharmaceuticalDirectorReviewRow> listByStatus(String status);
```

En la impl:

```java
  @Override
  public List<PharmaceuticalDirectorReviewRow> listByStatus(String status) {
    return qfRepository.findAllByStatusOrderByCjpAsc(status).stream().map(qf -> {
      PharmaceuticalDirectorReviewRow row = new PharmaceuticalDirectorReviewRow();
      row.setId(qf.getId());
      row.setCjp(qf.getCjp());
      row.setName(qf.getName());
      row.setLastname(qf.getLastname());
      row.setStatus(qf.getStatus());
      row.setPharmacies(pharmacyRepository.findAllByTrimmedManagerCjp(qf.getCjp())
          .stream().map(p -> {
            PharmaceuticalDirectorReviewRow.PharmacyBrief b =
                new PharmaceuticalDirectorReviewRow.PharmacyBrief();
            b.setId(p.getId());
            b.setName(p.getName());
            b.setManagerName(p.getManagerName());
            b.setManagerLastname(p.getManagerLastname());
            return b;
          }).toList());
      return row;
    }).toList();
  }
```

- [ ] **Step 5: Verde. Después el controller**

```java
package com.recetalia.api.application.controller;

import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.dto.enums.ResponseStatus;
import com.recetalia.api.application.dto.response.GenericResponse;
import com.recetalia.api.application.dto.response.PharmaceuticalDirectorReviewRow;
import com.recetalia.api.application.service.PharmaceuticalDirectorRegistrationService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * Administración de Químicos Farmacéuticos desde Gestión. Va aparte de
 * PharmaceuticalDirectorController, que está bajo /api/pharmaceutical-director/** y exige el
 * rol del propio QF: este es para ROLE_MANAGEMENT y necesita otro path.
 */
@RestController
@RequestMapping("/api/pharmaceutical-directors")
public class PharmaceuticalDirectorAdminController {

  @Autowired
  private PharmaceuticalDirectorRegistrationService service;

  /** Bandeja de curación: los QF cuyo CJP figura con más de un titular. */
  @GetMapping("/needs-review")
  public ResponseEntity<GenericResponse<List<PharmaceuticalDirectorReviewRow>>> needsReview() {
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS,
        service.listByStatus(PharmaceuticalDirector.STATUS_NEEDS_REVIEW)));
  }
}
```

- [ ] **Step 6: El matcher de seguridad**

En `SecurityConfiguration`, junto a los otros matchers por autoridad (donde está el de
`/api/control-dashboard/**`):

```java
                        .requestMatchers("/api/pharmaceutical-directors/**").hasAuthority("ROLE_ROLE_MANAGEMENT")
```

⚠️ **Verificá el orden con lupa.** El path del lookup público es
`/api/pharmacies/pharmaceutical-director-lookup/{cjp}` — otro prefijo, no colisiona. Pero
`/api/pharmaceutical-directors/**` (plural) y `/api/pharmaceutical-director/**` (singular) son
vecinos de un carácter: confirmá con un test manual o razonando el patrón que el matcher plural
**no** captura el singular ni viceversa, y reportá el resultado.

- [ ] **Step 7: `./gradlew build` → verde**

- [ ] **Step 8: Commit**

```bash
git add -A src/main/java/com/recetalia/api/application/ src/test/java/com/recetalia/api/application/
git commit -m "feat(qf): bandeja de curacion de CJPs para Gestion"
```

---

### Task 5: Validación manual contra DEV

**Files:** ninguno — es verificación.

- [ ] **Step 1: Deployar**

```bash
cd /Users/pablo/iwtg/recetalia-workspace
rsync -az --delete --exclude .git --exclude build --exclude .gradle \
  recetalia-api-rest/ root@138.197.150.98:/opt/recetalia/recetalia-api-rest/
ssh root@138.197.150.98 "cd /opt/recetalia/deploy-recetalia && \
  docker compose build recetalia-api-rest && docker compose up -d --no-deps recetalia-api-rest"
```

⚠️ `--no-deps` y solo ese servicio: un `up -d` a secas recrea nginx y rompe PRE.

- [ ] **Step 2: La bandeja con token de Gestión**

```bash
TOKEN=$(curl -s -X POST "https://apipre.recetalia.com/security-api-recetalia/api/auth/loginBack" \
  -H "Content-Type: application/json" \
  -d '{"email":"gestion@recetalia.com","password":"1wtg_p4ss","info":"000"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmaceutical-directors/needs-review" \
  | python3 -c "import sys,json; d=json.load(sys.stdin)['answer']; print(len(d),'QF en revision'); [print(r['cjp'], len(r['pharmacies']), sorted({p['managerLastname'] for p in r['pharmacies']})) for r in d[:5]]"
```

Esperado: **20** QF, y para el CJP `1` seis apellidos distintos.

- [ ] **Step 3: Sin token → 401, y con token de QF → 403**

```bash
curl -s -o /dev/null -w "sin token: %{http_code}\n" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmaceutical-directors/needs-review"

QFTOKEN=$(curl -s -X POST "https://apipre.recetalia.com/security-api-recetalia/api/auth/loginBack" \
  -H "Content-Type: application/json" \
  -d '{"email":"999999@qf.recetalia.com","password":"Recetalia2026!","info":"000"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -s -o /dev/null -w "token de QF: %{http_code}\n" -H "Authorization: Bearer $QFTOKEN" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmaceutical-directors/needs-review"
```

Esperado: `401` y `403`.

- [ ] **Step 4: Que los endpoints del QF sigan andando**

```bash
curl -s -o /dev/null -w "me: %{http_code}\n" -H "Authorization: Bearer $QFTOKEN" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmaceutical-director/me"
```

Esperado: `200`. Esto confirma que el matcher plural nuevo no se comió el singular.

- [ ] **Step 5: Probar el recálculo de punta a punta**

Elegí un CJP colisionado con exactamente 2 titulares, corregí en la DB el `managerCJP` de la
farmacia disidente a un CJP libre, y verificá que al guardar esa farmacia por la API el QF pasa a
`ACTIVE`. **Dejá el dato como estaba al terminar** y confirmá el estado restaurado.

Si no querés tocar datos, alcanza con verificar la query directamente:

```bash
ssh root@138.197.150.98 "docker exec recetalia-mysql mysql -uroot -pRootDev98_p3Wn8sLzQ -N -e \"
  SELECT COUNT(DISTINCT CONCAT(TRIM(managerName),'|',TRIM(managerLastname)))
  FROM recetali_receta.pharmacy
  WHERE deletedAt IS NULL AND TRIM(managerCJP)='1';\""
```

Esperado: `6`. Es el número que `countDistinctManagersByCjp` tiene que devolver.

- [ ] **Step 6: Regresión del ambiente**

Los 5 frontends de PRE en 200 y ningún contenedor caído salvo `observatorio-cpa`.

---

## Lo que queda para el Plan 2b (frontends)

- **Farmacias `register`** y **Gestión `pharmacy-update`**: el lookup por CJP al salir del campo, con los dos estados (encontrado → solo lectura; no encontrado → habilitar nombre, apellido, documento y clave inicial). Son los únicos dos formularios que editan el D.T.; los dos `profile` lo muestran deshabilitado y no hay que tocarlos.
- **Gestión**: la pantalla nueva de bandeja, consumiendo `/api/pharmaceutical-directors/needs-review`, con salto a las farmacias de cada CJP.
- Los dos formularios ya mandan `info`, así que el cifrado de la clave inicial del QF no necesita nada extra.
