# Fixes Testeo DEV & PRE Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply 18 fixes from the PDF "Recetalia - Testeo DEV & PRE" (2026-04-28) across 4 projects of the workspace (3 Angular frontends + 1 Spring Boot API) and redeploy the result to pre-prod (`138.197.150.98`).

**Architecture:** Single-spec / single-plan / single-redeploy. Backend changes (timezone, null-safety in DNMA lookup, extended dispensation row, new filters) are delivered first to keep them backward-compatible. Frontend changes consume those backend changes plus a set of pure-FE bug fixes (initial-load triggers, sidebar shell, sort defaults, fallbacks, missing columns/filters). The redeploy uses the existing `deploy-recetalia/scripts/build-and-push.sh` + `deploy.sh` pipeline.

**Tech Stack:**
- Java 21 / Spring Boot 3.3.0 / Gradle / JUnit 5 / Mockito (backend)
- Angular 18.2 SSR / NgModule / TypeScript strict / PrimeNG 17 / Karma (frontends — most have inactive test suites)
- docker-compose v2 + nginx + self-hosted registry (deploy)

**Branches in scope:**
- `recetalia-api-rest` → `register_medic`
- `medics-recetalia-app`, `farmacias-recetalia-app`, `gestion-recetadigital-app`, `deploy-recetalia` → `feature/workspace-bootstrap`

**Spec:** `/Users/pablo/iwtg/recetalia-workspace/doc/plans/2026-04-28-fixes-testeo-dev-pre-design.md`

---

## File map (decisions locked in here)

### `recetalia-api-rest` (Java)
- Modify: `src/main/java/com/recetalia/api/application/controller/PrescriptionController.java` — timezone fix (lines 164-165 and 216-217 — there are TWO endpoints with the same conversion).
- Modify: `src/main/java/com/recetalia/api/application/controller/DispensationController.java` — timezone fix (lines 122, 126) + new optional `@RequestParam`s for `pharmacyId` and `status`.
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PrescriptionServiceImpl.java` — null-safe DNMA lookup with WARN log (around lines 266-294).
- Modify: `src/main/java/com/recetalia/api/application/dto/response/DispensationSearchRow.java` — add `getPharmacyId`, `getPharmacyName`, `getPharmacyBusinessName`.
- Modify: `src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java` — extend SELECT/JOIN of native query for pharmacy + new WHERE clauses for `pharmacyId` / `status` + flip `<` to `<=` on line 153 for symmetry.
- Create: `src/test/java/com/recetalia/api/application/controller/PrescriptionControllerTimezoneTest.java`
- Create: `src/test/java/com/recetalia/api/application/controller/DispensationControllerTimezoneTest.java`
- Create: `src/test/java/com/recetalia/api/application/service/impl/PrescriptionServiceDnmaNullSafetyTest.java`

### `medics-recetalia-app` (Angular)
- Modify: `src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.ts` — trigger initial load.
- Modify: `src/app/pages/application/home/home.component.{ts,html}` — sidebar default expanded.
- Modify: `src/app/components/sidebar/*` (path to confirm in Task 9) — show medic name.
- Modify: `src/app/pages/application/home/medicine/medicine-list/medicine-list.component.{html,scss,ts}` — eliminate Horas/Días dropdowns, fix Crónico margin.

### `farmacias-recetalia-app` (Angular)
- Modify: `src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.ts` — fix initial load.
- Modify: `src/app/pages/application/home/home.component.{ts,html}` — sidebar default expanded.
- Modify: `src/app/components/sidebar/*` (path to confirm in Task 14) — show pharmacy name.
- Modify: `src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.{ts,html}` — clear code after dispensar.

### `gestion-recetadigital-app` (Angular)
- Modify: `src/app/pages/application/home/pharmacy/pharmacy-list/pharmacy-list.component.ts` — initial load.
- Modify: `src/app/pages/application/home/patient/patient-list/patient-list.component.ts` (or service) — sort DESC.
- Modify: `src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.{ts,html}` — modal init load + column MÉDICO + fallback helper + filter Médico fix.
- Modify: `src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.{ts,html}` — columns FARMACIA/MÉDICO, filters Farmacia/Médico/Estado, fallback helper.

### `deploy-recetalia`
- No code modifications. Used only for the build/push/deploy run in Phase 5.

---

## Phase 1 — Backend (`recetalia-api-rest`)

### Task 1: Add `MONTEVIDEO_ZONE` constant + fix `PrescriptionController` timezone (G4)

**Goal:** Both filter-by-date code paths in `PrescriptionController` must convert `LocalDate` to `Instant` using America/Montevideo, not `ZoneId.systemDefault()`.

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/controller/PrescriptionController.java` (lines 164-165 and 216-217 + import)
- Create: `recetalia-api-rest/src/test/java/com/recetalia/api/application/controller/PrescriptionControllerTimezoneTest.java`

- [ ] **Step 1: Verify branch + working tree clean**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
git branch --show-current
git status
```
Expected: branch is `register_medic`; working tree clean.

- [ ] **Step 2: Read the two affected blocks to confirm exact context**

Read lines 160-170 and 212-220 of `src/main/java/com/recetalia/api/application/controller/PrescriptionController.java`. Confirm both blocks use the same pattern `startDate.atStartOfDay(ZoneId.systemDefault()).toInstant()`.

- [ ] **Step 3: Write the failing test**

Create `src/test/java/com/recetalia/api/application/controller/PrescriptionControllerTimezoneTest.java`:

```java
package com.recetalia.api.application.controller;

import org.junit.jupiter.api.Test;
import java.lang.reflect.Field;
import java.time.ZoneId;

import static org.junit.jupiter.api.Assertions.*;

class PrescriptionControllerTimezoneTest {

    @Test
    void controllerHoldsAmericaMontevideoZoneConstant() throws Exception {
        Field zoneField = PrescriptionController.class.getDeclaredField("MONTEVIDEO_ZONE");
        zoneField.setAccessible(true);
        Object value = zoneField.get(null);
        assertEquals(ZoneId.of("America/Montevideo"), value,
            "PrescriptionController must use America/Montevideo for date-range filtering");
    }
}
```

- [ ] **Step 4: Run the test — it must fail**

```bash
./gradlew test --tests com.recetalia.api.application.controller.PrescriptionControllerTimezoneTest
```
Expected: FAIL with `NoSuchFieldException: MONTEVIDEO_ZONE`.

- [ ] **Step 5: Apply the fix**

In `PrescriptionController.java`:

a) Add inside the class, near the top after existing field declarations:

```java
private static final ZoneId MONTEVIDEO_ZONE = ZoneId.of("America/Montevideo");
```

b) Replace lines 164-165 (the FIRST occurrence — `getPrescriptionsByMedicalProvider`-style endpoint):

```java
Instant startInstant = startDate != null ? startDate.atStartOfDay(MONTEVIDEO_ZONE).toInstant() : null;
Instant endInstant = endDate != null ? endDate.atStartOfDay(MONTEVIDEO_ZONE).plusDays(1).minusNanos(1).toInstant() : null;
```

c) Replace lines 216-217 (the SECOND occurrence — `getPrescriptionsByFilters`):

```java
Instant startInstant = startDate != null ? startDate.atStartOfDay(MONTEVIDEO_ZONE).toInstant() : null;
Instant endInstant = endDate != null ? endDate.atStartOfDay(MONTEVIDEO_ZONE).plusDays(1).minusNanos(1).toInstant() : null;
```

(Imports: `java.time.ZoneId` may already be present from the existing `ZoneId.systemDefault()` usage. If not, add `import java.time.ZoneId;`.)

- [ ] **Step 6: Run the test — must now pass**

```bash
./gradlew test --tests com.recetalia.api.application.controller.PrescriptionControllerTimezoneTest
```
Expected: PASS.

- [ ] **Step 7: Run the full module's tests to ensure no regression**

```bash
./gradlew test
```
Expected: BUILD SUCCESSFUL with all tests passing. If a pre-existing test fails for unrelated reasons, document it but do not fix here unless trivial.

- [ ] **Step 8: Commit**

```bash
git add src/main/java/com/recetalia/api/application/controller/PrescriptionController.java \
        src/test/java/com/recetalia/api/application/controller/PrescriptionControllerTimezoneTest.java
git commit -m "fix(prescriptions): use America/Montevideo for date-range filter (G4)"
```

---

### Task 2: Fix `DispensationController` timezone (G8) + flip `<` to `<=` (bonus)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/controller/DispensationController.java` (lines 122, 126)
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java` (line 153)
- Create: `recetalia-api-rest/src/test/java/com/recetalia/api/application/controller/DispensationControllerTimezoneTest.java`

- [ ] **Step 1: Write the failing test**

Create `src/test/java/com/recetalia/api/application/controller/DispensationControllerTimezoneTest.java`:

```java
package com.recetalia.api.application.controller;

import org.junit.jupiter.api.Test;
import java.lang.reflect.Field;
import java.time.ZoneId;

import static org.junit.jupiter.api.Assertions.*;

class DispensationControllerTimezoneTest {

    @Test
    void controllerHoldsAmericaMontevideoZoneConstant() throws Exception {
        Field zoneField = DispensationController.class.getDeclaredField("MONTEVIDEO_ZONE");
        zoneField.setAccessible(true);
        Object value = zoneField.get(null);
        assertEquals(ZoneId.of("America/Montevideo"), value,
            "DispensationController must use America/Montevideo for date-range filtering");
    }
}
```

- [ ] **Step 2: Run the test — it must fail**

```bash
./gradlew test --tests com.recetalia.api.application.controller.DispensationControllerTimezoneTest
```
Expected: FAIL with `NoSuchFieldException: MONTEVIDEO_ZONE`.

- [ ] **Step 3: Add constant + replace `ZoneId.systemDefault()` calls**

In `DispensationController.java`, add at the top of the class (after existing fields):

```java
private static final ZoneId MONTEVIDEO_ZONE = ZoneId.of("America/Montevideo");
```

Replace lines 122 and 126 (the `search()` method's date conversion):

```java
Instant fromTs = (startDate != null)
        ? startDate.atStartOfDay(MONTEVIDEO_ZONE).toInstant()
        : null;

Instant toTs = (endDate != null)
        ? endDate.atStartOfDay(MONTEVIDEO_ZONE).plusDays(1).minusNanos(1).toInstant()
        : null;
```

- [ ] **Step 4: Bonus — flip `<` to `<=` in `DispensationRepository.java:153`**

In `src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java`, locate line ~153 inside the native `@Query` (the `AND COALESCE(d.updatedAt, d.createdAt) < CAST(:toTs AS DATETIME(6))` clause).

Change it to:

```sql
AND COALESCE(d.updatedAt, d.createdAt) <= CAST(:toTs AS DATETIME(6))
```

(Symmetry with `PrescriptionRepository.java`. Effect is functionally tiny — only the last nanosecond of the day-after-`endDate` — but removes a confusing inconsistency.)

- [ ] **Step 5: Run the test — must pass**

```bash
./gradlew test --tests com.recetalia.api.application.controller.DispensationControllerTimezoneTest
```
Expected: PASS.

- [ ] **Step 6: Full test run**

```bash
./gradlew test
```
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add src/main/java/com/recetalia/api/application/controller/DispensationController.java \
        src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java \
        src/test/java/com/recetalia/api/application/controller/DispensationControllerTimezoneTest.java
git commit -m "fix(dispensations): use America/Montevideo for date-range filter, symmetric upper bound (G8)"
```

---

### Task 3: Null-safe DNMA lookup in `PrescriptionServiceImpl` (G7-BE / G11-BE)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/PrescriptionServiceImpl.java` (around lines 266-294, method `mapPrescriptionWithAmpDetailsOption2`)
- Create: `recetalia-api-rest/src/test/java/com/recetalia/api/application/service/impl/PrescriptionServiceDnmaNullSafetyTest.java`

**Why:** today the method has a try-catch that swallows any error from the DNMA lookup; if the lookup returns an empty map for a `productId`, calling `.get("vmp_dsc")` on null throws NPE which the catch hides — so the response silently has `vmpDsc=null`. We want explicit null-checks + a WARN log so the missing products are visible.

- [ ] **Step 1: Read the current method to confirm exact shape**

Read `src/main/java/com/recetalia/api/application/service/impl/PrescriptionServiceImpl.java` lines 250-310. Confirm the structure:
- a `try { ... } catch (Exception e) { ... }` block around lines 266-294
- Inside, branches on `prescription.getProductType()` calling `dnmaDatabaseServiceImpl.fetchVmpDetails(...)` or `fetchAmpDetails(...)`
- Calls like `vmpDetails.get("vmp_dsc")` that can NPE.

If the line numbers drift, anchor to the method name `mapPrescriptionWithAmpDetailsOption2` (or whichever variant is mapped from the controller of `getPrescriptionsByFilters`).

- [ ] **Step 2: Write the failing test**

Create `src/test/java/com/recetalia/api/application/service/impl/PrescriptionServiceDnmaNullSafetyTest.java`:

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.Prescription;
import com.recetalia.api.application.dto.response.PrescriptionResponse;
import org.junit.jupiter.api.Test;

import java.util.Collections;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class PrescriptionServiceDnmaNullSafetyTest {

    @Test
    void leavesProductDescriptionsNullWhenDnmaLookupReturnsEmpty() {
        Prescription p = new Prescription();
        p.setId("test-prescription-id");
        p.setProductType("VMP");
        p.setProductId("missing-vmp-id");

        // Stub: dnmaDatabaseServiceImpl.fetchVmpDetails returns an empty map (no entry for productId).
        Map<String, Map<String, String>> emptyResult = Collections.emptyMap();

        PrescriptionResponse response = new PrescriptionResponse();

        // Direct invocation of the helper. If the helper is private, exercise it via the public path
        // mapPrescriptionWithAmpDetailsOption2(prescription, emptyResult) — adjust signature to match.
        // This test must fail today because the current code swallows the NPE silently and the
        // assertion below for "no exception thrown" is fine, but we also assert that the response
        // fields are null (which they already are by default, so the test relies on confirming
        // that no exception escapes).
        PrescriptionServiceImpl service = new PrescriptionServiceImpl();
        assertDoesNotThrow(() -> service.applyVmpDetailsForTest(p, emptyResult, response));

        assertNull(response.getVmpDsc());
        assertNull(response.getAmpDsc());
    }
}
```

> Note: `applyVmpDetailsForTest(...)` is a **package-private testing seam** we will introduce in Step 3. If the existing helper method is already package-private and named differently, rename the test call accordingly.

- [ ] **Step 3: Run the test — it fails**

```bash
./gradlew test --tests com.recetalia.api.application.service.impl.PrescriptionServiceDnmaNullSafetyTest
```
Expected: FAIL with compilation error (`applyVmpDetailsForTest not found`) or, if the seam exists, with NPE/wrong assertion.

- [ ] **Step 4: Apply the fix**

In `PrescriptionServiceImpl.java`:

a) Add at the top of the file (if not present):

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
```

b) Add as a class field (if not present):

```java
private static final Logger log = LoggerFactory.getLogger(PrescriptionServiceImpl.class);
```

c) Replace the swallowing try-catch (lines ~266-294) with explicit null-checks:

```java
if ("VMP".equals(prescription.getProductType())) {
    Map<String, Map<String, String>> vmpDetailsMap =
            dnmaDatabaseServiceImpl.fetchVmpDetails(List.of(prescription.getProductId()));
    Map<String, String> vmpDetails = vmpDetailsMap.get(prescription.getProductId());
    if (vmpDetails == null || vmpDetails.isEmpty()) {
        log.warn("DNMA lookup returned no VMP details for productId={} (prescriptionId={})",
                prescription.getProductId(), prescription.getId());
    } else {
        response.setVmpDsc(vmpDetails.get("vmp_dsc"));
    }
} else {
    Map<String, Map<String, String>> ampDetailsMap =
            dnmaDatabaseServiceImpl.fetchAmpDetails(List.of(prescription.getProductId()));
    Map<String, String> ampDetails = ampDetailsMap.get(prescription.getProductId());
    if (ampDetails == null || ampDetails.isEmpty()) {
        log.warn("DNMA lookup returned no AMP details for productId={} (prescriptionId={})",
                prescription.getProductId(), prescription.getId());
    } else {
        response.setAmpDsc(ampDetails.get("amp_dsc"));
        // Preserve any other fields that the original code mapped — e.g. nombreLaboratory, prodMsp.
        // Read the original block in Step 1 and replicate the assignments here, all guarded by
        // the same null-check.
    }
}
```

> **Important:** When you read the original block in Step 1, you may find additional fields being mapped (e.g. `prodMsp`, `nombreLaboratory`). Replicate every original `response.setXxx(...)` inside the corresponding `else` branch so no field is accidentally dropped. The structural change is: replace `try { ... } catch (Exception) {}` with `if (details == null) { log.warn(...) } else { ...same setters... }`.

d) Add a package-private testing seam if missing:

```java
void applyVmpDetailsForTest(Prescription prescription,
                            Map<String, Map<String, String>> vmpDetailsMap,
                            PrescriptionResponse response) {
    Map<String, String> vmpDetails = vmpDetailsMap.get(prescription.getProductId());
    if (vmpDetails == null || vmpDetails.isEmpty()) {
        log.warn("DNMA lookup returned no VMP details for productId={} (prescriptionId={})",
                prescription.getProductId(), prescription.getId());
        return;
    }
    response.setVmpDsc(vmpDetails.get("vmp_dsc"));
}
```

- [ ] **Step 5: Run the test — must pass**

```bash
./gradlew test --tests com.recetalia.api.application.service.impl.PrescriptionServiceDnmaNullSafetyTest
```
Expected: PASS.

- [ ] **Step 6: Full test run**

```bash
./gradlew test
```
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/impl/PrescriptionServiceImpl.java \
        src/test/java/com/recetalia/api/application/service/impl/PrescriptionServiceDnmaNullSafetyTest.java
git commit -m "fix(prescriptions): null-safe DNMA lookup with WARN log (G7/G11 backend)"
```

---

### Task 4: Extend `DispensationSearchRow` interface with pharmacy fields (G9-BE)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/response/DispensationSearchRow.java`

- [ ] **Step 1: Read the file to confirm interface shape**

Read `src/main/java/com/recetalia/api/application/dto/response/DispensationSearchRow.java`. Confirm it's a JPA projection interface with getters like `getDispensationId`, `getMedicId`, `getMedicName`, `getMedicLastname`, `getDispensationStatus`, `getDispensationProductName`, etc.

- [ ] **Step 2: Add the three pharmacy getters**

Append to the interface (before the closing `}`):

```java
String getPharmacyId();
String getPharmacyName();
String getPharmacyBusinessName();
```

- [ ] **Step 3: Compile**

```bash
./gradlew compileJava
```
Expected: BUILD SUCCESSFUL (the interface change alone shouldn't break callers).

- [ ] **Step 4: Commit**

```bash
git add src/main/java/com/recetalia/api/application/dto/response/DispensationSearchRow.java
git commit -m "feat(dispensations): add pharmacy fields to DispensationSearchRow projection (G9 backend)"
```

---

### Task 5: Extend `DispensationRepository` SQL + add `pharmacyId`/`status` filter params (G9-BE + G10-BE)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/controller/DispensationController.java` (extend `search()` signature with new optional params + pass-through to service/repo)

- [ ] **Step 1: Read repository's `search` native query**

Read `src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java` lines 60-210. Identify:
- The `@Query(value = "...", nativeQuery = true)` annotation.
- The current SELECT (around lines 80-113) — note which tables are joined.
- The current WHERE clauses (around lines 145-200).
- Whether `pharmacies` is already joined. If yes, just reference it; if no, add `LEFT JOIN pharmacies ph ON ph.id = d.pharmacy_id`.

- [ ] **Step 2: Add pharmacy columns to SELECT**

Inside the SELECT clause, add (alongside existing aliases):

```sql
ph.id AS pharmacyId,
ph.name AS pharmacyName,
ph.business_name AS pharmacyBusinessName,
```

Add the JOIN if missing (after the existing `LEFT JOIN`s):

```sql
LEFT JOIN pharmacies ph ON ph.id = d.pharmacy_id
```

(Adjust column names — `business_name` may be `businessName`, `razon_social`, etc. — by matching what's already used in `Pharmacy.java` entity.)

- [ ] **Step 3: Add `pharmacyId` and `status` filter clauses**

Inside the WHERE block, add:

```sql
AND (:pharmacyId IS NULL OR d.pharmacy_id = :pharmacyId)
AND (:status IS NULL OR d.status = :status)
```

- [ ] **Step 4: Update method signature**

Add the new parameters to the `search` method (whatever its exact name is — likely `search(...)` or `findDispensations(...)`):

```java
@Param("pharmacyId") String pharmacyId,
@Param("status") String status,
```

- [ ] **Step 5: Update `DispensationController.search()` to forward the new params**

In `src/main/java/com/recetalia/api/application/controller/DispensationController.java` `search(...)` method, add to the `@RequestParam` list:

```java
@RequestParam(required = false) String pharmacyId,
@RequestParam(required = false) String status,
```

Then pass them through to whatever service/repo call exists (the controller should already be propagating things like `dispensedById`, `laboratoryId` — match that pattern). Identify the propagation chain: usually `controller -> service -> repository.search(...)`. Add the two parameters at every layer.

- [ ] **Step 6: Compile + smoke test the change**

```bash
./gradlew compileJava
```
Expected: BUILD SUCCESSFUL.

If a `*Test.java` exercises this repository, run it:

```bash
./gradlew test --tests "*Dispensation*"
```
Expected: PASS (or no tests found — acceptable here; we'll smoke-test against real DB during the post-deploy phase).

- [ ] **Step 7: Commit**

```bash
git add src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java \
        src/main/java/com/recetalia/api/application/controller/DispensationController.java
git commit -m "feat(dispensations): expose pharmacy fields and pharmacyId/status filters in search endpoint (G9/G10 backend)"
```

---

### Task 6: Backend build + final verification

- [ ] **Step 1: Full rebuild**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
./gradlew clean build
```
Expected: BUILD SUCCESSFUL with all tests passing.

- [ ] **Step 2: Confirm git log shows the 4 backend commits**

```bash
git log --oneline -n 6
```
Expected: 4 new commits (Tasks 1, 2, 3, 4+5 — Tasks 4 and 5 may be one or two commits).

---

## Phase 2 — Frontend `medics-recetalia-app`

### Task 7: Trigger initial load in medics Prescriptions list (M3)

**Files:**
- Modify: `medics-recetalia-app/src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.ts`

- [ ] **Step 1: Read `ngOnInit` (around lines 139-159)**

Read the `ngOnInit` method. Confirm that it calls `getPatientsByMedic()` and similar, but does NOT call `loadPrescriptions(...)`. Confirm `loadPrescriptions` exists (around lines 200-260) and that `this.size`, `this.page` are class fields with sensible defaults (likely `size = 25`, `page = 0`).

- [ ] **Step 2: Add the initial load call at the end of `ngOnInit`**

Append before the closing `}` of `ngOnInit`:

```typescript
this.loadPrescriptions({ first: 0, rows: this.size });
```

If `loadPrescriptions` expects a different shape, adapt to match its signature (e.g. `this.loadPrescriptions()` with no arg, or with `{ page: 0, size: this.size }`). Read the method's first lines to know.

- [ ] **Step 3: Build to verify no TS errors**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/medics-recetalia-app
npm run build
```
Expected: build succeeds.

- [ ] **Step 4: Manual smoke (optional pre-deploy)**

```bash
npm start
```
Open `http://localhost:4200`, login as a test medic, navigate to Prescripciones. Expected: list either populates with rows or shows "no rows" — but **no infinite spinner**. Stop the dev server (Ctrl+C).

- [ ] **Step 5: Commit**

```bash
git add src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.ts
git commit -m "fix(medics): trigger initial loadPrescriptions in list component (M3)"
```

---

### Task 8: Sidebar default expanded + medic name in shell (M5/M6)

**Files:**
- Modify: `medics-recetalia-app/src/app/pages/application/home/home.component.ts` (set `isSidebarHidden = false` initial)
- Modify: `medics-recetalia-app/src/app/components/sidebar/sidebar.component.{ts,html}` (path TBD in Step 1 — show medic name)
- Read: `medics-recetalia-app/src/app/services/auth.service.ts` and `medics.service.ts` to fetch the medic by email

- [ ] **Step 1: Locate the sidebar component**

```bash
grep -rln "app-sidebar\|isSidebarHidden\|sidebarToggle" /Users/pablo/iwtg/recetalia-workspace/medics-recetalia-app/src/app
```

Likely path: `src/app/components/sidebar/sidebar.component.ts` (with sibling `.html`). Open both.

- [ ] **Step 2: Set sidebar default to expanded in `home.component.ts`**

Read `src/app/pages/application/home/home.component.ts`. Find the field `isSidebarHidden`. Set its initial value to `false`:

```typescript
isSidebarHidden = false;
```

(If it was previously `true` or unset, this guarantees the sidebar starts expanded.)

- [ ] **Step 3: Add a `medicName` observable to the sidebar component**

In `src/app/components/sidebar/sidebar.component.ts`, inject `AuthService` and `MedicsService` if not already there:

```typescript
import { AuthService } from '../../services/auth.service';
import { MedicsService } from '../../services/medics.service';

// ...inside the class
medicFullName: string = '';

constructor(
    private authService: AuthService,
    private medicsService: MedicsService,
    // ...other existing deps
) {}

ngOnInit(): void {
    const token = this.authService.getToken?.() ?? localStorage.getItem('token');
    if (!token) return;

    // Decode JWT (fast inline decode, no extra dependency)
    const payload = JSON.parse(atob(token.split('.')[1]));
    const email = payload?.mail ?? payload?.sub;
    if (!email) return;

    this.medicsService.getByEmail(email).subscribe({
        next: (medic: any) => {
            this.medicFullName = `${medic.firstName ?? ''} ${medic.lastName ?? ''}`.trim();
        },
        error: () => { /* swallow — sidebar still works without name */ }
    });
}
```

> If `MedicsService.getByEmail` does not exist, search for the actual method name with `grep -n "getByEmail\|byEmail\|findByEmail\|getMedicByEmail" src/app/services/medics.service.ts`. Use whichever method calls `/api/medics/email/{email}`.

- [ ] **Step 4: Show the name in `sidebar.component.html`**

Read the existing template. Insert a header block — preferably right under the logo, above the menu items:

```html
<div class="sidebar-user" *ngIf="medicFullName">
    <i class="pi pi-user"></i>
    <span>{{ medicFullName }}</span>
</div>
```

(Apply minimal CSS in `sidebar.component.scss` if needed: `padding: .5rem 1rem; font-weight: 600;`.)

- [ ] **Step 5: Build**

```bash
npm run build
```
Expected: success.

- [ ] **Step 6: Commit**

```bash
git add src/app/pages/application/home/home.component.ts \
        src/app/components/sidebar/sidebar.component.ts \
        src/app/components/sidebar/sidebar.component.html \
        src/app/components/sidebar/sidebar.component.scss
git commit -m "feat(medics): sidebar expanded by default with medic full name (M5/M6)"
```

---

### Task 9: Eliminate Horas/Días dropdowns + margin on Crónico (M1, M2)

**Files:**
- Modify: `medics-recetalia-app/src/app/pages/application/home/medicine/medicine-list/medicine-list.component.{html,ts,scss}` (this is the "Buscar medicamento" modal — it has Frecuencia/Duración fields and the Crónico checkbox)

- [ ] **Step 1: Read the template**

Open `src/app/pages/application/home/medicine/medicine-list/medicine-list.component.html`. Locate:
- The Frecuencia field with its `<p-dropdown>` for "Horas".
- The Duración field with its `<p-dropdown>` for "Días".
- The Crónico checkbox (`<p-checkbox>` or similar with label "Crónico" / `cronic`).

- [ ] **Step 2: Replace dropdowns with fixed text labels**

For Frecuencia, change:

```html
<!-- BEFORE -->
<p-dropdown [options]="frecuencyUnitOptions" formControlName="frecuencyUnit" placeholder="Horas"></p-dropdown>
```

to:

```html
<!-- AFTER -->
<span class="unit-label">Horas</span>
```

Similarly for Duración → `<span class="unit-label">Días</span>`.

- [ ] **Step 3: Hardcode the values in the component .ts**

In `medicine-list.component.ts`, locate the existing `FormBuilder.group({...})` call (probably named `this.medicineForm` or `this.form`). Do NOT rewrite the whole group — just modify the two unit fields and remove dropdown-options arrays:

a) Inside the form group config, set the two unit keys to hardcoded literals:

```typescript
frecuencyUnit: ['HOURS'],
durationUnit: ['DAYS'],
```

If those keys do not currently exist (the form may currently bind them via the dropdown's `formControlName`), add them with the values above. Preserve all other existing keys (`indicaciones`, `frecuency`, `duracion`, `isCronic`, etc.) untouched.

b) Confirm the exact contract key names by running:

```bash
grep -n "frecuencyUnit\|durationUnit\|isCronic" src/app/model/request/prescription-request.ts
```

If the request DTO uses different names, rename the form keys accordingly.

c) Remove from the component class any field that holds the dropdown options (likely `frecuencyUnitOptions` / `durationUnitOptions`) plus any code that populates them. They are no longer used.

- [ ] **Step 4: Add CSS for the new label + margin on Crónico**

In `medicine-list.component.scss`, add:

```scss
.unit-label {
    display: inline-block;
    padding: 0.5rem 0.75rem;
    color: #666;
    font-size: 0.95rem;
}

.cronic-checkbox-wrapper,
:host ::ng-deep .p-checkbox-label {
    /* Match the existing class wrapping the Crónico checkbox; if the wrapper has no class,
       add one in the template (e.g. <div class="cronic-checkbox-wrapper">...) */
    margin-left: 1rem;
}
```

In the template, ensure the Crónico checkbox is wrapped in `<div class="cronic-checkbox-wrapper">` (or apply the margin to whatever wrapper currently holds it).

- [ ] **Step 5: Build**

```bash
npm run build
```
Expected: success.

- [ ] **Step 6: Commit**

```bash
git add src/app/pages/application/home/medicine/medicine-list/
git commit -m "ui(medics): remove Horas/Días dropdowns and add margin to Crónico in medicamento modal (M1/M2)"
```

---

### Task 10: medics — final build verification

- [ ] **Step 1: Build with the `preprod` configuration to mirror what gets deployed**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/medics-recetalia-app
npm run build -- --configuration=preprod
```

If the script doesn't accept `--configuration`, use the raw Angular CLI:

```bash
./node_modules/.bin/ng build --configuration=preprod
```

Expected: build succeeds; `dist/medics-recetalia-app/` is updated.

- [ ] **Step 2: Confirm 3 commits on the branch**

```bash
git log --oneline -n 5
```
Expected: 3 new commits (M3, M5/M6, M1/M2).

---

## Phase 3 — Frontend `farmacias-recetalia-app`

### Task 11: Fix dispensation-list initial load (F3)

**Files:**
- Modify: `farmacias-recetalia-app/src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.ts` (lines 110-119)

- [ ] **Step 1: Read `ngOnInit` (lines 110-120) and `getCurrentUser` flow**

Open the file. Confirm the current `ngOnInit` waits for `authService.getCurrentUser()` with `take(1)` and only sets `pharmacyId` if `user.pharmacyId` is truthy.

- [ ] **Step 2: Rewrite the init to be sync-first with async fallback**

Replace the existing `ngOnInit`:

```typescript
ngOnInit(): void {
    // 1) Try sync sources first.
    const syncPharmacyId = this.resolvePharmacyIdSync();
    if (syncPharmacyId) {
        this.pharmacyId = syncPharmacyId;
        this.refreshTable();
        return;
    }

    // 2) Fall back to async resolution.
    this.authService.getCurrentUser().pipe(
        filter((u: any) => !!u?.pharmacyId),
        take(1)
    ).subscribe({
        next: (user: any) => {
            this.pharmacyId = user.pharmacyId;
            this.refreshTable();
        },
        error: () => {
            this.loading = false;
            this.errorMessage = 'No se pudo identificar la farmacia del usuario actual.';
        }
    });
}

private resolvePharmacyIdSync(): string | null {
    const token = localStorage.getItem('token');
    if (!token) return null;
    try {
        const payload = JSON.parse(atob(token.split('.')[1]));
        return payload?.pharmacyId ?? null;
    } catch {
        return null;
    }
}
```

Add the imports if missing:

```typescript
import { filter, take } from 'rxjs/operators';
```

- [ ] **Step 3: Surface the error in the template**

In `dispensation-list.component.html`, add near the top of the table block (only if `errorMessage` is set):

```html
<div class="error-banner" *ngIf="errorMessage">{{ errorMessage }}</div>
```

Add the field declaration in the `.ts`:

```typescript
errorMessage: string | null = null;
```

- [ ] **Step 4: Build**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/farmacias-recetalia-app
npm run build
```
Expected: success.

- [ ] **Step 5: Commit**

```bash
git add src/app/pages/application/home/dispensations/dispensation-list/
git commit -m "fix(farmacias): resolve pharmacyId sync-first in dispensation-list init (F3)"
```

---

### Task 12: Sidebar default expanded + pharmacy name (F1/F2)

**Files:**
- Modify: `farmacias-recetalia-app/src/app/pages/application/home/home.component.ts` (`isSidebarHidden = false`)
- Modify: `farmacias-recetalia-app/src/app/components/sidebar/sidebar.component.{ts,html,scss}` (TBD — same discovery as medics)

- [ ] **Step 1: Locate the sidebar component**

```bash
grep -rln "app-sidebar\|isSidebarHidden\|sidebarToggle" /Users/pablo/iwtg/recetalia-workspace/farmacias-recetalia-app/src/app
```

- [ ] **Step 2: `isSidebarHidden = false` in `home.component.ts`**

Same as Task 8 Step 2.

- [ ] **Step 3: Pharmacy name in sidebar**

In the sidebar component:

```typescript
import { AuthService } from '../../services/auth.service';
import { PharmacyService } from '../../services/pharmacy.service'; // or whichever service exposes getByEmail

pharmacyName: string = '';

ngOnInit(): void {
    const token = localStorage.getItem('token');
    if (!token) return;
    const payload = JSON.parse(atob(token.split('.')[1]));
    const email = payload?.mail ?? payload?.sub;
    if (!email) return;

    this.pharmacyService.getByEmail(email).subscribe({
        next: (pharmacy: any) => {
            this.pharmacyName = pharmacy.name?.trim() || pharmacy.businessName?.trim() || '';
        },
        error: () => { /* swallow */ }
    });
}
```

> If the pharmacy service doesn't expose `getByEmail`, search: `grep -n "getByEmail\|byEmail\|findByEmail" src/app/services/pharmacy.service.ts` (or `pharmacies.service.ts`). The endpoint is `GET /api/pharmacies/email/{email}`.

- [ ] **Step 4: Render in template**

Same block as medics (Task 8 Step 4), bound to `pharmacyName`.

- [ ] **Step 5: Build + commit**

```bash
npm run build
git add src/app/pages/application/home/home.component.ts \
        src/app/components/sidebar/
git commit -m "feat(farmacias): sidebar expanded by default with pharmacy name (F1/F2)"
```

---

### Task 13: Clear código input after dispensar (F6)

**Files:**
- Modify: `farmacias-recetalia-app/src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.ts`

- [ ] **Step 1: Locate the dispensar success handler**

Read `src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.ts`. Look for:
- A method that calls the dispensation API (likely named `dispensar()` / `onDispensar()` / `submitDispensation()`).
- Inside its `subscribe(...)` next callback, add the cleanup. The agent's investigation found a `search()` method at line 145 and `this.search(false)` calls at lines 426 and 433 — those are likely the entry points after successful dispense.

- [ ] **Step 2: Add the cleanup in the success callback**

Find the place where the dispensar HTTP call's `.subscribe({ next: ... })` runs. Right at the start of the `next` callback (after a possible toast/snackbar success message), add:

```typescript
// Clear search input so the prescription code does not linger.
this.code = '';
if (this.codeControl) {
    this.codeControl.setValue('');
}
this.codeControl?.markAsPristine();
this.codeControl?.markAsUntouched();
```

(Adapt names: the field that holds the code in the form may be `this.code`, `this.codigoControl`, or part of a `FormGroup`. Read the component's fields at the top to know.)

If the form is reactive (`FormGroup`), prefer:

```typescript
this.searchForm.reset();
```

If imperative (no FormGroup, just `this.code = ''`), the simple assignment is enough.

- [ ] **Step 3: Build**

```bash
npm run build
```

- [ ] **Step 4: Commit**

```bash
git add src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.ts
git commit -m "fix(farmacias): clear código input after successful dispensar (F6)"
```

---

### Task 14: farmacias — final build verification

- [ ] **Step 1: Build with `preprod`**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/farmacias-recetalia-app
npm run build -- --configuration=preprod
```

- [ ] **Step 2: Confirm 3 commits**

```bash
git log --oneline -n 5
```
Expected: 3 new commits (F3, F1/F2, F6).

---

## Phase 4 — Frontend `gestion-recetadigital-app`

### Task 15: Pharmacies list initial load (G1)

**Files:**
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/pharmacy/pharmacy-list/pharmacy-list.component.ts`

- [ ] **Step 1: Read the component**

Read `pharmacy-list.component.ts`. Confirm `ngOnInit` does NOT call the loader. Note the exact name of the loader method (likely `loadPharmacies` / `searchPharmacies` / `refreshTable`).

- [ ] **Step 2: Add the loader call to `ngOnInit`**

Append before the closing `}` of `ngOnInit`:

```typescript
this.loadPharmacies({ first: 0, rows: this.size });
```

(If the method is named differently, use that name. If `this.size` does not exist, use `this.rows = 25` or the existing field.)

- [ ] **Step 3: Build**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app
npm run build
```

- [ ] **Step 4: Commit**

```bash
git add src/app/pages/application/home/pharmacy/pharmacy-list/pharmacy-list.component.ts
git commit -m "fix(gestion): trigger initial pharmacy load in list component (G1)"
```

---

### Task 16: Patients list — sort DESC by createdAt (G2)

**Files:**
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/patient/patient-list/patient-list.component.ts` and/or `src/app/services/patient.service.ts`

- [ ] **Step 1: Locate the sort param construction**

```bash
grep -n "sort\|page\|HttpParams" /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app/src/app/services/patient.service.ts /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app/src/app/pages/application/home/patient/patient-list/patient-list.component.ts
```

Identify whether the component sets `sort` directly in the URL params or whether the service builds it. The default Spring Data `Pageable` sort param looks like `sort=createdAt,desc`.

- [ ] **Step 2: Set the default sort in the component (or service)**

Inside `patient-list.component.ts`, where `loadPatients(...)` (or equivalent) builds the request, ensure it includes:

```typescript
const sort = 'createdAt,desc';
// e.g. when calling the service:
this.patientService.list({ page: this.page, size: this.size, sort });
```

If the service already accepts `sort` but the component doesn't pass it, pass it. If neither does, add it to the service signature and to all callers.

- [ ] **Step 3: Verify the table renders newest first**

```bash
npm start
```
Login as gestión, navigate to Pacientes. The most recent CREACIÓN date should be the first row. Stop the dev server.

- [ ] **Step 4: Commit**

```bash
git add src/app/pages/application/home/patient/patient-list/patient-list.component.ts \
        src/app/services/patient.service.ts
git commit -m "fix(gestion): sort patients by createdAt desc by default (G2)"
```

---

### Task 17: Patient detail modal — trigger initial Prescriptions load (G3)

**Files:**
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.ts` (lines 166-200)

- [ ] **Step 1: Read the component's `ngOnInit`**

Read `src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.ts:160-205`. Confirm it receives `config?.data?.patient` from `DynamicDialogConfig` and sets `patientId`, but does NOT call `loadPrescriptions(...)`.

- [ ] **Step 2: Add the trigger after `patientId` is set**

At the end of `ngOnInit` (after the `if (config?.data?.patient) { ... }` block):

```typescript
this.loadPrescriptions({ first: 0, rows: this.size });
```

(Confirm method name and signature — the same `loadPrescriptions` already used by the standalone Prescripciones list.)

- [ ] **Step 3: Build**

```bash
npm run build
```

- [ ] **Step 4: Commit**

```bash
git add src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.ts
git commit -m "fix(gestion): trigger initial loadPrescriptions in patient-detail modal (G3)"
```

---

### Task 18: Prescriptions list — add MÉDICO column + product fallback helper (G5, G7-FE)

**Files:**
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.ts`
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.html`

- [ ] **Step 1: Add the helper method to the component .ts**

Append inside the class:

```typescript
displayPrescriptionProductName(p: any): string {
    return p?.vmpDsc
        || p?.ampDsc
        || p?.prodMsp
        || p?.productId
        || '—';
}
```

- [ ] **Step 2: Add MÉDICO column in the table header**

In `prescription-list.component.html`, locate the `<th>` row of the prescriptions table. Insert a new `<th>` between the existing PACIENTE and MEDICAMENTO headers (or wherever fits the layout):

```html
<th>MÉDICO</th>
```

- [ ] **Step 3: Add MÉDICO cell in the table body**

In the same `<tr *ngFor="let prescription of ...">`, insert a `<td>` matching the header position:

```html
<td>{{ prescription.medicName }} {{ prescription.medicLastname }}</td>
```

(The backend `PrescriptionResponse` already returns `medicName` and `medicLastname` — no backend change needed.)

- [ ] **Step 4: Replace the broken VMP/AMP rendering with the helper**

Find lines 111-115 (approx) of the template, where today the medicamento column reads:

```html
<td>
    <span *ngIf="prescription.productType == 'VMP'">{{ prescription.vmpDsc }}</span>
    <span *ngIf="prescription.productType == 'AMP'">{{ prescription.ampDsc }}</span>
    <span *ngIf="prescription.productType == 'AMP'">{{ prescription.nombreLaboratory }}</span>
</td>
```

Replace with:

```html
<td>
    <div>{{ displayPrescriptionProductName(prescription) }}</div>
    <div *ngIf="prescription.productType === 'AMP' && prescription.nombreLaboratory" class="product-laboratory">
        {{ prescription.nombreLaboratory }}
    </div>
</td>
```

- [ ] **Step 5: Build**

```bash
npm run build
```

- [ ] **Step 6: Commit**

```bash
git add src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.ts \
        src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.html
git commit -m "feat(gestion): show MÉDICO column and productId fallback in prescriptions list (G5/G7)"
```

---

### Task 19: Diagnose + fix Médico filter in Prescriptions list (G6)

**Files:**
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.ts`
- Possibly: `gestion-recetadigital-app/src/app/services/medic.service.ts` (or `medics.service.ts`)

- [ ] **Step 1: Run dev server + reproduce in browser**

```bash
npm start
```

Login gestión, go to Prescripciones, open dev tools (Network + Console). Click the Médico dropdown.

- [ ] **Step 2: Diagnose with three checks**

(a) **Does the Médico dropdown populate?**
- If empty: the call to `medic.service.getAll()` (or similar) is failing or never fires. Inspect Network — is there a request to `/api/medics` or `/api/medics/by-medical-provider`? What's its response?
- Likely fix: in `prescription-list.component.ts`, ensure `loadMedics()` is called in `ngOnInit`. Add `this.loadMedics();` if missing.

(b) **Does selecting a Médico trigger a network call?**
- Open Network tab, select a medic. Look for a new request to `/api/prescriptions/get-prescriptions-by-filters`. Does it include `medicId=<uuid>` in the URL?
- If no request: the `(onChange)` handler doesn't dispatch `refreshTable()`. Find the `onMedicSelect` (or equivalent) and ensure it calls `this.loadPrescriptions(...)` after setting `selectedMedicId`.

(c) **Does the response include only that medic's prescriptions?**
- If the request includes `medicId` but the response is unfiltered: backend issue, not in scope. Document and skip.

- [ ] **Step 3: Apply the fix matching the diagnosed cause**

Most likely cases:
- **Missing `loadMedics()`:** add to `ngOnInit` after the existing init logic:
  ```typescript
  this.medicService.getAll().subscribe(medics => this.medics = medics);
  ```
  Confirm method name in the service. If the endpoint is `/api/medics/by-medical-provider`, scope it by medical provider id from the JWT or current user.

- **Handler not dispatching:** locate the dropdown in the template. Find `(onChange)="onMedicSelect($event)"`. In `onMedicSelect`:
  ```typescript
  onMedicSelect(event: any): void {
      this.selectedMedicId = event?.value ?? null;
      this.loadPrescriptions({ first: 0, rows: this.size });
  }
  ```

- **Param not making it to the URL:** in the prescription service `getPrescriptionsByFilters(...)`, ensure:
  ```typescript
  if (medicId) params = params.set('medicId', medicId);
  ```

- [ ] **Step 4: Re-test in browser to confirm filter works**

Reload, select a medic, confirm the table reduces to that medic's prescriptions only.

- [ ] **Step 5: Stop dev server + commit**

```bash
git add src/app/pages/application/home/prescriptions/prescription-list/ \
        src/app/services/  # only if you modified a service
git commit -m "fix(gestion): repair Médico filter in prescriptions list (G6)"
```

> **If diagnosis points to a backend issue NOT covered by the spec:** stop, do NOT commit, and ping the user. Backend filter bugs need their own scope discussion.

---

### Task 20: Dispensations list — columns FARMACIA + MÉDICO + product fallback (G9-FE, G11-FE)

**Files:**
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.ts`
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.html`
- Modify: `gestion-recetadigital-app/src/app/model/response/dispensation-search-row.ts` (add new fields to interface)

- [ ] **Step 1: Add the new pharmacy fields to the response model**

In `src/app/model/response/dispensation-search-row.ts` (or `dispensationSearchRow.ts`), add to the interface:

```typescript
pharmacyId?: string;
pharmacyName?: string;
pharmacyBusinessName?: string;
```

- [ ] **Step 2: Add the helper method to the component .ts**

Append inside the class:

```typescript
displayDispensationProductName(r: any): string {
    return r?.dispensationProductName || r?.productId || '—';
}

displayDispensationPharmacy(r: any): string {
    return r?.pharmacyName || r?.pharmacyBusinessName || '—';
}
```

- [ ] **Step 3: Add columns to template header**

In `dispensation-list.component.html`, locate the table `<thead>` row. Insert headers between PACIENTE and MEDICAMENTO (or wherever fits):

```html
<th>MÉDICO</th>
<th>FARMACIA</th>
```

- [ ] **Step 4: Add cells to template body**

Inside the `<tr *ngFor>`, insert matching `<td>`s:

```html
<td>{{ r.medicName }} {{ r.medicLastname }}</td>
<td>{{ displayDispensationPharmacy(r) }}</td>
```

- [ ] **Step 5: Replace the medicamento cell with the helper**

Find the existing `<td>` rendering `{{ r.dispensationProductName }}` and replace with:

```html
<td>{{ displayDispensationProductName(r) }}</td>
```

- [ ] **Step 6: Verify ESTADO column renders**

Search the template for `dispensationStatus`. If it's already there, confirm it's visible (not hidden by CSS or accidentally inside an `*ngIf`). If absent, add a column:

```html
<th>ESTADO</th>
<!-- ...inside tr -->
<td>{{ r.dispensationStatus }}</td>
```

- [ ] **Step 7: Build**

```bash
npm run build
```

- [ ] **Step 8: Commit**

```bash
git add src/app/pages/application/home/dispensations/dispensation-list/ \
        src/app/model/response/
git commit -m "feat(gestion): show MÉDICO/FARMACIA columns and productId fallback in dispensations list (G9/G11)"
```

---

### Task 21: Diagnose + fix Médico/Farmacia/Estado filters in Dispensations (G10)

**Files:**
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.{ts,html}`
- Modify: `gestion-recetadigital-app/src/app/services/dispensation.service.ts`

- [ ] **Step 1: Reproduce all three filters**

```bash
npm start
```

Login gestión, go to Dispensaciones. Open dev tools. Test each filter (Médico, Farmacia, Estado) individually.

- [ ] **Step 2: Fix Médico filter**

Same diagnosis tree as Task 19 Step 2. Apply the matching fix.

- [ ] **Step 3: Fix Farmacia filter**

Per the agent's investigation: `onPharmacySelect()` setea `selectedPharmacyId = this.pharmacyId` — wrong reference. Locate the method:

```bash
grep -n "onPharmacySelect\|selectedPharmacyId" /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app/src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.ts
```

Replace the broken handler:

```typescript
onPharmacySelect(event: any): void {
    this.selectedPharmacyId = event?.value ?? null;
    this.refreshTable();  // or this.loadDispensations(...)
}
```

In the service `dispensation.service.ts` `search(opts)` method, ensure `selectedPharmacyId` is forwarded:

```typescript
if (opts.pharmacyId) params = params.set('pharmacyId', opts.pharmacyId);
```

In the component, when calling the service:

```typescript
this.dispensationService.search({ ..., pharmacyId: this.selectedPharmacyId, ... });
```

- [ ] **Step 4: Add Estado filter (it's not declared today)**

In `dispensation-list.component.html`, add a new dropdown next to the existing filters:

```html
<div class="filter-field">
    <label>ESTADO</label>
    <p-dropdown
        [options]="statusOptions"
        [showClear]="true"
        placeholder="Estado"
        (onChange)="onStatusSelect($event)"></p-dropdown>
</div>
```

In `dispensation-list.component.ts`:

```typescript
selectedStatus: string | null = null;

statusOptions = [
    { label: 'Disponible', value: 'AVAILABLE' },
    { label: 'Dispensada',  value: 'DISPENSED' },
    { label: 'Cancelada',  value: 'CANCELLED' },
];

onStatusSelect(event: any): void {
    this.selectedStatus = event?.value ?? null;
    this.refreshTable();
}
```

> Confirm enum values during reproduction — capture an existing dispensation's `dispensationStatus` from the table response and use those exact strings. If the backend uses different values (e.g. lowercase, Spanish), update `statusOptions` accordingly.

In the service call inside the component:

```typescript
this.dispensationService.search({ ..., status: this.selectedStatus, ... });
```

In `dispensation.service.ts`:

```typescript
if (opts.status) params = params.set('status', opts.status);
```

- [ ] **Step 5: Re-test all three filters in browser**

Each filter must reduce the table appropriately. Combine them (e.g., Médico + Estado=DISPENSED) and verify the conjunction works.

- [ ] **Step 6: Stop dev server + commit**

```bash
git add src/app/pages/application/home/dispensations/dispensation-list/ \
        src/app/services/dispensation.service.ts
git commit -m "fix(gestion): repair Médico/Farmacia filters and add Estado filter in dispensations (G10)"
```

---

### Task 22: gestion — final build verification

- [ ] **Step 1: Build with `preprod`**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app
npm run build -- --configuration=preprod
```
Expected: success.

- [ ] **Step 2: Confirm 7 commits**

```bash
git log --oneline -n 10
```
Expected: 7 new commits (G1, G2, G3, G5+G7, G6, G9+G11, G10).

---

## Phase 5 — Build, push, deploy, smoke

### Task 23: Pre-deploy validation

- [ ] **Step 1: Confirm all 4 repos are clean**

```bash
for repo in recetalia-api-rest medics-recetalia-app farmacias-recetalia-app gestion-recetadigital-app; do
    echo "=== $repo ==="
    git -C /Users/pablo/iwtg/recetalia-workspace/$repo status -s
    git -C /Users/pablo/iwtg/recetalia-workspace/$repo log --oneline -n 5
done
```
Expected: every repo shows working tree clean and 3-7 new commits as appropriate.

- [ ] **Step 2: Confirm registry credentials and SSH key**

```bash
docker login registrypre.recetadigital.uy
ssh -o BatchMode=yes -o ConnectTimeout=5 root@138.197.150.98 'echo connected'
```
Expected: docker login succeeds; SSH echoes `connected`.

If SSH prompts for password (BatchMode failed), abort and ask user how to provide the key.

---

### Task 24: Build + push images

- [ ] **Step 1: Run the build-and-push script**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/deploy-recetalia
./scripts/build-and-push.sh
```

Watch the output. If a build fails, **stop** and re-investigate the failing project.

- [ ] **Step 2: Verify the registry catalog**

```bash
curl -u "$REGISTRY_USER:$REGISTRY_PASSWORD" https://registrypre.recetadigital.uy/v2/_catalog
```
Expected: JSON with 7 repositories listed.

(`$REGISTRY_USER` and `$REGISTRY_PASSWORD` are read from your local `.env` file or shell — if they aren't exported, prepend `set -a; source ./.env; set +a`.)

---

### Task 25: Deploy to pre-prod

- [ ] **Step 1: Run the deploy script**

```bash
./scripts/deploy.sh root@138.197.150.98 /opt/recetalia
```

Expected: rsync of compose succeeds; remote `docker compose pull` and `up -d` complete without error.

- [ ] **Step 2: Verify all 8 services running on the server**

```bash
ssh root@138.197.150.98 'cd /opt/recetalia && docker compose ps'
```
Expected: 8 services (registry, nginx, 3 APIs, 4 frontends) in `running`/`healthy` state.

- [ ] **Step 3: Tail logs of the 3 APIs to confirm clean startup**

```bash
ssh root@138.197.150.98 'cd /opt/recetalia && docker compose logs --tail=50 recetalia-api-rest security-api-recetalia transversal-recetalia-api'
```
Look for: `Started <App>Application` lines, no stack traces, no DB connection errors.

---

### Task 26: Smoke tests

- [ ] **Step 1: Auth flow (smoke #1)**

Login through each frontend in the browser:
- `https://medicospre.recetadigital.uy`
- `https://farmaciaspre.recetadigital.uy`
- `https://gestionpre.recetadigital.uy`

Expected: each app loads, login succeeds (JWT in localStorage). Screenshot or note any error.

- [ ] **Step 2: Sidebar smoke (smoke #2 — covers M5/M6, F1/F2)**

In medics and farmacias post-login:
- Sidebar **expanded** by default.
- Header/sidebar shows the user's full name.

- [ ] **Step 3: Initial-load smoke (smoke #3 — covers M3, F3, G1, G3)**

- medics > Prescripciones — list populates without manual action.
- farmacias > Dispensaciones — list populates.
- gestión > Farmacias — list populates.
- gestión > Pacientes > click any patient — modal opens and prescriptions load.

- [ ] **Step 4: Date range smoke (smoke #4 — covers G4, G8)**

In gestión > Prescripciones, set rango de fecha to **2026-03-26 → 2026-04-24**. Expected: rows appear for dates between (specifically the previously-missing 2026-03-26 to 2026-04-23 range).

Repeat in gestión > Dispensaciones.

- [ ] **Step 5: Columns + filters smoke (smoke #5 — covers G5, G6, G9-FE, G10)**

- gestión > Prescripciones: column **MÉDICO** visible with values; selecting a Médico in the filter reduces the table.
- gestión > Dispensaciones: columns **MÉDICO**, **FARMACIA**, **ESTADO** visible with values; each of the 3 filters reduces the table.

- [ ] **Step 6: Fallback smoke (smoke #6 — covers G7, G11)**

- gestión > Prescripciones: rows whose product was previously empty now show either the product name OR a `productId` (UUID-shape) as fallback.
- gestión > Dispensaciones: same.
- API logs: `ssh root@138.197.150.98 'cd /opt/recetalia && docker compose logs recetalia-api-rest | grep WARN | grep DNMA'` — confirm there are WARN entries with `productId=...`.

- [ ] **Step 7: Pacientes order smoke (smoke #7 — covers G2)**

In gestión > Pacientes, the topmost row is the most recent CREACIÓN date.

- [ ] **Step 8: F6 + M1/M2 smoke (smoke #8 — covers F6, M1, M2)**

- farmacias > Buscar Prescripción: input a code, dispensar; after success the input is empty.
- medics > Crear Prescripción > buscar medicamento modal: no Horas/Días dropdowns, only fixed text labels; Crónico checkbox has visible left margin.

- [ ] **Step 9: Regression smoke**

`transversal-recetalia-api` not publicly accessible:

```bash
curl -o /dev/null -w "%{http_code}\n" https://apipre.recetadigital.uy/transversal-recetalia-api/api/email/send
```
Expected: 404 (still not exposed by nginx).

---

### Task 27: Close the cycle

- [ ] **Step 1: Update `TODO.md` at workspace root**

Move all 18 ítems and the "G4/G8 timezone bug" entry from open buckets to "✅ Verificado / cerrado" section, with date 2026-04-28 and a one-line note.

```bash
# Manual edit of /Users/pablo/iwtg/recetalia-workspace/TODO.md
```

- [ ] **Step 2: Update Phase 5/6/7 status in the deploy plan**

Edit `/Users/pablo/iwtg/recetalia-workspace/deploy-recetalia/doc/plans/single-server-deploy.md` to add a "Fase 8 — Fixes Testeo DEV & PRE (2026-04-28)" with `[x]` boxes referencing this plan.

- [ ] **Step 3: Final summary to user**

Report which smoke tests passed, any deltas observed (e.g., a smoke that revealed new issues), and the list of commits per repo for traceability.

---

## Self-review notes

This plan has been self-reviewed against `2026-04-28-fixes-testeo-dev-pre-design.md`. All 18 spec ítems are covered:

- **M1, M2** — Task 9.
- **M3** — Task 7.
- **M5, M6** — Task 8.
- **F1, F2** — Task 12.
- **F3** — Task 11.
- **F6** — Task 13.
- **G1** — Task 15.
- **G2** — Task 16.
- **G3** — Task 17.
- **G4** — Task 1.
- **G5, G7-FE** — Task 18.
- **G6** — Task 19.
- **G7-BE, G11-BE** — Task 3.
- **G8** — Task 2.
- **G9-BE** — Tasks 4, 5.
- **G9-FE, G11-FE** — Task 20.
- **G10 (FE)** — Task 21.
- **G10-BE (filtros pharmacyId/status en endpoint)** — Task 5.

Build/push/deploy/smoke covered by Tasks 23-26. Closure by Task 27.

The plan acknowledges and contains the discovery work needed for shell components, modals, and runtime diagnostics — those are scoped within their tasks (not deferred TBDs).
