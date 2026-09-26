# Tope de cajas al dispensar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Topear la cantidad de cajas al dispensar según posología × unidades por caja de la presentación, en UI (clamp) y API (rechazo 400).

**Architecture:** El dato `vmpp.CANTIDAD` (unidades por caja) se expone en la cadena transversal-api → api-rest → frontend agregándolo al join de AMPPs. El cálculo del tope es una función pura duplicada con la misma semántica en Java (`DispensationCapCalculator`) y TS (`dispensation-cap.util`). El backend valida en `DispensationServiceImpl.create()` consultando CANTIDAD por SQL directo a DNMA; si el tope no es computable, no se topea (fallback decidido en la spec).

**Tech Stack:** Spring Boot 3 (api-rest JPA, transversal WebFlux/R2DBC), Angular 18 NgModule.

**Spec:** [2026-06-12-tope-cajas-dispensacion-design.md](2026-06-12-tope-cajas-dispensacion-design.md)

**Regla de flujo:** NO mergear a `2.x.y` — todo queda en las branches `fix/ajustes-farmacias-2026-06` hasta el OK explícito de Pablo. El deploy a PRE (si se pide) sale desde la branch.

**Fórmula de referencia:**

```
horasTratamiento   = esCrónica ? 30×24 : duration(días) × 24
tomas              = ceil(horasTratamiento / frecuency(horas))
unidadesNecesarias = tomas × dose
maxCajas           = ceil(unidadesNecesarias / unidadesPorCaja)   // unidadesPorCaja = vmpp.CANTIDAD
```

Caso de control: 1 c/8h × 8 días, caja de 20 → 24 unidades → max 2 cajas.

---

### Task 1: Branches de trabajo en api-rest y transversal

(`fix/ajustes-farmacias-2026-06` ya existe en farmacias-recetalia-app.)

- [ ] **Step 1: Crear branches desde `2.x.y`**

```bash
for r in recetalia-api-rest transversal-recetalia-api; do
  git -C /Users/pablo/iwtg/recetalia-workspace/$r fetch origin 2.x.y
  git -C /Users/pablo/iwtg/recetalia-workspace/$r checkout 2.x.y
  git -C /Users/pablo/iwtg/recetalia-workspace/$r pull origin 2.x.y
  git -C /Users/pablo/iwtg/recetalia-workspace/$r checkout -b fix/ajustes-farmacias-2026-06
done
```

Expected: ambas branches creadas, working trees limpios.

---

### Task 2: transversal-recetalia-api — exponer `cantidad` en la búsqueda de AMPPs

**Files:**
- Modify: `infrastructure/driven-adapters/dnma-db/src/main/java/com/recetalia/dnmadb/entity/Ampp.java`
- Modify: `infrastructure/driven-adapters/dnma-db/src/main/java/com/recetalia/dnmadb/repository/AmppRepository.java` (query `findByAmpId`)
- Modify: `domain/model/src/main/java/com/recetalia/model/dnmadb/AmppDnmaDto.java`

- [ ] **Step 1: Agregar campo `cantidad` a la entidad `Ampp`**

Junto a los campos alias existentes (`laboratorioId`, `condvtaId`):

```java
  @Column("CANTIDAD")          // unidades por caja, viene del join con vmpp
  private String cantidad;
```

- [ ] **Step 2: Sumar el join a `vmpp` en `AmppRepository.findByAmpId`**

Reemplazar la query por:

```java
  @Query("""
              SELECT a.AMPP_Id,
                     a.AMPP_DSC,
                     a.AMPP_Estado,
                     a.AMPP_EstValidacion,
                     a.COMERCIALIZADO,
                     a.DESCRIPCIONES,
                     a.AMP_Id,
                     a.VMPP_Id,
                     amp.LABORATORIO_Id,
                     vmp.CONDVTA_Id,
                     vmpp.CANTIDAD
              FROM ampp a
                       LEFT JOIN amp ON amp.AMP_Id = a.AMP_Id
                       INNER JOIN vmp ON vmp.VMP_Id = amp.VMP_Id
                       LEFT JOIN vmpp ON vmpp.VMPP_Id = a.VMPP_Id
              WHERE a.AMP_Id = :ampId
          """)
  Flux<Ampp> findByAmpId(String ampId);
```

(LEFT JOIN para no perder AMPPs sin VMPP — fallback "no topear".) Actualizar el javadoc del método mencionando que también trae `CANTIDAD` (unidades por envase).

- [ ] **Step 3: Agregar campo `cantidad` a `AmppDnmaDto`**

```java
  private String cantidad;           // Units per pack (vmpp.CANTIDAD), nullable
```

El mapper MapStruct entity→DTO (`dnmadb/mapper/AmppMapper`) mapea por nombre; no requiere cambios. (El otro mapper `model/mapper/AmppDnmaMapper` es del path XML de migración y deja `cantidad` en null — correcto.)

- [ ] **Step 4: Build**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/transversal-recetalia-api
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew build -x test
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(ampp): exponer vmpp.CANTIDAD (unidades por caja) en search por AMP"
```

---

### Task 3: recetalia-api-rest — passthrough de `cantidad` en `AmppDto`

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/infrastructure/adapter/transversal/dto/AmppDto.java`

- [ ] **Step 1: Agregar campo**

```java
    private String cantidad;   // unidades por caja (vmpp.CANTIDAD), nullable
```

Jackson lo deserializa por nombre desde la respuesta del transversal y lo serializa hacia el frontend. Sin más cambios.

- [ ] **Step 2: Commit**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
git add src/main/java/com/recetalia/api/application/infrastructure/adapter/transversal/dto/AmppDto.java
git commit -m "feat(ampp): campo cantidad (unidades por caja) en AmppDto"
```

---

### Task 4: recetalia-api-rest — `DispensationCapCalculator` (TDD)

**Files:**
- Create: `src/main/java/com/recetalia/api/application/service/impl/DispensationCapCalculator.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/DispensationCapCalculatorTest.java`

- [ ] **Step 1: Escribir el test (falla)**

```java
package com.recetalia.api.application.service.impl;

import org.junit.jupiter.api.Test;

import java.util.OptionalInt;

import static org.junit.jupiter.api.Assertions.*;

class DispensationCapCalculatorTest {

  @Test
  void agudaEjemploDeControl() {
    // 1 comp c/8h × 8 días = 24 unidades; caja de 20 → 2 cajas
    assertEquals(OptionalInt.of(2), DispensationCapCalculator.maxBoxes(1, 8, 8, false, "20"));
  }

  @Test
  void cronicaTopeaUnMesDe30Dias() {
    // 1 c/8h crónica → 90 tomas/mes; caja de 20 → 5 cajas (duration en meses se ignora)
    assertEquals(OptionalInt.of(5), DispensationCapCalculator.maxBoxes(1, 8, 2, true, "20"));
  }

  @Test
  void frecuenciaNoDivisoraRedondeaTomasHaciaArriba() {
    // c/7h × 3 días = ceil(72/7) = 11 tomas; caja de 10 → 2 cajas
    assertEquals(OptionalInt.of(2), DispensationCapCalculator.maxBoxes(1, 7, 3, false, "10"));
  }

  @Test
  void doseFraccionada() {
    // 0.5 c/12h × 10 días = 20 tomas × 0.5 = 10 unidades; caja de 30 → 1 caja
    assertEquals(OptionalInt.of(1), DispensationCapCalculator.maxBoxes(0.5, 12, 10, false, "30"));
  }

  @Test
  void cantidadConDecimales() {
    assertEquals(OptionalInt.of(2), DispensationCapCalculator.maxBoxes(1, 8, 8, false, "20.0"));
  }

  @Test
  void sinDatosNoTopea() {
    assertTrue(DispensationCapCalculator.maxBoxes(0, 8, 8, false, "20").isEmpty());      // dose 0
    assertTrue(DispensationCapCalculator.maxBoxes(1, null, 8, false, "20").isEmpty());   // sin frecuencia
    assertTrue(DispensationCapCalculator.maxBoxes(1, 0, 8, false, "20").isEmpty());      // frecuencia 0
    assertTrue(DispensationCapCalculator.maxBoxes(1, 8, null, false, "20").isEmpty());   // sin duración (aguda)
    assertTrue(DispensationCapCalculator.maxBoxes(1, 8, 0, false, "20").isEmpty());      // duración 0
    assertTrue(DispensationCapCalculator.maxBoxes(1, 8, 8, false, null).isEmpty());      // sin cantidad
    assertTrue(DispensationCapCalculator.maxBoxes(1, 8, 8, false, "").isEmpty());        // cantidad vacía
    assertTrue(DispensationCapCalculator.maxBoxes(1, 8, 8, false, "abc").isEmpty());     // cantidad no numérica
    assertTrue(DispensationCapCalculator.maxBoxes(1, 8, 8, false, "0").isEmpty());       // cantidad 0
  }

  @Test
  void cronicaNoNecesitaDuracion() {
    assertEquals(OptionalInt.of(5), DispensationCapCalculator.maxBoxes(1, 8, null, true, "20"));
  }
}
```

- [ ] **Step 2: Correr el test — debe fallar**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew test --tests "com.recetalia.api.application.service.impl.DispensationCapCalculatorTest"
```

Expected: FAIL (clase no existe / no compila).

- [ ] **Step 3: Implementación mínima**

```java
package com.recetalia.api.application.service.impl;

import java.util.OptionalInt;

/**
 * Tope de cajas a dispensar según posología × unidades por caja.
 * Misma semántica que dispensation-cap.util.ts en farmacias-recetalia-app.
 * Devuelve empty cuando el tope no es computable (fallback: no topear).
 */
public final class DispensationCapCalculator {

  private static final int HOURS_PER_DAY = 24;
  private static final int DAYS_PER_MONTH = 30; // mes crónico fijo de 30 días

  private DispensationCapCalculator() {
  }

  /**
   * @param dose            unidades por toma (admite fracciones de 0.5)
   * @param frecuencyHours  horas entre tomas (la prescripción siempre usa horas)
   * @param durationDays    duración en días (ignorada si isCronic: el tope crónico es por mes)
   * @param isCronic        receta crónica → base de un mes (30 días)
   * @param unitsPerBoxRaw  vmpp.CANTIDAD como string, nullable
   * @return máximo de cajas dispensables, o empty si falta algún dato
   */
  public static OptionalInt maxBoxes(double dose, Integer frecuencyHours, Integer durationDays,
                                     boolean isCronic, String unitsPerBoxRaw) {
    if (dose <= 0 || frecuencyHours == null || frecuencyHours <= 0) {
      return OptionalInt.empty();
    }
    int treatmentHours;
    if (isCronic) {
      treatmentHours = DAYS_PER_MONTH * HOURS_PER_DAY;
    } else {
      if (durationDays == null || durationDays <= 0) {
        return OptionalInt.empty();
      }
      treatmentHours = durationDays * HOURS_PER_DAY;
    }
    double unitsPerBox = parsePositive(unitsPerBoxRaw);
    if (unitsPerBox <= 0) {
      return OptionalInt.empty();
    }
    long doses = (long) Math.ceil((double) treatmentHours / frecuencyHours);
    double unitsNeeded = doses * dose;
    return OptionalInt.of((int) Math.ceil(unitsNeeded / unitsPerBox));
  }

  private static double parsePositive(String raw) {
    if (raw == null || raw.isBlank()) {
      return -1;
    }
    try {
      return Double.parseDouble(raw.trim());
    } catch (NumberFormatException e) {
      return -1;
    }
  }
}
```

- [ ] **Step 4: Correr el test — debe pasar**

```bash
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew test --tests "com.recetalia.api.application.service.impl.DispensationCapCalculatorTest"
```

Expected: BUILD SUCCESSFUL, 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/impl/DispensationCapCalculator.java \
        src/test/java/com/recetalia/api/application/service/impl/DispensationCapCalculatorTest.java
git commit -m "feat(dispensation): calculadora de tope de cajas según posología (con tests)"
```

---

### Task 5: recetalia-api-rest — validación en el create de dispensación

**Files:**
- Create: `src/main/java/com/recetalia/api/application/infrastructure/exception/BusinessRuleException.java`
- Modify: `src/main/java/com/recetalia/api/application/infrastructure/exception/GlobalExceptionHandler.java`
- Modify: `src/main/java/com/recetalia/api/application/service/DnmaDatabaseService.java`
- Modify: `src/main/java/com/recetalia/api/application/service/impl/DnmaDatabaseServiceImpl.java`
- Create: `src/main/java/com/recetalia/api/application/service/impl/DispensationCapValidator.java`
- Modify: `src/main/java/com/recetalia/api/application/service/impl/DispensationServiceImpl.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/DispensationCapValidatorTest.java`

- [ ] **Step 1: `BusinessRuleException`**

```java
package com.recetalia.api.application.infrastructure.exception;

/**
 * Violación de una regla de negocio; el mensaje es propio (seguro de devolver al cliente) → 400.
 */
public class BusinessRuleException extends RuntimeException {
  public BusinessRuleException(String message) {
    super(message);
  }
}
```

- [ ] **Step 2: Handler → 400 con mensaje**

En `GlobalExceptionHandler`, antes del catch-all:

```java
  /**
   * Regla de negocio violada → 400. El mensaje es generado por nosotros (no filtra internals).
   */
  @ExceptionHandler(BusinessRuleException.class)
  public ResponseEntity<GenericResponse<String>> handleBusinessRule(BusinessRuleException ex, WebRequest request) {
    logger.warn("Regla de negocio rechazada: {}", ex.getMessage());
    GenericResponse<String> response = new GenericResponse<>(ResponseStatus.ERROR, ex.getMessage());
    return new ResponseEntity<>(response, HttpStatus.BAD_REQUEST);
  }
```

- [ ] **Step 3: Consulta de CANTIDAD por AMPP**

En la interfaz `DnmaDatabaseService` agregar:

```java
  public String fetchUnitsPerBoxByAmppId(String amppId);
```

En `DnmaDatabaseServiceImpl` (usa el `dnmaDataSource` pooled existente; PreparedStatement, no concatenación):

```java
    /**
     * Unidades por caja (vmpp.CANTIDAD) para un AMPP. Null si no se encuentra o ante error
     * (el caller no topea en ese caso).
     */
    @Override
    public String fetchUnitsPerBoxByAmppId(String amppId) {
        if (amppId == null || amppId.isBlank()) {
            return null;
        }
        String query = "SELECT v.CANTIDAD FROM ampp a INNER JOIN vmpp v ON v.VMPP_Id = a.VMPP_Id WHERE a.AMPP_Id = ?";
        try (Connection connection = dnmaDataSource.getConnection();
             java.sql.PreparedStatement ps = connection.prepareStatement(query)) {
            ps.setString(1, amppId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getString("CANTIDAD");
                }
            }
        } catch (Exception e) {
            System.err.println("DnmaDatabaseService.fetchUnitsPerBoxByAmppId error: " + e.getMessage());
        }
        return null;
    }
```

- [ ] **Step 4: Test del validador (falla — la clase no existe)**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.dto.request.DispensationRequest;
import com.recetalia.api.application.dto.response.PrescriptionResponse;
import com.recetalia.api.application.infrastructure.exception.BusinessRuleException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class DispensationCapValidatorTest {

  private com.recetalia.api.application.service.DnmaDatabaseService dnma;
  private DispensationCapValidator validator;
  private DispensationRequest request;
  private PrescriptionResponse prescription;

  @BeforeEach
  void setUp() {
    dnma = mock(com.recetalia.api.application.service.DnmaDatabaseService.class);
    validator = new DispensationCapValidator(dnma);

    request = new DispensationRequest();
    request.setProductId("ampp-1");

    // 1 comp c/8h × 8 días → con caja de 20, max 2
    prescription = new PrescriptionResponse();
    prescription.setDose(1);
    prescription.setFrecuency(8);
    prescription.setDuration(8);
    prescription.setIsCronic(false);
  }

  @Test
  void rechazaQtySobreElTope() {
    when(dnma.fetchUnitsPerBoxByAmppId("ampp-1")).thenReturn("20");
    request.setQty(3);
    BusinessRuleException ex = assertThrows(BusinessRuleException.class,
        () -> validator.validate(request, prescription));
    assertTrue(ex.getMessage().contains("máximo 2"));
  }

  @Test
  void aceptaQtyDentroDelTope() {
    when(dnma.fetchUnitsPerBoxByAmppId("ampp-1")).thenReturn("20");
    request.setQty(2);
    assertDoesNotThrow(() -> validator.validate(request, prescription));
  }

  @Test
  void sinCantidadNoTopea() {
    when(dnma.fetchUnitsPerBoxByAmppId("ampp-1")).thenReturn(null);
    request.setQty(99);
    assertDoesNotThrow(() -> validator.validate(request, prescription));
  }

  @Test
  void errorDeDnmaNoTopea() {
    when(dnma.fetchUnitsPerBoxByAmppId(anyString())).thenThrow(new RuntimeException("db down"));
    request.setQty(99);
    assertDoesNotThrow(() -> validator.validate(request, prescription));
  }

  @Test
  void sinQtyOSinProductoNoTopea() {
    request.setQty(null);
    assertDoesNotThrow(() -> validator.validate(request, prescription));

    request.setQty(99);
    request.setProductId(null);
    assertDoesNotThrow(() -> validator.validate(request, prescription));
  }

  @Test
  void cronicaTopeaPorMes() {
    // 1 c/8h crónica → 90 unidades/mes; caja de 20 → max 5
    when(dnma.fetchUnitsPerBoxByAmppId("ampp-1")).thenReturn("20");
    prescription.setIsCronic(true);
    prescription.setDuration(2); // meses, ignorado por el tope mensual
    request.setQty(6);
    assertThrows(BusinessRuleException.class, () -> validator.validate(request, prescription));
    request.setQty(5);
    assertDoesNotThrow(() -> validator.validate(request, prescription));
  }
}
```

Correr y verificar que falla:

```bash
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew test --tests "com.recetalia.api.application.service.impl.DispensationCapValidatorTest"
```

Expected: FAIL (DispensationCapValidator no existe).

Nota: `DispensationRequest.qty` es `Integer` con default `= 1`; el test lo pisa con `setQty(null)` explícito para el caso "sin qty". `PrescriptionResponse` es Lombok `@Data` (setters disponibles; `dose` es `double`).

- [ ] **Step 5: Implementar `DispensationCapValidator`**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.dto.request.DispensationRequest;
import com.recetalia.api.application.dto.response.PrescriptionResponse;
import com.recetalia.api.application.infrastructure.exception.BusinessRuleException;
import com.recetalia.api.application.service.DnmaDatabaseService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.util.OptionalInt;

/**
 * Valida que la cantidad a dispensar no supere el tope por posología.
 * Si el tope no es computable (datos faltantes o error consultando DNMA), no valida.
 */
@Component
public class DispensationCapValidator {

  private static final Logger logger = LoggerFactory.getLogger(DispensationCapValidator.class);

  private final DnmaDatabaseService dnmaDatabaseService;

  public DispensationCapValidator(DnmaDatabaseService dnmaDatabaseService) {
    this.dnmaDatabaseService = dnmaDatabaseService;
  }

  public void validate(DispensationRequest request, PrescriptionResponse prescription) {
    if (request.getQty() == null || request.getProductId() == null || request.getProductId().isBlank()) {
      return;
    }
    String unitsPerBox;
    try {
      unitsPerBox = dnmaDatabaseService.fetchUnitsPerBoxByAmppId(request.getProductId());
    } catch (Exception e) {
      logger.warn("No se pudo obtener CANTIDAD para AMPP {}: {}", request.getProductId(), e.getMessage());
      return;
    }
    OptionalInt maxBoxes = DispensationCapCalculator.maxBoxes(
        prescription.getDose(),
        prescription.getFrecuency(),
        prescription.getDuration(),
        Boolean.TRUE.equals(prescription.getIsCronic()),
        unitsPerBox);
    if (maxBoxes.isPresent() && request.getQty() > maxBoxes.getAsInt()) {
      throw new BusinessRuleException(
          "La cantidad supera el máximo permitido por la posología: máximo "
              + maxBoxes.getAsInt() + " cajas");
    }
  }
}
```

- [ ] **Step 6: Inyectar y llamar en `DispensationServiceImpl.create()`**

Agregar el campo autowired junto a los existentes:

```java
  @Autowired
  private DispensationCapValidator dispensationCapValidator;
```

En `create()`, inmediatamente después de obtener la prescripción (ANTES del branch de `CANCELLED`, para cubrir también la re-dispensación que deriva en `update`):

```java
    PrescriptionResponse prescription = prescriptionService.getPrescriptionById(request.getPrescriptionId());

    dispensationCapValidator.validate(request, prescription);
```

- [ ] **Step 7: Correr tests — deben pasar**

```bash
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew test --tests "com.recetalia.api.application.service.impl.DispensationCapValidatorTest" --tests "com.recetalia.api.application.service.impl.DispensationCapCalculatorTest"
```

Expected: PASS (6 + 8 tests). Luego build completo: `JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew build -x test` → BUILD SUCCESSFUL.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(dispensation): rechazar qty sobre el tope de posología (400 BusinessRuleException)"
```

---

### Task 6: farmacias-recetalia-app — clamp en UI + leyenda

**Files:**
- Create: `src/app/shared/utils/dispensation-cap.util.ts`
- Test: `src/app/shared/utils/dispensation-cap.util.spec.ts`
- Modify: `src/app/model/response/ampp-response.ts`
- Modify: `src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.ts`
- Modify: `src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.html`

- [ ] **Step 1: Spec del util (falla)**

`src/app/shared/utils/dispensation-cap.util.spec.ts`:

```typescript
import { computeDispensationCap } from './dispensation-cap.util';

describe('computeDispensationCap', () => {
  it('caso de control agudo: 1 c/8h × 8 días, caja de 20 → 2 cajas (24 unidades)', () => {
    expect(computeDispensationCap({ dose: 1, frecuency: 8, duration: 8, isCronic: false }, '20'))
      .toEqual({ maxBoxes: 2, units: 24 });
  });

  it('crónica topea un mes de 30 días e ignora duration', () => {
    expect(computeDispensationCap({ dose: 1, frecuency: 8, duration: 2, isCronic: true }, '20'))
      .toEqual({ maxBoxes: 5, units: 90 });
  });

  it('frecuencia no divisora redondea tomas hacia arriba', () => {
    expect(computeDispensationCap({ dose: 1, frecuency: 7, duration: 3, isCronic: false }, '10'))
      .toEqual({ maxBoxes: 2, units: 11 });
  });

  it('dose fraccionada', () => {
    expect(computeDispensationCap({ dose: 0.5, frecuency: 12, duration: 10, isCronic: false }, '30'))
      .toEqual({ maxBoxes: 1, units: 10 });
  });

  it('sin datos devuelve null (no topear)', () => {
    expect(computeDispensationCap({ dose: 0, frecuency: 8, duration: 8 }, '20')).toBeNull();
    expect(computeDispensationCap({ dose: 1, frecuency: 0, duration: 8 }, '20')).toBeNull();
    expect(computeDispensationCap({ dose: 1, frecuency: 8, duration: 0, isCronic: false }, '20')).toBeNull();
    expect(computeDispensationCap({ dose: 1, frecuency: 8, duration: 8 }, undefined)).toBeNull();
    expect(computeDispensationCap({ dose: 1, frecuency: 8, duration: 8 }, 'abc')).toBeNull();
    expect(computeDispensationCap({ dose: 1, frecuency: 8, duration: 8 }, '0')).toBeNull();
  });
});
```

- [ ] **Step 2: Implementar el util**

`src/app/shared/utils/dispensation-cap.util.ts`:

```typescript
/**
 * Tope de cajas a dispensar según posología × unidades por caja (vmpp.CANTIDAD).
 * Misma semántica que DispensationCapCalculator en recetalia-api-rest.
 * Devuelve null cuando el tope no es computable (fallback: no topear).
 */
export interface DispensationCapInfo {
  maxBoxes: number;
  units: number; // unidades necesarias según posología (para la leyenda)
}

const HOURS_PER_DAY = 24;
const DAYS_PER_MONTH = 30; // mes crónico fijo de 30 días

export function computeDispensationCap(
  posology: { dose?: number; frecuency?: number; duration?: number; isCronic?: boolean },
  unitsPerBoxRaw?: string | null
): DispensationCapInfo | null {
  const unitsPerBox = parseFloat(unitsPerBoxRaw ?? '');
  if (!isFinite(unitsPerBox) || unitsPerBox <= 0) return null;

  const dose = posology.dose ?? 0;
  const frecuencyHours = posology.frecuency ?? 0;
  if (dose <= 0 || frecuencyHours <= 0) return null;

  const treatmentHours = posology.isCronic
    ? DAYS_PER_MONTH * HOURS_PER_DAY
    : (posology.duration ?? 0) * HOURS_PER_DAY;
  if (treatmentHours <= 0) return null;

  const doses = Math.ceil(treatmentHours / frecuencyHours);
  const units = doses * dose;
  return { maxBoxes: Math.ceil(units / unitsPerBox), units };
}
```

- [ ] **Step 3: Correr el spec**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/farmacias-recetalia-app
npm test -- --watch=false --browsers=ChromeHeadless
```

Expected: el suite `computeDispensationCap` en verde (si hay specs preexistentes rotos no relacionados, ignorarlos pero dejarlo anotado).

- [ ] **Step 4: Campo `cantidad` en los modelos**

En `src/app/model/response/ampp-response.ts` y en la interfaz `Ampp` de `prescription-search.component.ts` (línea ~22):

```typescript
  cantidad?: string; // unidades por caja (vmpp.CANTIDAD), puede faltar
```

- [ ] **Step 5: Lógica en el componente**

En `prescription-search.component.ts`:

1. Import: `import { computeDispensationCap, DispensationCapInfo } from '../../../../../shared/utils/dispensation-cap.util';`
2. Al tipo del grupo (`groupedPrescriptions`) agregar: `capInfo?: DispensationCapInfo | null`.
3. En `groupPrescriptionsByCode()`, en el objeto literal del grupo nuevo, agregar `capInfo: null,`.
4. Métodos nuevos (debajo de `decrement`):

```typescript
  recomputeCap(groupKey: string): void {
    const group = this.groupedPrescriptions[groupKey];
    const ampp = group.sustituteSelect ? group.selectAmppSustitute : group.selectAmpp;
    const rx = group.prescriptions[0];
    group.capInfo = ampp && rx ? computeDispensationCap(rx, ampp.cantidad) : null;
    this.clampAmount(groupKey);
  }

  clampAmount(groupKey: string): void {
    const group = this.groupedPrescriptions[groupKey];
    const max = group.capInfo?.maxBoxes;
    let amount = group.sustituteSelect ? group.amppSustituteAmount : group.amppAmount;
    if (!amount || amount < 1) amount = 1;
    if (max && amount > max) amount = max;
    if (group.sustituteSelect) {
      group.amppSustituteAmount = amount;
    } else {
      group.amppAmount = amount;
    }
  }

  onSubstituteToggle(groupKey: string, value: boolean): void {
    this.groupedPrescriptions[groupKey].sustituteSelect = value;
    this.recomputeCap(groupKey);
  }
```

5. En `increment()` (respetar el tope con los botones +/-):

```typescript
  increment(groupKey: string): void {
    this.groupedPrescriptions[groupKey].amppAmount++;
    this.clampAmount(groupKey);
  }
```

6. En `dispense()`, después del guard de `chosenAmpp` (línea ~347), recalcular antes de leer qty (cubre el caso de tipear y clickear Dispensar sin blur):

```typescript
    // Recalcular tope con la presentación elegida y clampear la cantidad
    this.recomputeCap(groupKey);
```

- [ ] **Step 6: Template**

En `prescription-search.component.html`:

1. Dropdown normal (línea ~129): agregar `(onChange)="recomputeCap(groupKey)"`.
2. Input normal (línea ~137): agregar `min="1"`, `[attr.max]="groupedPrescriptions[groupKey].capInfo?.maxBoxes ?? null"` y `(change)="clampAmount(groupKey)"`; debajo, la leyenda:

```html
                    <div class="col-4">
                      <label class="form-label">Cantidad {{ isGroupChronic(groupKey) ? 'por mes' : '' }}: </label>
                      <input type="number" min="1" class="form-control text-center"
                        [attr.max]="groupedPrescriptions[groupKey].capInfo?.maxBoxes ?? null"
                        [(ngModel)]="groupedPrescriptions[groupKey].amppAmount"
                        (change)="clampAmount(groupKey)" style="font-size: 24px;" />
                      <small class="text-muted d-block mt-1" *ngIf="groupedPrescriptions[groupKey].capInfo as cap">
                        Máximo {{ cap.maxBoxes }} {{ cap.maxBoxes === 1 ? 'caja' : 'cajas' }}
                        ({{ cap.units }} unidades según posología)
                      </small>
                    </div>
```

3. Checkbox de sustituto (línea ~145-147): partir el banana-binding para recalcular al togglear:

```html
                  <input type="checkbox" class="form-check-input"
                    id="substituteToggle{{ groupIndex }}_{{ prescriptionIndex }}"
                    [ngModel]="groupedPrescriptions[groupKey].sustituteSelect"
                    (ngModelChange)="onSubstituteToggle(groupKey, $event)" />
```

4. Dropdown sustituto (línea ~171): agregar `(onChange)="recomputeCap(groupKey)"`.
5. Input sustituto (línea ~179): mismos cambios que el input normal pero sobre `amppSustituteAmount`, con la misma leyenda (el `capInfo` es compartido — refleja la presentación activa según el toggle).

- [ ] **Step 7: Build**

```bash
npm run build
```

Expected: build SSR sin errores de template (strictTemplates activo).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(dispensar): topear cantidad de cajas según posología y presentación"
```

---

### Task 7: Sync de docs

**Files:**
- Modify: `farmacias-recetalia-app/doc/specs/api-contract.md` — campo `cantidad` en la respuesta de `/ampp/search/amp` y el 400 de `POST /dispensations` por tope de posología.
- Modify: `recetalia-api-rest/doc/specs/api-contract.md` (si documenta esos endpoints) — ídem.
- Modify: `transversal-recetalia-api/doc/specs/api-contract.md` — `cantidad` en el search de AMPPs.

- [ ] **Step 1: Actualizar las 3 specs** con los cambios de contrato (leer cada archivo y tocar solo las secciones de AMPP search y dispensations; estilo existente).

- [ ] **Step 2: Commit en cada repo**

```bash
# en cada repo tocado
git add doc/specs/api-contract.md && git commit -m "docs: cantidad en AMPP search + tope de cajas en dispensación"
```

---

### Task 8: Validación en PRE (cuando Pablo lo pida — NO mergear)

- [ ] **Step 1: Deploy desde la branch** (3 imágenes; comandos de la memoria de deploy):

```bash
# en cada repo (transversal-recetalia-api, recetalia-api-rest, farmacias-recetalia-app):
docker buildx build --builder f2a-builder --platform linux/amd64 --build-arg CONFIGURATION=preprod \
  -t registrypre.recetadigital.uy/recetalia/<app>:latest --push .
# en el server root@138.197.150.98:
cd /opt/recetalia/deploy-recetalia && docker pull <img> && docker compose up -d --force-recreate <svc>
```

- [ ] **Step 2: Contrato** — login API (`loginBack`, quirk del campo `info`) y verificar que `GET /api/ampp/search/amp?ampId=...` devuelve `cantidad` numérica.

- [ ] **Step 3: Caso del screenshot** — receta de clonazepam 1 c/8h × 8 días, presentación de 20: tipear 4 → clamp a 2 con leyenda "Máximo 2 cajas (24 unidades según posología)"; intento por curl con `qty: 3` → 400 con el mensaje del tope.

- [ ] **Step 4: Crónica** — receta de prueba crónica: el tope refleja un mes; dispensar meses sucesivos mantiene el mismo tope.

- [ ] **Step 5: Avisar a Pablo** — el merge de las branches `fix/ajustes-farmacias-2026-06` queda pendiente de su OK explícito.
