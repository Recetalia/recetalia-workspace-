# Recetas en papel — Plan 4a: Backend

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que una farmacia pueda cargar al sistema una receta emitida en papel, creando en un solo acto el médico, el paciente, la receta y su dispensación — sin disparar ninguna notificación.

**Architecture:** Un endpoint nuevo que resuelve médico y paciente (reusándolos si ya existen), crea la receta con el generador de códigos de siempre y marcada como `origin = 'PAPER'`, y después la dispensa **por el camino existente** `DispensationService.create`, que ya trae todas las validaciones de negocio. Más la anulación y el Nº de talonario en el Excel.

**Tech Stack:** Java 21, Spring Boot 3.3.0, Spring Data JPA, MySQL, POI, JUnit 5 + Mockito + AssertJ.

**Spec:** [2026-07-31-qf-registro-y-libro-negro-papel-design.md](2026-07-31-qf-registro-y-libro-negro-papel-design.md) — sección "Feature 2".

---

## Contexto imprescindible antes de empezar

**Rama:** seguir en `feat/qf-registro-y-papel` de `recetalia-api-rest` (último commit `2b074b7`, 137 tests verdes).

**El schema ya está.** Las columnas `prescription.origin`, `paperNumber` y `paperIssuedAt` existen en la DB desde el Plan 1 y están mapeadas en la entidad. La proyección `DispensationSearchRow` ya las expone. **No hace falta ningún cambio de schema en este plan.**

**Tres cosas que se relevaron y que cambian lo que decía el spec:**

1. **No existe búsqueda de médico por CJP.** `MedicRepository` solo tiene `findByEmail` / `existsByEmail`. Hay que agregarla. Y ojo: `medic.cjp` **no es único** — puede haber varios médicos con el mismo CJP, así que la búsqueda tiene que ser determinística.

2. **El médico de papel NO puede crearse con `MedicService.create()`.** Ese método hace alta dual: crea también un usuario de login en el security-api, y si eso falla borra el médico. Un médico transcripto de una receta de papel **no es usuario de Recetalia**: no tiene que poder entrar a ningún lado. Se crea directo por el repositorio.

3. **`DispensationService.create(DispensationRequest)` hace todo lo que necesitamos** y está probado en producción: valida que la farmacia esté `ACTIVE`, aplica el tope de cajas (`DispensationCapValidator`), rechaza dispensaciones duplicadas, valida que el dispensador exista, completa `dispensedTo*` desde el paciente de la receta, y pone la receta en `DISPENSED`. **Reusalo. No armes la dispensación a mano.**

**Por qué esto no dispara WhatsApp** (verificado contra las queries reales del scheduler, que vive en `transversal-recetalia-api`):

| Disparo | Condición | Por qué no aplica |
|---|---|---|
| Receta nueva | `status = 'PENDING'` | La receta de papel nunca pasa por `PENDING` |
| Recordatorio de no retiro | `status = 'AVAILABLE'` **y** `dispensationPendingReminderSended = 0` **y** `updatedAt <= now - 48h` | Se crea con el flag en `1`, y además queda `DISPENSED` en el mismo acto |

`dateTimeToSend` no aparece en ninguna cláusula `WHERE` — solo se selecciona. Igual se deja en `null` por higiene.

**Los tests de este proyecto no levantan Spring ni DB.** Unitarios puros, Mockito + AssertJ, seams package-private. Referencia: `PharmaceuticalDirectorResolveTest`.

**Comandos:** `./gradlew build` · `./gradlew test --tests "*Nombre*"`

---

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `dto/request/PaperPrescriptionRequest.java` | Payload de la carga |
| `dto/response/PaperPrescriptionResponse.java` | Devuelve el código generado |
| `domain/repository/MedicRepository.java` | +búsqueda por CJP |
| `service/PaperPrescriptionService.java` + `impl/` | Toda la lógica nueva |
| `controller/PrescriptionController.java` | +`/paper` y +`/paper/{id}/cancel` |
| `infrastructure/config/SecurityConfiguration.java` | Endurecer el Excel por rol |
| `service/impl/ControlledMedicationsExcelServiceImpl.java` | +columna Nº de talonario |

El servicio va **aparte** de `PrescriptionServiceImpl`, que ya tiene más de 600 líneas y una docena de dependencias.

---

### Task 1: El payload y la búsqueda de médico por CJP

**Files:**
- Create: `src/main/java/com/recetalia/api/application/dto/request/PaperPrescriptionRequest.java`
- Create: `src/main/java/com/recetalia/api/application/dto/response/PaperPrescriptionResponse.java`
- Modify: `src/main/java/com/recetalia/api/application/domain/repository/MedicRepository.java`

- [ ] **Step 1: El request**

```java
package com.recetalia.api.application.dto.request;

import com.recetalia.api.application.domain.model.Document;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Carga de una receta emitida en papel, transcripta por una farmacia.
 * Los campos siguen el orden del documento impreso de la receta.
 */
@Data
public class PaperPrescriptionRequest {

  // --- Paciente ---
  @NotBlank private String patientName;
  @NotBlank private String patientLastname;
  @NotNull  private Document patientDocument;

  // --- Médico ---
  @NotBlank private String medicName;
  @NotBlank private String medicLastname;
  @NotBlank private String medicCjp;

  // --- Receta ---
  /** Nº de talonario que trae el papel. */
  @NotBlank private String paperNumber;
  /** Fecha que dice el papel (distinta de cuándo se cargó al sistema). */
  @NotNull  private Instant paperIssuedAt;

  // --- Medicamento (sale del buscador DNMA) ---
  @NotBlank private String productType;      // AMP | VMP
  @NotBlank private String productId;
  private String condvtaId;                  // '11' verde, '12' naranja, null blanca
  private Integer dnmaLaboratoryId;

  // --- Administración ---
  private BigDecimal dose;
  private String doseUnit;
  private String doseType;
  /**
   * Horas entre tomas. OBLIGATORIO: si va null, el tope de cajas al dispensar no aplica
   * y la app muestra "1 comprimido cada [vacío] horas".
   */
  @NotNull  private Integer frecuency;
  @NotBlank private String frecuencyUnit;
  private Integer duration;
  private String durationUnit;

  // --- Dispensación ---
  @NotNull  private Integer qty;
  @NotBlank private String loteNumber;
  private Instant loteExpireAt;
  /** Dispensador de la farmacia que registra la carga. */
  @NotBlank private String dispensedById;
}
```

- [ ] **Step 2: El response**

```java
package com.recetalia.api.application.dto.response;

import lombok.AllArgsConstructor;
import lombok.Data;

/** Lo que devuelve la carga de una receta en papel. */
@Data
@AllArgsConstructor
public class PaperPrescriptionResponse {
  /** Código Recetalia generado, para mostrárselo a la farmacia. */
  private String prescriptionCode;
  private String prescriptionId;
  private String dispensationId;
}
```

- [ ] **Step 3: La búsqueda por CJP**

En `MedicRepository`, al final:

```java
  /**
   * Primer médico con ese CJP. `medic.cjp` NO es único: puede haber varios (altas duplicadas
   * históricas), así que se ordena por fecha de creación para que el resultado sea
   * determinístico y no dependa del orden físico de las filas.
   */
  Optional<Medic> findFirstByCjpAndDeletedAtIsNullOrderByCreatedAtAsc(String cjp);
```

- [ ] **Step 4: Compilar**

Run: `./gradlew build`
Expected: `BUILD SUCCESSFUL`, 137 tests verdes.

⚠️ Si Spring Data no puede derivar el nombre del método (por ejemplo si el campo se llama distinto), **decilo en el reporte** en vez de improvisar una `@Query`. El error aparece al arrancar el contexto, no al compilar, así que verificalo también en la Task 5.

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/recetalia/api/application/dto/request/PaperPrescriptionRequest.java \
        src/main/java/com/recetalia/api/application/dto/response/PaperPrescriptionResponse.java \
        src/main/java/com/recetalia/api/application/domain/repository/MedicRepository.java
git commit -m "feat(papel): payload de receta en papel y busqueda de medico por CJP"
```

---

### Task 2: Resolver médico y paciente

La parte con más trampas: las dos entidades tienen campos `NOT NULL` que una receta de papel no trae.

**Files:**
- Create: `src/main/java/com/recetalia/api/application/service/PaperPrescriptionService.java`
- Create: `src/main/java/com/recetalia/api/application/service/impl/PaperPrescriptionServiceImpl.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PaperPrescriptionResolveTest.java`

- [ ] **Step 1: Escribir el test que falla**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.Document;
import com.recetalia.api.application.domain.model.entities.Medic;
import com.recetalia.api.application.domain.model.entities.Patient;
import com.recetalia.api.application.domain.repository.MedicRepository;
import com.recetalia.api.application.domain.repository.PatientRepository;
import com.recetalia.api.application.dto.request.PaperPrescriptionRequest;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class PaperPrescriptionResolveTest {

    private PaperPrescriptionRequest req() {
        PaperPrescriptionRequest r = new PaperPrescriptionRequest();
        r.setMedicName("JUAN");
        r.setMedicLastname("PEREZ");
        r.setMedicCjp("  51697 ");
        r.setPatientName("MARIA");
        r.setPatientLastname("GOMEZ");
        Document doc = new Document();
        doc.setNumber("2852833");
        doc.setType("UY");
        r.setPatientDocument(doc);
        return r;
    }

    private PaperPrescriptionServiceImpl svc(MedicRepository medics, PatientRepository patients) {
        PaperPrescriptionServiceImpl s = new PaperPrescriptionServiceImpl();
        s.setReposForTest(medics, patients);
        return s;
    }

    @Test
    void medicoExistente_seReusaYNoSeCreaNadaNuevo() {
        MedicRepository medics = mock(MedicRepository.class);
        PatientRepository patients = mock(PatientRepository.class);
        Medic existente = new Medic();
        existente.setId("med-1");
        existente.setCjp("51697");
        existente.setName("JUAN CARLOS");
        when(medics.findFirstByCjpAndDeletedAtIsNullOrderByCreatedAtAsc("51697"))
                .thenReturn(Optional.of(existente));

        Medic m = svc(medics, patients).resolveMedic(req());

        assertThat(m.getId()).isEqualTo("med-1");
        assertThat(m.getName()).isEqualTo("JUAN CARLOS");   // no se pisa con el del papel
        verify(medics, never()).save(any());
    }

    @Test
    void medicoNuevo_seCreaSinUsuarioDeLoginYSinTelefono() {
        MedicRepository medics = mock(MedicRepository.class);
        PatientRepository patients = mock(PatientRepository.class);
        when(medics.findFirstByCjpAndDeletedAtIsNullOrderByCreatedAtAsc("51697"))
                .thenReturn(Optional.empty());
        when(medics.save(any(Medic.class))).thenAnswer(i -> i.getArgument(0));

        Medic m = svc(medics, patients).resolveMedic(req());

        ArgumentCaptor<Medic> cap = ArgumentCaptor.forClass(Medic.class);
        verify(medics).save(cap.capture());
        Medic creado = cap.getValue();
        assertThat(creado.getCjp()).isEqualTo("51697");     // trimeado
        assertThat(creado.getName()).isEqualTo("JUAN");
        assertThat(creado.getEmail()).isEqualTo("51697@papel.recetalia.com");
        assertThat(creado.getMedicalProviderId()).isNull(); // no pertenece a ningún prestador
        assertThat(m).isSameAs(creado);
    }

    @Test
    void pacienteExistente_seReusaPorDocumento() {
        MedicRepository medics = mock(MedicRepository.class);
        PatientRepository patients = mock(PatientRepository.class);
        Patient existente = new Patient();
        existente.setId("pat-1");
        existente.setName("MARIA ELENA");
        when(patients.findByDocumentNumberAndType("2852833", "UY"))
                .thenReturn(Optional.of(existente));

        Patient p = svc(medics, patients).resolvePatient(req());

        assertThat(p.getId()).isEqualTo("pat-1");
        assertThat(p.getName()).isEqualTo("MARIA ELENA");   // no se pisa
        verify(patients, never()).save(any());
    }

    @Test
    void pacienteNuevo_seCreaSinTelefono() {
        // Sin teléfono no hay WhatsApp posible, ni siquiera por accidente.
        MedicRepository medics = mock(MedicRepository.class);
        PatientRepository patients = mock(PatientRepository.class);
        when(patients.findByDocumentNumberAndType("2852833", "UY")).thenReturn(Optional.empty());
        when(patients.save(any(Patient.class))).thenAnswer(i -> i.getArgument(0));

        Patient p = svc(medics, patients).resolvePatient(req());

        assertThat(p.getName()).isEqualTo("MARIA");
        assertThat(p.getDocument().getNumber()).isEqualTo("2852833");
        assertThat(p.getPhone()).isNull();
    }
}
```

- [ ] **Step 2: Verificar rojo**

Run: `./gradlew test --tests "*PaperPrescriptionResolveTest*"`
Expected: FAIL — la clase no existe.

- [ ] **Step 3: La interfaz**

```java
package com.recetalia.api.application.service;

import com.recetalia.api.application.dto.request.PaperPrescriptionRequest;
import com.recetalia.api.application.dto.response.PaperPrescriptionResponse;
import com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;

public interface PaperPrescriptionService {

  /** Crea médico, paciente, receta y dispensación a partir de una receta en papel. */
  PaperPrescriptionResponse create(PaperPrescriptionRequest request) throws ResourceNotFoundException;

  /** Anula una receta de papel cargada por error. No borra: deja constancia. */
  void cancel(String prescriptionId) throws ResourceNotFoundException;
}
```

- [ ] **Step 4: La implementación (solo el resolve; el resto va en la Task 3)**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.Medic;
import com.recetalia.api.application.domain.model.entities.Patient;
import com.recetalia.api.application.domain.repository.MedicRepository;
import com.recetalia.api.application.domain.repository.PatientRepository;
import com.recetalia.api.application.dto.request.PaperPrescriptionRequest;
import com.recetalia.api.application.dto.response.PaperPrescriptionResponse;
import com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;
import com.recetalia.api.application.service.PaperPrescriptionService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class PaperPrescriptionServiceImpl implements PaperPrescriptionService {

  private static final Logger logger = LoggerFactory.getLogger(PaperPrescriptionServiceImpl.class);

  /** Dominio de los emails sintéticos de médicos transcriptos de papel. */
  private static final String PAPER_MEDIC_DOMAIN = "@papel.recetalia.com";

  @Autowired private MedicRepository medicRepository;
  @Autowired private PatientRepository patientRepository;

  /**
   * Médico del papel. Se busca por CJP y, si existe, se reusa TAL CUAL: puede ser un médico
   * que ya receta digitalmente en Recetalia, y sus datos son mejores que los transcriptos
   * a mano de un papel.
   *
   * Si no existe se crea directo por el repositorio, NO por MedicService.create(): ese hace
   * alta dual y le crearía un usuario de login en el security-api. Un médico transcripto de
   * un papel no es usuario de Recetalia y no tiene que poder entrar a ningún lado.
   */
  public Medic resolveMedic(PaperPrescriptionRequest req) {
    String cjp = trimToNull(req.getMedicCjp());
    if (cjp == null) {
      throw new IllegalArgumentException("El CJP del médico es obligatorio");
    }
    return medicRepository.findFirstByCjpAndDeletedAtIsNullOrderByCreatedAtAsc(cjp)
        .orElseGet(() -> {
          Medic m = new Medic();
          m.setName(trimToNull(req.getMedicName()));
          m.setLastname(trimToNull(req.getMedicLastname()));
          m.setCjp(cjp);
          // Email sintético: el campo es NOT NULL y único, y este médico no tiene email real.
          m.setEmail(cjp + PAPER_MEDIC_DOMAIN);
          // Password aleatoria: el campo es NOT NULL pero nadie va a autenticarse con ella.
          m.setPassword(UUID.randomUUID().toString());
          m.setStatus("ACTIVE");
          m.setBirthdate("");
          // Sin teléfono y sin prestador: no recibe notificaciones ni pertenece a ninguna red.
          logger.info("Médico de papel creado para CJP {}", cjp);
          return medicRepository.save(m);
        });
  }

  /**
   * Paciente del papel, deduplicado por documento. Si ya existe se reusa: es lo que hace que
   * el libro de controlados acumule el historial de esa persona, que es todo su sentido.
   */
  public Patient resolvePatient(PaperPrescriptionRequest req) {
    String number = req.getPatientDocument() == null ? null : req.getPatientDocument().getNumber();
    String type = req.getPatientDocument() == null ? null : req.getPatientDocument().getType();
    if (trimToNull(number) == null || trimToNull(type) == null) {
      throw new IllegalArgumentException("El documento del paciente es obligatorio");
    }
    return patientRepository.findByDocumentNumberAndType(number.trim(), type.trim())
        .orElseGet(() -> {
          Patient p = new Patient();
          p.setName(trimToNull(req.getPatientName()));
          p.setLastname(trimToNull(req.getPatientLastname()));
          p.setDocument(req.getPatientDocument());
          p.setPassword(UUID.randomUUID().toString());
          p.setBirthdate("");
          // Sin teléfono: sin teléfono no hay WhatsApp posible, ni siquiera por accidente.
          return patientRepository.save(p);
        });
  }

  @Override
  public PaperPrescriptionResponse create(PaperPrescriptionRequest request) throws ResourceNotFoundException {
    throw new UnsupportedOperationException("Task 3");
  }

  @Override
  public void cancel(String prescriptionId) throws ResourceNotFoundException {
    throw new UnsupportedOperationException("Task 3");
  }

  private String trimToNull(String s) {
    if (s == null) return null;
    String t = s.trim();
    return t.isEmpty() ? null : t;
  }

  /* Test seam. */
  void setReposForTest(MedicRepository medics, PatientRepository patients) {
    this.medicRepository = medics;
    this.patientRepository = patients;
  }
}
```

⚠️ **Verificá los campos `NOT NULL` reales de `Medic` y `Patient` antes de dar esto por bueno.** El código de arriba asume que `phone` es nullable y que `birthdate` acepta string vacío. Si alguno de esos campos es `NOT NULL` en la entidad y explota al persistir, **decilo en el reporte con el campo exacto**: la decisión de qué poner ahí es de diseño, no la improvises. `medic.phone` y `patient.phone` usan converters JSON; si no admiten `null`, el valor correcto es un `Phone` vacío, **nunca** un teléfono inventado.

- [ ] **Step 5: Verde**

Run: `./gradlew test --tests "*PaperPrescriptionResolveTest*"`
Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/PaperPrescriptionService.java \
        src/main/java/com/recetalia/api/application/service/impl/PaperPrescriptionServiceImpl.java \
        src/test/java/com/recetalia/api/application/service/impl/PaperPrescriptionResolveTest.java
git commit -m "feat(papel): resolver medico por CJP y paciente por documento"
```

---

### Task 3: Crear la receta y dispensarla

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PaperPrescriptionServiceImpl.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PaperPrescriptionCreateTest.java`

**El diseño, y por qué:** la receta se crea con `status = 'AVAILABLE'` y después se dispensa llamando a `DispensationService.create(...)`, que es el mismo camino que usa la farmacia todos los días. Eso trae gratis: validación de que la farmacia esté `ACTIVE`, el tope de cajas según posología, el rechazo de dispensaciones duplicadas, la validación del dispensador, el completado de `dispensedTo*` desde el paciente, y el cambio de estado a `DISPENSED`. Armar la dispensación a mano duplicaría todo eso y quedaría desincronizado a la primera que alguien toque una regla.

- [ ] **Step 1: Escribir el test que falla**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.Document;
import com.recetalia.api.application.domain.model.entities.Medic;
import com.recetalia.api.application.domain.model.entities.Patient;
import com.recetalia.api.application.domain.model.entities.Prescription;
import com.recetalia.api.application.domain.repository.MedicRepository;
import com.recetalia.api.application.domain.repository.PatientRepository;
import com.recetalia.api.application.domain.repository.PrescriptionRepository;
import com.recetalia.api.application.dto.request.DispensationRequest;
import com.recetalia.api.application.dto.request.PaperPrescriptionRequest;
import com.recetalia.api.application.dto.response.DispensationResponse;
import com.recetalia.api.application.dto.response.PaperPrescriptionResponse;
import com.recetalia.api.application.service.DispensationService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class PaperPrescriptionCreateTest {

    private PaperPrescriptionRequest req() {
        PaperPrescriptionRequest r = new PaperPrescriptionRequest();
        r.setMedicName("JUAN"); r.setMedicLastname("PEREZ"); r.setMedicCjp("51697");
        r.setPatientName("MARIA"); r.setPatientLastname("GOMEZ");
        Document doc = new Document(); doc.setNumber("2852833"); doc.setType("UY");
        r.setPatientDocument(doc);
        r.setPaperNumber("0648345");
        r.setPaperIssuedAt(Instant.parse("2026-07-20T00:00:00Z"));
        r.setProductType("AMP"); r.setProductId("100421000179106");
        r.setCondvtaId("11"); r.setDnmaLaboratoryId(188);
        r.setDose(new BigDecimal("1.0")); r.setDoseUnit("comprimido");
        r.setFrecuency(8); r.setFrecuencyUnit("HOUR");
        r.setDuration(8); r.setDurationUnit("días");
        r.setQty(3); r.setLoteNumber("L-123");
        r.setDispensedById("disp-1");
        return r;
    }

    private PaperPrescriptionServiceImpl svc(PrescriptionRepository prescriptions,
                                             DispensationService dispensations) {
        MedicRepository medics = mock(MedicRepository.class);
        PatientRepository patients = mock(PatientRepository.class);
        Medic m = new Medic(); m.setId("med-1"); m.setCjp("51697");
        Patient p = new Patient(); p.setId("pat-1");
        when(medics.findFirstByCjpAndDeletedAtIsNullOrderByCreatedAtAsc("51697")).thenReturn(Optional.of(m));
        when(patients.findByDocumentNumberAndType("2852833", "UY")).thenReturn(Optional.of(p));

        PaperPrescriptionServiceImpl s = new PaperPrescriptionServiceImpl();
        s.setReposForTest(medics, patients);
        s.setCreateDepsForTest(prescriptions, dispensations, "ph-1");
        return s;
    }

    @Test
    void creaLaRecetaComoPapelYFueraDeTodaNotificacion() throws Exception {
        PrescriptionRepository prescriptions = mock(PrescriptionRepository.class);
        DispensationService dispensations = mock(DispensationService.class);
        when(prescriptions.save(any(Prescription.class))).thenAnswer(i -> {
            Prescription pr = i.getArgument(0);
            if (pr.getId() == null) { pr.setId("presc-1"); }
            return pr;
        });
        when(prescriptions.findPrescriptionsByCodePrefix(anyString())).thenReturn(java.util.List.of());
        DispensationResponse dr = new DispensationResponse();
        dr.setId("disp-created");
        when(dispensations.create(any(DispensationRequest.class))).thenReturn(dr);

        PaperPrescriptionResponse res = svc(prescriptions, dispensations).create(req());

        ArgumentCaptor<Prescription> cap = ArgumentCaptor.forClass(Prescription.class);
        verify(prescriptions).save(cap.capture());
        Prescription pr = cap.getValue();

        assertThat(pr.getOrigin()).isEqualTo("PAPER");
        assertThat(pr.getPaperNumber()).isEqualTo("0648345");
        assertThat(pr.getPaperIssuedAt()).isEqualTo(Instant.parse("2026-07-20T00:00:00Z"));
        assertThat(pr.getCondvtaId()).isEqualTo("11");
        assertThat(pr.getFrecuency()).isEqualTo(8);

        // Fuera de los dos schedulers: nunca PENDING, y el flag de recordatorio ya consumido.
        assertThat(pr.getStatus()).isEqualTo("AVAILABLE");
        assertThat(pr.getDispensationPendingReminderSended()).isEqualTo((byte) 1);
        assertThat(pr.getDateTimeToSend()).isNull();

        // El código sale del generador de siempre.
        assertThat(pr.getCode()).matches("[0-9A-F]{6}-A");
        assertThat(res.getPrescriptionCode()).isEqualTo(pr.getCode());
        assertThat(res.getDispensationId()).isEqualTo("disp-created");
    }

    @Test
    void dispensaPorElCaminoDeSiempreConLaFarmaciaDelUsuario() throws Exception {
        PrescriptionRepository prescriptions = mock(PrescriptionRepository.class);
        DispensationService dispensations = mock(DispensationService.class);
        when(prescriptions.save(any(Prescription.class))).thenAnswer(i -> {
            Prescription pr = i.getArgument(0);
            if (pr.getId() == null) { pr.setId("presc-1"); }
            return pr;
        });
        when(prescriptions.findPrescriptionsByCodePrefix(anyString())).thenReturn(java.util.List.of());
        DispensationResponse dr = new DispensationResponse(); dr.setId("disp-created");
        when(dispensations.create(any(DispensationRequest.class))).thenReturn(dr);

        svc(prescriptions, dispensations).create(req());

        ArgumentCaptor<DispensationRequest> cap = ArgumentCaptor.forClass(DispensationRequest.class);
        verify(dispensations).create(cap.capture());
        DispensationRequest d = cap.getValue();

        // La farmacia sale del usuario autenticado, NUNCA del body.
        assertThat(d.getPharmacyId()).isEqualTo("ph-1");
        assertThat(d.getPrescriptionId()).isEqualTo("presc-1");
        assertThat(d.getDispensedById()).isEqualTo("disp-1");
        assertThat(d.getQty()).isEqualTo(3);
        assertThat(d.getLoteNumber()).isEqualTo("L-123");
        assertThat(d.getProductId()).isEqualTo("100421000179106");
        assertThat(d.getCondvtaId()).isEqualTo("11");
    }
}
```

- [ ] **Step 2: Verificar rojo, después implementar**

Agregar al servicio las dependencias, el seam, y los dos métodos. **El generador de códigos:** `PrescriptionServiceImpl.generateUniqueBaseCode()` es privado; extraelo a un helper reutilizable o replicá su lógica exacta — 6 primeros caracteres de un UUID sin guiones, en mayúsculas, verificando contra `findPrescriptionsByCodePrefix` que no esté tomado, más el sufijo `-A`. **No inventes otro formato**: el código tiene que ser indistinguible del de una receta digital.

```java
  @Autowired private PrescriptionRepository prescriptionRepository;
  @Autowired private DispensationService dispensationService;
  @Autowired private CurrentUserAuthenticatedService currentUser;

  @Override
  @Transactional
  public PaperPrescriptionResponse create(PaperPrescriptionRequest request) throws ResourceNotFoundException {
    // La farmacia sale SIEMPRE del usuario autenticado, nunca del body: si viniera del
    // request, una farmacia podría cargar recetas a nombre de otra.
    String pharmacyId = currentUser.getCurrentPharmacy().getId();

    Medic medic = resolveMedic(request);
    Patient patient = resolvePatient(request);

    Prescription pr = new Prescription();
    pr.setCode(generatePaperCode());
    pr.setMedic(medic);
    pr.setPatient(patient);
    pr.setProductType(request.getProductType());
    pr.setProductId(request.getProductId());
    pr.setCondvtaId(request.getCondvtaId());
    pr.setDnmaLaboratoryId(request.getDnmaLaboratoryId());
    pr.setDose(request.getDose());
    pr.setDoseUnit(request.getDoseUnit());
    pr.setDoseType(request.getDoseType());
    pr.setFrecuency(request.getFrecuency());
    pr.setFrecuencyUnit(request.getFrecuencyUnit());
    pr.setDuration(request.getDuration());
    pr.setDurationUnit(request.getDurationUnit());
    pr.setOrigin("PAPER");
    pr.setPaperNumber(request.getPaperNumber());
    pr.setPaperIssuedAt(request.getPaperIssuedAt());

    // Fuera de los dos schedulers de notificación:
    //  - el de "receta nueva" solo mira status='PENDING', y acá nunca pasa por ahí;
    //  - el de recordatorio pide AVAILABLE + flag en 0 + 48h de antigüedad, y el flag ya va en 1.
    pr.setStatus("AVAILABLE");
    pr.setDispensationPendingReminderSended((byte) 1);
    pr.setDateTimeToSend(null);

    pr = prescriptionRepository.save(pr);

    // Se dispensa por el camino de siempre: trae validación de farmacia activa, tope de cajas,
    // dispensación duplicada, dispensador válido, y deja la receta en DISPENSED.
    DispensationRequest d = new DispensationRequest();
    d.setPrescriptionId(pr.getId());
    d.setPharmacyId(pharmacyId);
    d.setDispensedById(request.getDispensedById());
    d.setQty(request.getQty());
    d.setLoteNumber(request.getLoteNumber());
    d.setLoteExpireAt(request.getLoteExpireAt());
    d.setProductId(request.getProductId());
    d.setProductType(request.getProductType());
    d.setCondvtaId(request.getCondvtaId());
    d.setDnmaLaboratoryId(request.getDnmaLaboratoryId());
    d.setStatus("DISPENSED");
    // dispensedTo* los completa DispensationService desde el paciente de la receta.

    DispensationResponse disp = dispensationService.create(d);

    return new PaperPrescriptionResponse(pr.getCode(), pr.getId(), disp.getId());
  }
```

⚠️ **`DispensationRequest.dispensedToName/Lastname/Document` son `@NotBlank`/`@NotNull`.** Si el objeto se valida por Bean Validation en el camino, va a fallar antes de que el servicio los complete. Verificá si `DispensationService.create` se invoca con validación activa; si sí, completalos desde el paciente resuelto **antes** de llamar. Reportá qué encontraste.

- [ ] **Step 3: La anulación**

```java
  /**
   * Anula una receta de papel cargada por error. NO es borrado lógico: las consultas del
   * Libro Negro filtran `deletedAt IS NULL`, así que borrarla la haría desaparecer del
   * registro — lo contrario de lo que un libro de controlados necesita.
   */
  @Override
  @Transactional
  public void cancel(String prescriptionId) throws ResourceNotFoundException {
    Prescription pr = prescriptionRepository.findById(prescriptionId)
        .orElseThrow(() -> new ResourceNotFoundException("Receta no encontrada :: " + prescriptionId));

    if (!"PAPER".equals(pr.getOrigin())) {
      throw new BusinessRuleException("Solo se pueden anular recetas cargadas en papel.");
    }
    // La farmacia solo puede anular lo que cargó ella.
    String pharmacyId = currentUser.getCurrentPharmacy().getId();
    // (verificar la farmacia de la dispensación asociada — ver nota del step)

    pr.setStatus("CANCELLED");
    prescriptionRepository.save(pr);
  }
```

⚠️ **Falta cerrar dos cosas acá y quiero que las resuelvas vos con el código a la vista, no que las adivine yo:** (a) cómo llegar de la receta a la farmacia de su dispensación para verificar la pertenencia — mirá si `Prescription` tiene la relación inversa `dispensation` mapeada; y (b) cómo poner la dispensación en `CANCELLED` con su `dispensedCancelledById`, que probablemente ya tenga un método en `DispensationService`. **Reportá qué encontraste y qué usaste.** Agregá tests para los dos casos: anular una receta de otra farmacia tiene que fallar, y anular una digital también.

- [ ] **Step 4: Verde y commit**

Run: `./gradlew build`

```bash
git add -A src/main/java/com/recetalia/api/application/service src/test/java/com/recetalia/api/application/service
git commit -m "feat(papel): crear receta de papel y dispensarla por el camino existente"
```

---

### Task 4: Endpoints y seguridad

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/controller/PrescriptionController.java`
- Modify: `src/main/java/com/recetalia/api/application/infrastructure/config/SecurityConfiguration.java`

- [ ] **Step 1: Los dos endpoints**

```java
  @Autowired
  private PaperPrescriptionService paperPrescriptionService;

  /**
   * Carga de una receta emitida en papel. Crea médico, paciente, receta y dispensación.
   * La farmacia sale del usuario autenticado, no del body.
   */
  @PostMapping("/paper")
  @PreAuthorize("hasAuthority('ROLE_ROLE_PHARMACY') or hasAuthority('ROLE_ROLE_PHARMACY_ADMIN')")
  public ResponseEntity<GenericResponse<PaperPrescriptionResponse>> createPaper(
      @Valid @RequestBody PaperPrescriptionRequest request) throws ResourceNotFoundException {
    return ResponseEntity.ok(new GenericResponse<>(
        ResponseStatus.SUCCESS, paperPrescriptionService.create(request)));
  }

  @PostMapping("/paper/{id}/cancel")
  @PreAuthorize("hasAuthority('ROLE_ROLE_PHARMACY') or hasAuthority('ROLE_ROLE_PHARMACY_ADMIN')")
  public ResponseEntity<GenericResponse<Boolean>> cancelPaper(@PathVariable String id)
      throws ResourceNotFoundException {
    paperPrescriptionService.cancel(id);
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, true));
  }
```

⚠️ **Verificá el prefijo del rol.** En este proyecto conviven dos formas: los `@PreAuthorize` de `PrescriptionController` usan `hasAuthority('ROLE_MEDICAL_PROVIDER')` (un solo prefijo) mientras los matchers de `SecurityConfiguration` usan `hasAuthority("ROLE_ROLE_MANAGEMENT")` (doble, por el quirk del converter de JWT). **Mirá cuál aplica en los `@PreAuthorize` existentes y usá esa**, o el endpoint va a rechazar a todo el mundo. Reportá cuál era.

- [ ] **Step 2: Endurecer el Excel de controlados**

El endpoint `/api/dispensations/controlled-medications/excel` quedó en `authenticated()` desde julio: hoy cualquier usuario logueado, de cualquier rol, puede bajarse el listado de medicamentos controlados de cualquier farmacia. Restringirlo a los roles de farmacia y al QF.

Agregá el `@PreAuthorize` correspondiente en su método del controller (o el matcher en `SecurityConfiguration`, siguiendo lo que ya use ese endpoint), y **verificá que el parámetro `pharmacyId` esté validado contra el usuario**: si no lo está, decilo — sería el mismo agujero por otra puerta.

- [ ] **Step 3: Build y commit**

```bash
./gradlew build
git add src/main/java/com/recetalia/api/application/controller/PrescriptionController.java \
        src/main/java/com/recetalia/api/application/infrastructure/config/SecurityConfiguration.java
git commit -m "feat(papel): endpoints de carga y anulacion, y endurecer el Excel de controlados"
```

---

### Task 5: El Nº de talonario en el Excel

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/impl/ControlledMedicationsExcelServiceImpl.java`

- [ ] **Step 1: Agregar la columna**

El servicio arma cabeceras y filas con POI. Agregá una columna **"Nº receta"** al lado de la del código, alimentada con `row.getPrescriptionPaperNumber()` (ya viaja en la proyección desde el Plan 3). Vacía para las digitales.

⚠️ Si las cabeceras y las celdas se arman con índices numéricos, **insertar una columna en el medio desplaza todas las siguientes**: revisá que no queden desalineadas. Si el riesgo es alto, agregala al final y decilo.

- [ ] **Step 2: Build y commit**

```bash
./gradlew build
git add src/main/java/com/recetalia/api/application/service/impl/ControlledMedicationsExcelServiceImpl.java
git commit -m "feat(papel): columna de Nro de talonario en el Excel de controlados"
```

---

### Task 6: Validación contra DEV

**Files:** ninguno — es verificación.

- [ ] **Step 1: Deployar api-rest al .98**

```bash
cd /Users/pablo/iwtg/recetalia-workspace
rsync -az --delete --exclude .git --exclude build --exclude .gradle \
  recetalia-api-rest/ root@138.197.150.98:/opt/recetalia/recetalia-api-rest/
ssh root@138.197.150.98 "cd /opt/recetalia/deploy-recetalia && \
  docker compose build recetalia-api-rest && docker compose up -d --no-deps recetalia-api-rest"
```

⚠️ `--no-deps`: un `up -d` a secas recrea nginx y rompe PRE.
⚠️ **Mirá los logs de arranque.** La derived query `findFirstByCjpAndDeletedAtIsNullOrderByCreatedAtAsc` se valida al levantar el contexto, no al compilar: si el nombre está mal, la app no arranca.

- [ ] **Step 2: Cargar una receta de papel de verdad**

Con el token de `test@test.com` / `Recetalia2026!` (rol `ROLE_PHARMACY`, farmacia "Test"). Necesitás un `dispensedById` real: sacalo de la farmacia. Un producto real de DEV: `productType=AMP`, `productId=100421000179106`, `condvtaId=11`, `dnmaLaboratoryId=188`.

Verificá en la respuesta que el **código generado tenga el formato de siempre** (6 hex + `-A`).

- [ ] **Step 3: Verificar que quedó bien y que NO notificó**

```bash
ssh root@138.197.150.98 "docker exec recetalia-mysql mysql -uroot -pRootDev98_p3Wn8sLzQ -e \"
  SELECT code, status, origin, paperNumber, paperIssuedAt, dispensationPendingReminderSended, dateTimeToSend
  FROM recetali_receta.prescription WHERE origin='PAPER' ORDER BY createdAt DESC LIMIT 3;\""
```

Esperado: `status = DISPENSED`, `origin = PAPER`, el Nº cargado, el flag en `1` y `dateTimeToSend` en NULL.

**Y lo más importante:** confirmá que no se generó ningún mensaje. Mirá la tabla `whatsapp_message` antes y después, y que el paciente creado no tenga teléfono.

- [ ] **Step 4: Que aparezca donde tiene que aparecer**

La receta nueva tiene que salir en: el Libro Negro de Farmacias (`/api/dispensations/search?condvtaId=GREEN&pharmacyId=...`), el listado del QF si esa farmacia tiene D.T., y el Excel de controlados **con su Nº en la columna nueva**. Bajá el Excel y verificá el contenido, no solo el HTTP 200.

- [ ] **Step 5: La anulación**

Anulá la receta cargada y verificá que queda `CANCELLED` en receta y dispensación, y que **sigue apareciendo** en el Libro Negro (tachada, no desaparecida).

- [ ] **Step 6: Regresión y limpieza**

Los 5 frontends en 200, ningún contenedor caído salvo `observatorio-cpa`. Y **dejá anotado qué datos de prueba creaste** (receta, médico, paciente) por si hay que limpiarlos.

---

## Lo que queda después de este plan

**Plan 4b** — la pantalla "Mantenimiento de Libro Negro" en `farmacias-recetalia-app`: el formulario con buscador DNMA, el listado de lo cargado en papel, la anulación, y el Nº de talonario en la columna Código del Libro Negro.
