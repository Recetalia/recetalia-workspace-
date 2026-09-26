# Dashboard de KPIs en Gestión — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar un Dashboard de KPIs a nivel plataforma en gestion-recetadigital-app, servido por un endpoint de agregación nuevo en recetalia-api-rest, y hacerlo la pantalla por defecto.

**Architecture:** Backend hexagonal (mismo patrón que `Dispensation`): `DashboardController` (inbound adapter) → `DashboardService` (interface) + `DashboardServiceImpl` → `DashboardRepository` (queries nativas MySQL + projection interfaces). El nombre de medicamento se resuelve contra la DB externa DNMA reusando `DnmaDatabaseServiceImpl`. Frontend Angular NgModule: feature folder `dashboard/` con PrimeNG Chart (Chart.js), un solo `GET /api/dashboard/summary`.

**Tech Stack:** Java 21 / Spring Boot 3.3 / Gradle / MySQL (native queries) · Angular 18.2 / PrimeNG 17 / Chart.js · Jasmine/Karma.

**Diseño de referencia:** `doc/plans/2026-06-01-gestion-dashboard-kpis-design.md`

---

## Mapa de archivos

### Backend — recetalia-api-rest (`src/main/java/com/recetalia/api/application/`)
- Create `dto/response/projection/PrescriptionStatsProjection.java` — projection counts de prescripciones.
- Create `dto/response/projection/DispensationStatsProjection.java` — projection counts de dispensaciones.
- Create `dto/response/projection/DailyCountProjection.java` — `{day, total}`.
- Create `dto/response/projection/MedicineCountProjection.java` — `{productId, productType, total}`.
- Create `dto/response/projection/ChainCountProjection.java` — `{franchiseId, franchiseName, total}`.
- Create `dto/response/DashboardCounts.java` — DTO de tarjetas.
- Create `dto/response/ActivityTrendRow.java` — DTO serie diaria.
- Create `dto/response/MedicineCountRow.java` — DTO ranking medicamentos (con nombre).
- Create `dto/response/ChainCountRow.java` — DTO por cadena.
- Create `dto/response/DashboardSummaryResponse.java` — DTO agrupado.
- Create `domain/repository/DashboardRepository.java` — `JpaRepository<Dispensation,String>` con 6 queries nativas.
- Create `service/DashboardService.java` — interface.
- Create `service/impl/DashboardServiceImpl.java` — orquestación + tasa + relleno de días + resolución de nombres + "Sin cadena".
- Create `controller/DashboardController.java` — `GET /api/dashboard/summary`.
- Test `src/test/java/com/recetalia/api/application/service/impl/DashboardServiceImplTest.java`.

### Frontend — gestion-recetadigital-app (`src/app/`)
- Modify `package.json` — agregar `chart.js`.
- Create `model/response/dashboard-summary-response.ts` — interfaces de respuesta.
- Create `services/dashboard.service.ts` — `getSummary(startDate,endDate)`.
- Create `pages/application/home/dashboard/kpi-card/kpi-card.component.{ts,html,scss}`.
- Create `pages/application/home/dashboard/dashboard.component.{ts,html,scss}`.
- Modify `pages/application/home/home.module.ts` — `ChartModule` + declarar componentes.
- Modify `pages/application/home/home-routing.module.ts` — ruta `dashboard` + cambiar redirect default.
- Modify `pages/application/home/components/sidebar/sidebar.component.html` — item "Dashboard" primero.
- Test `services/dashboard.service.spec.ts`.

### Comandos
- Backend build/test: `cd recetalia-api-rest && ./gradlew build` · `./gradlew test --tests DashboardServiceImplTest`
- Frontend: `cd gestion-recetadigital-app && npm install` · `npm run build` · `npm test`

### Convenciones de columnas (MySQL, ya verificadas en el código)
- `dispensation`: `createdAt`, `deletedAt`, `status` (`'DISPENSED'`), `pharmacyId`, `prescriptionId`, `productId`, `productType`.
- `prescription`: `createdAt`, `deletedAt`, `medicId`, `patientId`.
- `pharmacy`: `franchiseId`, `name`.
- `franchise`: `id`, `name`.
- Filtro de rango (patrón existente): `col >= CAST(:fromTs AS DATETIME(6)) AND col < CAST(:toTs AS DATETIME(6))`.

---

## FASE 1 — Backend (recetalia-api-rest)

### Task 1: Projection interfaces

**Files:**
- Create: `src/main/java/com/recetalia/api/application/dto/response/projection/PrescriptionStatsProjection.java`
- Create: `src/main/java/com/recetalia/api/application/dto/response/projection/DispensationStatsProjection.java`
- Create: `src/main/java/com/recetalia/api/application/dto/response/projection/DailyCountProjection.java`
- Create: `src/main/java/com/recetalia/api/application/dto/response/projection/MedicineCountProjection.java`
- Create: `src/main/java/com/recetalia/api/application/dto/response/projection/ChainCountProjection.java`

- [ ] **Step 1: Crear las 5 projections** (interfaces de Spring Data; los getters mapean a aliases SQL)

```java
// PrescriptionStatsProjection.java
package com.recetalia.api.application.dto.response.projection;
public interface PrescriptionStatsProjection {
    Long getPrescriptions();
    Long getActiveMedics();
    Long getPatients();
}
```
```java
// DispensationStatsProjection.java
package com.recetalia.api.application.dto.response.projection;
public interface DispensationStatsProjection {
    Long getDispensations();
    Long getActivePharmacies();
}
```
```java
// DailyCountProjection.java
package com.recetalia.api.application.dto.response.projection;
public interface DailyCountProjection {
    String getDay();   // 'YYYY-MM-DD'
    Long getTotal();
}
```
```java
// MedicineCountProjection.java
package com.recetalia.api.application.dto.response.projection;
public interface MedicineCountProjection {
    String getProductId();
    String getProductType();   // 'AMP' | 'VMP'
    Long getTotal();
}
```
```java
// ChainCountProjection.java
package com.recetalia.api.application.dto.response.projection;
public interface ChainCountProjection {
    String getFranchiseId();    // null para farmacias sin cadena
    String getFranchiseName();  // null para farmacias sin cadena
    Long getTotal();
}
```

- [ ] **Step 2: Compilar** — Run: `./gradlew compileJava` · Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**
```bash
git add src/main/java/com/recetalia/api/application/dto/response/projection
git commit -m "feat(dashboard): projections de agregación de KPIs"
```

---

### Task 2: DashboardRepository (queries nativas)

**Files:**
- Create: `src/main/java/com/recetalia/api/application/domain/repository/DashboardRepository.java`

> Native queries: se anclan a `Dispensation` solo para satisfacer Spring Data; con `nativeQuery=true` consultan cualquier tabla. Todas excluyen `deletedAt IS NOT NULL`. Dispensaciones filtran `status='DISPENSED'`.

- [ ] **Step 1: Crear el repository con las 6 queries**

```java
package com.recetalia.api.application.domain.repository;

import com.recetalia.api.application.domain.model.entities.Dispensation;
import com.recetalia.api.application.dto.response.projection.*;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.List;

@Repository
public interface DashboardRepository extends JpaRepository<Dispensation, String> {

    @Query(value = """
        SELECT
          COUNT(*)                       AS prescriptions,
          COUNT(DISTINCT pr.medicId)     AS activeMedics,
          COUNT(DISTINCT pr.patientId)   AS patients
        FROM prescription pr
        WHERE pr.deletedAt IS NULL
          AND pr.createdAt >= CAST(:fromTs AS DATETIME(6))
          AND pr.createdAt <  CAST(:toTs   AS DATETIME(6))
        """, nativeQuery = true)
    PrescriptionStatsProjection getPrescriptionStats(@Param("fromTs") Instant fromTs, @Param("toTs") Instant toTs);

    @Query(value = """
        SELECT
          COUNT(*)                        AS dispensations,
          COUNT(DISTINCT d.pharmacyId)    AS activePharmacies
        FROM dispensation d
        WHERE d.deletedAt IS NULL
          AND d.status = 'DISPENSED'
          AND d.createdAt >= CAST(:fromTs AS DATETIME(6))
          AND d.createdAt <  CAST(:toTs   AS DATETIME(6))
        """, nativeQuery = true)
    DispensationStatsProjection getDispensationStats(@Param("fromTs") Instant fromTs, @Param("toTs") Instant toTs);

    @Query(value = """
        SELECT DATE(pr.createdAt) AS day, COUNT(*) AS total
        FROM prescription pr
        WHERE pr.deletedAt IS NULL
          AND pr.createdAt >= CAST(:fromTs AS DATETIME(6))
          AND pr.createdAt <  CAST(:toTs   AS DATETIME(6))
        GROUP BY DATE(pr.createdAt)
        """, nativeQuery = true)
    List<DailyCountProjection> getPrescriptionDailyCounts(@Param("fromTs") Instant fromTs, @Param("toTs") Instant toTs);

    @Query(value = """
        SELECT DATE(d.createdAt) AS day, COUNT(*) AS total
        FROM dispensation d
        WHERE d.deletedAt IS NULL
          AND d.status = 'DISPENSED'
          AND d.createdAt >= CAST(:fromTs AS DATETIME(6))
          AND d.createdAt <  CAST(:toTs   AS DATETIME(6))
        GROUP BY DATE(d.createdAt)
        """, nativeQuery = true)
    List<DailyCountProjection> getDispensationDailyCounts(@Param("fromTs") Instant fromTs, @Param("toTs") Instant toTs);

    @Query(value = """
        SELECT d.productId AS productId, d.productType AS productType, COUNT(*) AS total
        FROM dispensation d
        WHERE d.deletedAt IS NULL
          AND d.status = 'DISPENSED'
          AND d.createdAt >= CAST(:fromTs AS DATETIME(6))
          AND d.createdAt <  CAST(:toTs   AS DATETIME(6))
        GROUP BY d.productId, d.productType
        ORDER BY total DESC
        LIMIT :limit
        """, nativeQuery = true)
    List<MedicineCountProjection> getTopMedicines(@Param("fromTs") Instant fromTs, @Param("toTs") Instant toTs, @Param("limit") int limit);

    @Query(value = """
        SELECT fr.id AS franchiseId, fr.name AS franchiseName, COUNT(*) AS total
        FROM dispensation d
        JOIN pharmacy ph ON ph.id = d.pharmacyId
        LEFT JOIN franchise fr ON fr.id = ph.franchiseId
        WHERE d.deletedAt IS NULL
          AND d.status = 'DISPENSED'
          AND d.createdAt >= CAST(:fromTs AS DATETIME(6))
          AND d.createdAt <  CAST(:toTs   AS DATETIME(6))
        GROUP BY fr.id, fr.name
        ORDER BY total DESC
        """, nativeQuery = true)
    List<ChainCountProjection> getDispensationsByChain(@Param("fromTs") Instant fromTs, @Param("toTs") Instant toTs);
}
```

- [ ] **Step 2: Compilar** — Run: `./gradlew compileJava` · Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**
```bash
git add src/main/java/com/recetalia/api/application/domain/repository/DashboardRepository.java
git commit -m "feat(dashboard): repository con queries nativas de agregación"
```

---

### Task 3: DTOs de respuesta

**Files:**
- Create: `dto/response/DashboardCounts.java`, `ActivityTrendRow.java`, `MedicineCountRow.java`, `ChainCountRow.java`, `DashboardSummaryResponse.java`

- [ ] **Step 1: Crear los 5 DTOs** (Lombok como el resto del proyecto)

```java
// DashboardCounts.java
package com.recetalia.api.application.dto.response;
import lombok.*;
@Getter @Setter @NoArgsConstructor @AllArgsConstructor
public class DashboardCounts {
    private long prescriptions;
    private long dispensations;
    private double dispensationRate;   // porcentaje 0..100
    private long activeMedics;
    private long activePharmacies;
    private long patients;
}
```
```java
// ActivityTrendRow.java
package com.recetalia.api.application.dto.response;
import lombok.*;
@Getter @Setter @NoArgsConstructor @AllArgsConstructor
public class ActivityTrendRow {
    private String date;        // 'YYYY-MM-DD'
    private long prescriptions;
    private long dispensations;
}
```
```java
// MedicineCountRow.java
package com.recetalia.api.application.dto.response;
import lombok.*;
@Getter @Setter @NoArgsConstructor @AllArgsConstructor
public class MedicineCountRow {
    private String medicineId;
    private String medicineName;
    private long count;
}
```
```java
// ChainCountRow.java
package com.recetalia.api.application.dto.response;
import lombok.*;
@Getter @Setter @NoArgsConstructor @AllArgsConstructor
public class ChainCountRow {
    private String franchiseId;     // null si "Sin cadena"
    private String franchiseName;   // "Sin cadena" si no tiene
    private long count;
}
```
```java
// DashboardSummaryResponse.java
package com.recetalia.api.application.dto.response;
import lombok.*;
import java.util.List;
@Getter @Setter @NoArgsConstructor @AllArgsConstructor
public class DashboardSummaryResponse {
    private DashboardCounts counts;
    private List<ActivityTrendRow> activityTrend;
    private List<MedicineCountRow> topMedicines;
    private List<ChainCountRow> byChain;
}
```

- [ ] **Step 2: Compilar** — Run: `./gradlew compileJava` · Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**
```bash
git add src/main/java/com/recetalia/api/application/dto/response/Dashboard*.java \
        src/main/java/com/recetalia/api/application/dto/response/ActivityTrendRow.java \
        src/main/java/com/recetalia/api/application/dto/response/MedicineCountRow.java \
        src/main/java/com/recetalia/api/application/dto/response/ChainCountRow.java
git commit -m "feat(dashboard): DTOs de respuesta del summary"
```

---

### Task 4: DashboardService interface

**Files:**
- Create: `service/DashboardService.java`

- [ ] **Step 1: Crear la interface**
```java
package com.recetalia.api.application.service;

import com.recetalia.api.application.dto.response.DashboardSummaryResponse;
import java.time.LocalDate;

public interface DashboardService {
    /** Resumen de KPIs de la plataforma para [startDate, endDate] inclusive. */
    DashboardSummaryResponse getSummary(LocalDate startDate, LocalDate endDate);
}
```
- [ ] **Step 2: Compilar** — Run: `./gradlew compileJava` · Expected: BUILD SUCCESSFUL.
- [ ] **Step 3: Commit**
```bash
git add src/main/java/com/recetalia/api/application/service/DashboardService.java
git commit -m "feat(dashboard): interface DashboardService"
```

---

### Task 5: Verificar firma del servicio DNMA (lectura, sin cambios)

**Files:** none (lectura)

- [ ] **Step 1: Leer la firma real de resolución de nombres**

Run: `grep -n "fetchAmpDetails\|fetchVmpDetails\|public.*Map" src/main/java/com/recetalia/api/application/service/impl/DnmaDatabaseServiceImpl.java`

Confirmar: nombres de método, tipos de parámetro (`List<String>`), y forma del retorno (`Map<String, Map<String,String>>`) y la clave del nombre (`amp_dsc` / `vmp_dsc`). **Anotar las firmas exactas** — se usan en Task 6, Step 3. Si difieren de lo asumido, ajustar el código de Task 6 a las firmas reales antes de implementar.

---

### Task 6: DashboardServiceImpl (TDD sobre la lógica)

**Files:**
- Create: `service/impl/DashboardServiceImpl.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/DashboardServiceImplTest.java`

> Se testea la **lógica** con repositorio + servicio DNMA mockeados (Mockito ya viene con spring-boot-starter-test): cálculo de tasa (incl. división por cero), relleno de días en cero a lo largo del rango, mapeo "Sin cadena", y armado del top de medicamentos con nombre. El SQL nativo se valida con smoke test manual (Task 8).

- [ ] **Step 1: Escribir el test que falla**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.repository.DashboardRepository;
import com.recetalia.api.application.dto.response.*;
import com.recetalia.api.application.dto.response.projection.*;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

class DashboardServiceImplTest {

    private PrescriptionStatsProjection presStats(long p, long m, long pat) {
        return new PrescriptionStatsProjection() {
            public Long getPrescriptions() { return p; }
            public Long getActiveMedics() { return m; }
            public Long getPatients() { return pat; }
        };
    }
    private DispensationStatsProjection dispStats(long d, long ph) {
        return new DispensationStatsProjection() {
            public Long getDispensations() { return d; }
            public Long getActivePharmacies() { return ph; }
        };
    }
    private DailyCountProjection daily(String day, long total) {
        return new DailyCountProjection() {
            public String getDay() { return day; }
            public Long getTotal() { return total; }
        };
    }
    private ChainCountProjection chain(String id, String name, long total) {
        return new ChainCountProjection() {
            public String getFranchiseId() { return id; }
            public String getFranchiseName() { return name; }
            public Long getTotal() { return total; }
        };
    }

    private DashboardServiceImpl serviceWith(DashboardRepository repo) {
        // DNMA service mock devuelve nombres vacíos por defecto (top medicines no testeado acá)
        DnmaDatabaseServiceImpl dnma = Mockito.mock(DnmaDatabaseServiceImpl.class);
        when(repo.getTopMedicines(any(), any(), Mockito.anyInt())).thenReturn(List.of());
        return new DashboardServiceImpl(repo, dnma);
    }

    @Test
    void computesDispensationRate() {
        DashboardRepository repo = Mockito.mock(DashboardRepository.class);
        when(repo.getPrescriptionStats(any(), any())).thenReturn(presStats(200, 10, 150));
        when(repo.getDispensationStats(any(), any())).thenReturn(dispStats(150, 5));
        when(repo.getPrescriptionDailyCounts(any(), any())).thenReturn(List.of());
        when(repo.getDispensationDailyCounts(any(), any())).thenReturn(List.of());
        when(repo.getDispensationsByChain(any(), any())).thenReturn(List.of());

        DashboardSummaryResponse r = serviceWith(repo)
                .getSummary(LocalDate.of(2026,5,1), LocalDate.of(2026,5,1));

        assertThat(r.getCounts().getPrescriptions()).isEqualTo(200);
        assertThat(r.getCounts().getDispensations()).isEqualTo(150);
        assertThat(r.getCounts().getDispensationRate()).isEqualTo(75.0);
    }

    @Test
    void rateIsZeroWhenNoPrescriptions() {
        DashboardRepository repo = Mockito.mock(DashboardRepository.class);
        when(repo.getPrescriptionStats(any(), any())).thenReturn(presStats(0, 0, 0));
        when(repo.getDispensationStats(any(), any())).thenReturn(dispStats(0, 0));
        when(repo.getPrescriptionDailyCounts(any(), any())).thenReturn(List.of());
        when(repo.getDispensationDailyCounts(any(), any())).thenReturn(List.of());
        when(repo.getDispensationsByChain(any(), any())).thenReturn(List.of());

        DashboardSummaryResponse r = serviceWith(repo)
                .getSummary(LocalDate.of(2026,5,1), LocalDate.of(2026,5,1));
        assertThat(r.getCounts().getDispensationRate()).isEqualTo(0.0);
    }

    @Test
    void fillsTrendWithZeroDaysAcrossRange() {
        DashboardRepository repo = Mockito.mock(DashboardRepository.class);
        when(repo.getPrescriptionStats(any(), any())).thenReturn(presStats(3, 1, 1));
        when(repo.getDispensationStats(any(), any())).thenReturn(dispStats(1, 1));
        when(repo.getPrescriptionDailyCounts(any(), any()))
                .thenReturn(List.of(daily("2026-05-01", 2), daily("2026-05-03", 1)));
        when(repo.getDispensationDailyCounts(any(), any()))
                .thenReturn(List.of(daily("2026-05-03", 1)));
        when(repo.getDispensationsByChain(any(), any())).thenReturn(List.of());

        DashboardSummaryResponse r = serviceWith(repo)
                .getSummary(LocalDate.of(2026,5,1), LocalDate.of(2026,5,3));

        List<ActivityTrendRow> t = r.getActivityTrend();
        assertThat(t).hasSize(3);
        assertThat(t.get(0).getDate()).isEqualTo("2026-05-01");
        assertThat(t.get(0).getPrescriptions()).isEqualTo(2);
        assertThat(t.get(0).getDispensations()).isEqualTo(0);
        assertThat(t.get(1).getDate()).isEqualTo("2026-05-02");
        assertThat(t.get(1).getPrescriptions()).isEqualTo(0);
        assertThat(t.get(2).getDate()).isEqualTo("2026-05-03");
        assertThat(t.get(2).getPrescriptions()).isEqualTo(1);
        assertThat(t.get(2).getDispensations()).isEqualTo(1);
    }

    @Test
    void mapsNullFranchiseToSinCadena() {
        DashboardRepository repo = Mockito.mock(DashboardRepository.class);
        when(repo.getPrescriptionStats(any(), any())).thenReturn(presStats(1, 1, 1));
        when(repo.getDispensationStats(any(), any())).thenReturn(dispStats(1, 1));
        when(repo.getPrescriptionDailyCounts(any(), any())).thenReturn(List.of());
        when(repo.getDispensationDailyCounts(any(), any())).thenReturn(List.of());
        when(repo.getDispensationsByChain(any(), any()))
                .thenReturn(List.of(chain("f1","Cadena A",5), chain(null,null,3)));

        DashboardSummaryResponse r = serviceWith(repo)
                .getSummary(LocalDate.of(2026,5,1), LocalDate.of(2026,5,1));

        assertThat(r.getByChain()).hasSize(2);
        assertThat(r.getByChain().get(1).getFranchiseId()).isNull();
        assertThat(r.getByChain().get(1).getFranchiseName()).isEqualTo("Sin cadena");
    }
}
```

- [ ] **Step 2: Correr el test — debe fallar a compilación** (no existe `DashboardServiceImpl`)

Run: `./gradlew test --tests DashboardServiceImplTest` · Expected: FAIL (compilation / clase inexistente).

- [ ] **Step 3: Implementar `DashboardServiceImpl`**

> Ajustar la sección de `topMedicines` a las firmas reales anotadas en Task 5 si difieren.

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.repository.DashboardRepository;
import com.recetalia.api.application.dto.response.*;
import com.recetalia.api.application.dto.response.projection.*;
import com.recetalia.api.application.service.DashboardService;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class DashboardServiceImpl implements DashboardService {

    private final DashboardRepository repo;
    private final DnmaDatabaseServiceImpl dnma;

    public DashboardServiceImpl(DashboardRepository repo, DnmaDatabaseServiceImpl dnma) {
        this.repo = repo;
        this.dnma = dnma;
    }

    @Override
    public DashboardSummaryResponse getSummary(LocalDate startDate, LocalDate endDate) {
        ZoneId zone = ZoneId.systemDefault();
        Instant fromTs = startDate.atStartOfDay(zone).toInstant();
        Instant toTs = endDate.plusDays(1).atStartOfDay(zone).toInstant(); // exclusivo

        PrescriptionStatsProjection ps = repo.getPrescriptionStats(fromTs, toTs);
        DispensationStatsProjection ds = repo.getDispensationStats(fromTs, toTs);

        long prescriptions = nz(ps == null ? null : ps.getPrescriptions());
        long dispensations = nz(ds == null ? null : ds.getDispensations());
        double rate = prescriptions == 0 ? 0.0
                : Math.round((dispensations * 10000.0) / prescriptions) / 100.0;

        DashboardCounts counts = new DashboardCounts(
                prescriptions, dispensations, rate,
                nz(ps == null ? null : ps.getActiveMedics()),
                nz(ds == null ? null : ds.getActivePharmacies()),
                nz(ps == null ? null : ps.getPatients()));

        List<ActivityTrendRow> trend = buildTrend(startDate, endDate,
                repo.getPrescriptionDailyCounts(fromTs, toTs),
                repo.getDispensationDailyCounts(fromTs, toTs));

        List<MedicineCountRow> topMedicines = buildTopMedicines(repo.getTopMedicines(fromTs, toTs, 10));

        List<ChainCountRow> byChain = repo.getDispensationsByChain(fromTs, toTs).stream()
                .map(c -> new ChainCountRow(
                        c.getFranchiseId(),
                        c.getFranchiseId() == null ? "Sin cadena" : c.getFranchiseName(),
                        nz(c.getTotal())))
                .collect(Collectors.toList());

        return new DashboardSummaryResponse(counts, trend, topMedicines, byChain);
    }

    private List<ActivityTrendRow> buildTrend(LocalDate start, LocalDate end,
                                              List<DailyCountProjection> pres,
                                              List<DailyCountProjection> disp) {
        Map<String, Long> presByDay = pres.stream()
                .collect(Collectors.toMap(DailyCountProjection::getDay, d -> nz(d.getTotal())));
        Map<String, Long> dispByDay = disp.stream()
                .collect(Collectors.toMap(DailyCountProjection::getDay, d -> nz(d.getTotal())));
        List<ActivityTrendRow> out = new ArrayList<>();
        for (LocalDate d = start; !d.isAfter(end); d = d.plusDays(1)) {
            String key = d.toString(); // ISO 'YYYY-MM-DD'
            out.add(new ActivityTrendRow(key,
                    presByDay.getOrDefault(key, 0L),
                    dispByDay.getOrDefault(key, 0L)));
        }
        return out;
    }

    private List<MedicineCountRow> buildTopMedicines(List<MedicineCountProjection> top) {
        if (top.isEmpty()) return new ArrayList<>();
        // Resolver nombres por tipo reusando el servicio DNMA (mismo patrón que el enrichment de dispensaciones).
        List<String> ampIds = top.stream().filter(t -> "AMP".equalsIgnoreCase(t.getProductType()))
                .map(MedicineCountProjection::getProductId).collect(Collectors.toList());
        List<String> vmpIds = top.stream().filter(t -> "VMP".equalsIgnoreCase(t.getProductType()))
                .map(MedicineCountProjection::getProductId).collect(Collectors.toList());
        Map<String, Map<String, String>> amp = ampIds.isEmpty() ? Map.of() : dnma.fetchAmpDetails(ampIds);
        Map<String, Map<String, String>> vmp = vmpIds.isEmpty() ? Map.of() : dnma.fetchVmpDetails(vmpIds);

        List<MedicineCountRow> out = new ArrayList<>();
        for (MedicineCountProjection t : top) {
            String name;
            if ("AMP".equalsIgnoreCase(t.getProductType())) {
                name = amp.getOrDefault(t.getProductId(), Map.of()).getOrDefault("amp_dsc", t.getProductId());
            } else {
                name = vmp.getOrDefault(t.getProductId(), Map.of()).getOrDefault("vmp_dsc", t.getProductId());
            }
            out.add(new MedicineCountRow(t.getProductId(), name, nz(t.getTotal())));
        }
        return out;
    }

    private static long nz(Long v) { return v == null ? 0L : v; }
}
```

- [ ] **Step 4: Correr los tests — deben pasar**

Run: `./gradlew test --tests DashboardServiceImplTest` · Expected: PASS (4 tests).

- [ ] **Step 5: Commit**
```bash
git add src/main/java/com/recetalia/api/application/service/impl/DashboardServiceImpl.java \
        src/test/java/com/recetalia/api/application/service/impl/DashboardServiceImplTest.java
git commit -m "feat(dashboard): DashboardServiceImpl con tasa, trend y by-chain (TDD)"
```

---

### Task 7: DashboardController

**Files:**
- Create: `controller/DashboardController.java`

- [ ] **Step 1: Crear el controller** (mismo `@CrossOrigin` y envoltura que `DispensationController`)

```java
package com.recetalia.api.application.controller;

import com.recetalia.api.application.dto.enums.ResponseStatus;
import com.recetalia.api.application.dto.response.DashboardSummaryResponse;
import com.recetalia.api.application.dto.response.GenericResponse;
import com.recetalia.api.application.service.DashboardService;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;

@CrossOrigin(
        origins = { "http://localhost:4200" },
        allowCredentials = "true",
        allowedHeaders = "*",
        methods = { RequestMethod.GET, RequestMethod.OPTIONS }
)
@RestController
@RequestMapping("/api/dashboard")
public class DashboardController {

    private final DashboardService dashboardService;

    public DashboardController(DashboardService dashboardService) {
        this.dashboardService = dashboardService;
    }

    @GetMapping("/summary")
    public ResponseEntity<GenericResponse<DashboardSummaryResponse>> summary(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate
    ) {
        DashboardSummaryResponse data = dashboardService.getSummary(startDate, endDate);
        return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, data));
    }
}
```

- [ ] **Step 2: Build completo** — Run: `./gradlew build` · Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**
```bash
git add src/main/java/com/recetalia/api/application/controller/DashboardController.java
git commit -m "feat(dashboard): endpoint GET /api/dashboard/summary"
```

---

### Task 8: Smoke test manual del endpoint (valida el SQL nativo)

**Files:** none

- [ ] **Step 1: Levantar la API localmente** (apuntando a la DB pre-prod ya configurada) — Run: `./gradlew bootRun`

- [ ] **Step 2: Obtener un JWT de gestión y consultar**

```bash
# (usar el flujo de login de gestión para obtener <JWT>)
curl -s "http://localhost:8092/api/dashboard/summary?startDate=2026-05-01&endDate=2026-05-29" \
  -H "Authorization: Bearer <JWT>" | head -c 800
```
Expected: JSON `{"status":"SUCCESS","answer":{"counts":{...},"activityTrend":[...],"topMedicines":[...],"byChain":[...]}}`. Verificar que `counts` tenga números coherentes, `activityTrend` cubra todos los días del rango, `topMedicines` traiga nombres (no IDs crudos), y `byChain` incluya "Sin cadena" si corresponde.

- [ ] **Step 3:** Si el SQL falla (nombres de columna/tabla), ajustar la query en `DashboardRepository` según el error de MySQL y repetir.

---

## FASE 2 — Frontend (gestion-recetadigital-app)

### Task 9: Dependencia Chart.js

**Files:**
- Modify: `package.json`

- [ ] **Step 1: Instalar chart.js** (peer dep de PrimeNG Chart)

Run: `cd gestion-recetadigital-app && npm install chart.js@4`
Expected: `chart.js` agregado a dependencies.

- [ ] **Step 2: Commit**
```bash
git add package.json package-lock.json
git commit -m "chore(dashboard): agregar chart.js para PrimeNG Chart"
```

---

### Task 10: Modelos de respuesta

**Files:**
- Create: `src/app/model/response/dashboard-summary-response.ts`

- [ ] **Step 1: Crear las interfaces**
```typescript
export interface DashboardCounts {
  prescriptions: number;
  dispensations: number;
  dispensationRate: number;
  activeMedics: number;
  activePharmacies: number;
  patients: number;
}
export interface ActivityTrendRow {
  date: string;
  prescriptions: number;
  dispensations: number;
}
export interface MedicineCountRow {
  medicineId: string;
  medicineName: string;
  count: number;
}
export interface ChainCountRow {
  franchiseId: string | null;
  franchiseName: string;
  count: number;
}
export interface DashboardSummaryResponse {
  counts: DashboardCounts;
  activityTrend: ActivityTrendRow[];
  topMedicines: MedicineCountRow[];
  byChain: ChainCountRow[];
}
```
- [ ] **Step 2: Commit**
```bash
git add src/app/model/response/dashboard-summary-response.ts
git commit -m "feat(dashboard): modelos de respuesta"
```

---

### Task 11: DashboardService (TDD del armado de params + unwrap)

**Files:**
- Create: `src/app/services/dashboard.service.ts`
- Test: `src/app/services/dashboard.service.spec.ts`

- [ ] **Step 1: Escribir el test que falla** (HttpClientTestingModule)
```typescript
import { TestBed } from '@angular/core/testing';
import { HttpClientTestingModule, HttpTestingController } from '@angular/common/http/testing';
import { DashboardService } from './dashboard.service';
import { environment } from '../../environments/environment';
import { DashboardSummaryResponse } from '../model/response/dashboard-summary-response';

describe('DashboardService', () => {
  let service: DashboardService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [HttpClientTestingModule],
      providers: [DashboardService],
    });
    service = TestBed.inject(DashboardService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('GET summary con startDate/endDate y desenvuelve answer', () => {
    const fake: DashboardSummaryResponse = {
      counts: { prescriptions: 10, dispensations: 8, dispensationRate: 80, activeMedics: 3, activePharmacies: 2, patients: 7 },
      activityTrend: [], topMedicines: [], byChain: [],
    };
    let result: DashboardSummaryResponse | undefined;
    service.getSummary('2026-05-01', '2026-05-29').subscribe(r => (result = r));

    const req = httpMock.expectOne(r =>
      r.url === `${environment.apiUrl}/dashboard/summary` &&
      r.params.get('startDate') === '2026-05-01' &&
      r.params.get('endDate') === '2026-05-29');
    expect(req.request.method).toBe('GET');
    req.flush({ status: 'SUCCESS', answer: fake, serverDateTime: 'x' });

    expect(result).toEqual(fake);
  });
});
```
- [ ] **Step 2: Correr — debe fallar** — Run: `npm test -- --watch=false` · Expected: FAIL (DashboardService no existe).

- [ ] **Step 3: Implementar el service** (patrón idéntico a `MedicsService`)
```typescript
import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { map, catchError } from 'rxjs/operators';
import { environment } from '../../environments/environment';
import { ApiResponse } from '../model/response/api-response';
import { DashboardSummaryResponse } from '../model/response/dashboard-summary-response';

@Injectable({ providedIn: 'root' })
export class DashboardService {
  private apiUrl = `${environment.apiUrl}/dashboard`;

  constructor(private http: HttpClient) {}

  getSummary(startDate: string, endDate: string): Observable<DashboardSummaryResponse> {
    const params = new HttpParams().set('startDate', startDate).set('endDate', endDate);
    return this.http
      .get<ApiResponse<DashboardSummaryResponse>>(`${this.apiUrl}/summary`, { params })
      .pipe(
        map(response => {
          if (response.status === 'SUCCESS') return response.answer;
          throw new Error('Error response from the API: ' + response.applicationProvider);
        }),
        catchError(error => {
          console.error('API request failed:', error);
          return throwError(() => new Error('Failed to fetch dashboard summary'));
        })
      );
  }
}
```
- [ ] **Step 4: Correr — debe pasar** — Run: `npm test -- --watch=false` · Expected: PASS.
- [ ] **Step 5: Commit**
```bash
git add src/app/services/dashboard.service.ts src/app/services/dashboard.service.spec.ts
git commit -m "feat(dashboard): DashboardService (TDD)"
```

---

### Task 12: KpiCardComponent

**Files:**
- Create: `src/app/pages/application/home/dashboard/kpi-card/kpi-card.component.ts`
- Create: `src/app/pages/application/home/dashboard/kpi-card/kpi-card.component.html`
- Create: `src/app/pages/application/home/dashboard/kpi-card/kpi-card.component.scss`

- [ ] **Step 1: Componente de presentación** (clickeable opcional)
```typescript
import { Component, Input } from '@angular/core';

@Component({
  selector: 'app-kpi-card',
  standalone: false,
  templateUrl: './kpi-card.component.html',
  styleUrls: ['./kpi-card.component.scss'],
})
export class KpiCardComponent {
  @Input() label = '';
  @Input() value: string | number = '';
  @Input() icon = 'fas fa-chart-simple';
  @Input() clickable = false;
}
```
```html
<!-- kpi-card.component.html -->
<div class="kpi-card" [class.clickable]="clickable">
  <i [class]="icon" class="kpi-icon"></i>
  <div class="kpi-body">
    <div class="kpi-value">{{ value }}</div>
    <div class="kpi-label">{{ label }}</div>
  </div>
</div>
```
```scss
/* kpi-card.component.scss */
.kpi-card {
  display:flex; align-items:center; gap:12px;
  padding:16px; background:#fff; border:1px solid #e5e9ef; border-radius:8px;
  box-shadow:0 1px 2px rgba(0,0,0,.04);
}
.kpi-card.clickable { cursor:pointer; transition:box-shadow .15s, transform .15s; }
.kpi-card.clickable:hover { box-shadow:0 4px 10px rgba(0,0,0,.10); transform:translateY(-1px); }
.kpi-icon { font-size:22px; color:#2a6; }
.kpi-value { font-size:24px; font-weight:700; color:#243; line-height:1; }
.kpi-label { font-size:12px; color:#789; margin-top:4px; }
```
- [ ] **Step 2: Commit** (se compila al declararlo en Task 14)
```bash
git add src/app/pages/application/home/dashboard/kpi-card
git commit -m "feat(dashboard): KpiCardComponent"
```

---

### Task 13: DashboardComponent (período + tarjetas + gráficos)

**Files:**
- Create: `src/app/pages/application/home/dashboard/dashboard.component.ts`
- Create: `src/app/pages/application/home/dashboard/dashboard.component.html`
- Create: `src/app/pages/application/home/dashboard/dashboard.component.scss`

- [ ] **Step 1: Componente contenedor**
```typescript
import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { DashboardService } from '../../../../services/dashboard.service';
import { DashboardSummaryResponse } from '../../../../model/response/dashboard-summary-response';

type Preset = 'today' | '7d' | '30d' | 'month' | 'custom';

@Component({
  selector: 'app-dashboard',
  standalone: false,
  templateUrl: './dashboard.component.html',
  styleUrls: ['./dashboard.component.scss'],
})
export class DashboardComponent implements OnInit {
  loading = false;
  error = false;
  data?: DashboardSummaryResponse;

  preset: Preset = '30d';
  startDate!: Date;
  endDate!: Date;

  trendChart: any; trendOpts: any;
  topMedsChart: any; topMedsOpts: any;
  chainChart: any; chainOpts: any;

  constructor(private dashboardService: DashboardService, private router: Router) {}

  ngOnInit(): void {
    this.applyPreset('30d');
  }

  applyPreset(p: Preset): void {
    this.preset = p;
    const end = new Date();
    const start = new Date();
    if (p === 'today') { /* start=end=hoy */ }
    else if (p === '7d') start.setDate(end.getDate() - 6);
    else if (p === '30d') start.setDate(end.getDate() - 29);
    else if (p === 'month') start.setDate(1);
    if (p !== 'custom') { this.startDate = start; this.endDate = end; this.load(); }
  }

  onCustomChange(): void {
    if (this.startDate && this.endDate) { this.preset = 'custom'; this.load(); }
  }

  private iso(d: Date): string {
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }

  load(): void {
    this.loading = true; this.error = false;
    this.dashboardService.getSummary(this.iso(this.startDate), this.iso(this.endDate)).subscribe({
      next: data => { this.data = data; this.buildCharts(data); this.loading = false; },
      error: () => { this.error = true; this.loading = false; },
    });
  }

  private buildCharts(d: DashboardSummaryResponse): void {
    this.trendChart = {
      labels: d.activityTrend.map(r => r.date),
      datasets: [
        { label: 'Prescripciones', data: d.activityTrend.map(r => r.prescriptions), borderColor: '#3b82f6', tension: .3 },
        { label: 'Dispensaciones', data: d.activityTrend.map(r => r.dispensations), borderColor: '#22a06b', tension: .3 },
      ],
    };
    this.trendOpts = { maintainAspectRatio: false, plugins: { legend: { position: 'bottom' } } };

    this.topMedsChart = {
      labels: d.topMedicines.map(m => m.medicineName),
      datasets: [{ label: 'Dispensaciones', data: d.topMedicines.map(m => m.count), backgroundColor: '#3b82f6' }],
    };
    this.topMedsOpts = { maintainAspectRatio: false, indexAxis: 'y', plugins: { legend: { display: false } } };

    this.chainChart = {
      labels: d.byChain.map(c => c.franchiseName),
      datasets: [{ data: d.byChain.map(c => c.count) }],
    };
    this.chainOpts = { maintainAspectRatio: false, plugins: { legend: { position: 'right' } } };
  }

  // Drill-down: navega llevando el período (y filtro puntual) como query params.
  private periodParams() { return { startDate: this.iso(this.startDate), endDate: this.iso(this.endDate) }; }
  goTo(route: string, extra: Record<string, string> = {}): void {
    this.router.navigate([route], { queryParams: { ...this.periodParams(), ...extra } });
  }
  onMedicineClick(i: number): void {
    const m = this.data?.topMedicines[i]; if (m) this.goTo('/dispensations', { medicineId: m.medicineId });
  }
  onChainClick(i: number): void {
    const c = this.data?.byChain[i]; if (c && c.franchiseId) this.goTo('/dispensations', { franchiseId: c.franchiseId });
  }
}
```
- [ ] **Step 2: Template** (Layout A; usa `p-chart`, `p-calendar` y `app-kpi-card`)
```html
<div class="dashboard">
  <div class="period-bar">
    <button class="preset" [class.on]="preset==='today'" (click)="applyPreset('today')">Hoy</button>
    <button class="preset" [class.on]="preset==='7d'" (click)="applyPreset('7d')">7 días</button>
    <button class="preset" [class.on]="preset==='30d'" (click)="applyPreset('30d')">30 días</button>
    <button class="preset" [class.on]="preset==='month'" (click)="applyPreset('month')">Mes actual</button>
    <span class="custom">
      <p-calendar [(ngModel)]="startDate" dateFormat="dd/mm/yy" (onSelect)="onCustomChange()" placeholder="Desde"></p-calendar>
      <p-calendar [(ngModel)]="endDate" dateFormat="dd/mm/yy" (onSelect)="onCustomChange()" placeholder="Hasta"></p-calendar>
    </span>
  </div>

  <div *ngIf="loading" class="state">Cargando…</div>
  <div *ngIf="error" class="state error">No se pudo cargar el dashboard. <button (click)="load()">Reintentar</button></div>

  <ng-container *ngIf="data && !loading && !error">
    <div class="kpi-grid">
      <app-kpi-card label="Prescripciones" [value]="data.counts.prescriptions" icon="fas fa-capsules" [clickable]="true" (click)="goTo('/prescriptions')"></app-kpi-card>
      <app-kpi-card label="Dispensaciones" [value]="data.counts.dispensations" icon="fas fa-hand-holding-heart" [clickable]="true" (click)="goTo('/dispensations')"></app-kpi-card>
      <app-kpi-card label="Tasa de dispensación" [value]="data.counts.dispensationRate + '%'" icon="fas fa-percent"></app-kpi-card>
      <app-kpi-card label="Médicos activos" [value]="data.counts.activeMedics" icon="fas fa-user-doctor" [clickable]="true" (click)="goTo('/medics')"></app-kpi-card>
      <app-kpi-card label="Farmacias activas" [value]="data.counts.activePharmacies" icon="fas fa-prescription-bottle-medical" [clickable]="true" (click)="goTo('/pharmacies')"></app-kpi-card>
      <app-kpi-card label="Pacientes" [value]="data.counts.patients" icon="fas fa-users" [clickable]="true" (click)="goTo('/patients')"></app-kpi-card>
    </div>

    <div class="chart-wide">
      <h3>Tendencia de actividad</h3>
      <p-chart type="line" [data]="trendChart" [options]="trendOpts"></p-chart>
    </div>

    <div class="chart-row">
      <div class="chart-box">
        <h3>Top medicamentos</h3>
        <p-chart type="bar" [data]="topMedsChart" [options]="topMedsOpts" (onDataSelect)="onMedicineClick($event.element.index)"></p-chart>
      </div>
      <div class="chart-box">
        <h3>Dispensaciones por cadena</h3>
        <p-chart type="doughnut" [data]="chainChart" [options]="chainOpts" (onDataSelect)="onChainClick($event.element.index)"></p-chart>
      </div>
    </div>
  </ng-container>
</div>
```
```scss
/* dashboard.component.scss */
.dashboard { padding:16px; }
.period-bar { display:flex; gap:8px; align-items:center; flex-wrap:wrap; margin-bottom:16px; }
.period-bar .preset { border:1px solid #cfd8e3; background:#fff; border-radius:6px; padding:6px 12px; cursor:pointer; }
.period-bar .preset.on { background:#22a06b; color:#fff; border-color:#22a06b; }
.period-bar .custom { display:flex; gap:8px; margin-left:8px; }
.kpi-grid { display:grid; grid-template-columns:repeat(auto-fit, minmax(180px,1fr)); gap:12px; margin-bottom:16px; }
.chart-wide, .chart-box { background:#fff; border:1px solid #e5e9ef; border-radius:8px; padding:12px; margin-bottom:16px; }
.chart-wide { height:300px; } .chart-wide p-chart { display:block; height:240px; }
.chart-row { display:grid; grid-template-columns:1fr 1fr; gap:16px; }
.chart-box { height:300px; } .chart-box p-chart { display:block; height:240px; }
.state { padding:24px; text-align:center; color:#789; } .state.error { color:#c0392b; }
@media (max-width:900px){ .chart-row { grid-template-columns:1fr; } }
```
- [ ] **Step 3: Commit** (compila al declararlo en Task 14)
```bash
git add src/app/pages/application/home/dashboard/dashboard.component.*
git commit -m "feat(dashboard): DashboardComponent (período + tarjetas + gráficos, Layout A)"
```

---

### Task 14: Declarar en HomeModule + ChartModule

**Files:**
- Modify: `src/app/pages/application/home/home.module.ts`

- [ ] **Step 1: Agregar import de `ChartModule` y declarar los componentes nuevos**

En `home.module.ts`:
- Agregar import: `import { ChartModule } from 'primeng/chart';`
- Agregar imports de los componentes nuevos:
  `import { DashboardComponent } from './dashboard/dashboard.component';`
  `import { KpiCardComponent } from './dashboard/kpi-card/kpi-card.component';`
- En `declarations: [...]` agregar `DashboardComponent, KpiCardComponent`.
- En `imports: [...]` agregar `ChartModule`.

- [ ] **Step 2: Build** — Run: `npm run build` · Expected: build OK (sin errores de template/DI).
- [ ] **Step 3: Commit**
```bash
git add src/app/pages/application/home/home.module.ts
git commit -m "feat(dashboard): declarar Dashboard + ChartModule en HomeModule"
```

---

### Task 15: Routing + menú (default = dashboard)

**Files:**
- Modify: `src/app/pages/application/home/home-routing.module.ts`
- Modify: `src/app/pages/application/home/components/sidebar/sidebar.component.html`

- [ ] **Step 1: Ruta `dashboard` + cambiar redirect default**

En `home-routing.module.ts`:
- Import: `import { DashboardComponent } from "./dashboard/dashboard.component";`
- Cambiar el child redirect de `redirectTo: "dnma-medicines"` → `redirectTo: "dashboard"`.
- Agregar como primer child con path: `{ path: "dashboard", component: DashboardComponent }`.

- [ ] **Step 2: Item "Dashboard" primero en el sidebar**

En `sidebar.component.html`, agregar como **primer** `<li>` dentro de `<ul class="nav flex-column">`:
```html
<li class="nav-item">
  <a class="nav-link" routerLink="dashboard" routerLinkActive="active" (click)="closeSidebar()">
    <i class="fas fa-chart-line"></i> <span>Dashboard</span>
  </a>
</li>
```

- [ ] **Step 3: Build + verificación manual**

Run: `npm start` y abrir la app. Expected: al ingresar redirige a `/dashboard`; el menú muestra "Dashboard" primero; cambiar período re-consulta; tarjetas clickeables navegan (con `?startDate&endDate` en la URL del destino).

- [ ] **Step 4: Commit**
```bash
git add src/app/pages/application/home/home-routing.module.ts \
        src/app/pages/application/home/components/sidebar/sidebar.component.html
git commit -m "feat(dashboard): ruta /dashboard por defecto + item de menú"
```

---

## Follow-up (fuera de este plan)

**Honrar los query params en los listados destino** (drill-down filtrado): hoy ningún list component lee `ActivatedRoute.queryParams`. Para que el filtro se auto-aplique al navegar desde el dashboard, cada listado destino (`dispensations`, `prescriptions`, `medics`, `pharmacies`, `patients`) necesita leer `queryParams` al iniciar y aplicar el filtro a sus controles internos. Esto es un plan separado, una tarea por listado (cada uno tiene su propia estructura de filtros). El dashboard ya deja la navegación con los params en la URL; este follow-up los consume.

> Prioridad sugerida del follow-up: `dispensations` primero (recibe 3 drill-downs: dispensaciones, medicamento, cadena, y ya tiene filtros de fecha/cadena/medicamento internamente).

---

## Criterios de éxito (del spec)

- [ ] `GET /api/dashboard/summary?startDate&endDate` devuelve counts + trend + top 10 medicamentos + by-chain en `GenericResponse`.
- [ ] Tasa de dispensación correcta (0% si no hay prescripciones) — cubierto por tests.
- [ ] Trend con relleno de días en cero — cubierto por test.
- [ ] "Sin cadena" para farmacias sin franchise — cubierto por test.
- [ ] Dashboard renderiza tarjetas + 3 gráficos y re-consulta al cambiar período.
- [ ] `/dashboard` es la ruta por defecto y primer ítem del menú.
- [ ] Tarjetas/elementos navegan al detalle con período (y filtro) en la URL.
- [ ] `./gradlew test --tests DashboardServiceImplTest` y `npm test` pasan.

## Self-review (hecho)

- **Cobertura del spec**: KPIs (Task 1,2,3,6), período (Task 7,13), layout A (Task 13), drill-down navegación (Task 13,15) + caveat de honrar params (Follow-up), charts lib (Task 9,14), default route (Task 15), backend hexagonal (Task 1-7). ✅
- **Sin placeholders**: código completo en cada step; la única lectura previa (Task 5) es para confirmar firmas reales del servicio DNMA antes de usarlas en Task 6. ✅
- **Consistencia de tipos**: projections (`Long`) → DTOs (`long`/`double`) con `nz()`; nombres de métodos del repo usados consistentemente en service y tests; `getSummary(LocalDate,LocalDate)` consistente entre interface, impl, controller. ✅
