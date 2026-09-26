# Principio activo genérico en la receta — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps usan checkbox (`- [ ]`).

**Goal:** Mostrar el principio activo (sustancia DNMA) en Farmacias > Buscar Prescripción, en el modal de Dispensaciones (farmacias y gestión) y en los exports Excel/PDF, derivándolo de DNMA on-read.

**Architecture:** Backend (api-rest) resuelve la sustancia por `productId` vía DNMA (`amp/ampp/vmp → vmp_sustancia → sustancia`, `GROUP_CONCAT` para combos) y la expone en `PrescriptionResponse.substanceName` y `DispensationSearchRow.prescriptionSubstanceName`. Frontends solo la muestran. Sin tocar base ni alta de recetas.

**Tech Stack:** Spring Boot 3.3/Java 21 (api-rest, JDBC crudo a DNMA), Angular 18.2 (farmacias, gestión).

**Spec:** [2026-06-17-principio-activo-en-receta-design.md](2026-06-17-principio-activo-en-receta-design.md)

**Branches (existentes, NO mergear):** api-rest + farmacias → `fix/ajustes-farmacias-2026-06-2`; gestión → `fix/ajustes-gestion-2026-06`.

**Testing:** la lógica vive en servicios con muchas dependencias; se verifica por integración en PRE (API + visual), como los fixes previos de resolución DNMA. Frontend: build + visual.

---

### Task 1: Confirmar branches

- [ ] **Step 1:** Verificar que los repos están en su branch:

```bash
git -C /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest branch --show-current   # fix/ajustes-farmacias-2026-06-2
git -C /Users/pablo/iwtg/recetalia-workspace/farmacias-recetalia-app branch --show-current # fix/ajustes-farmacias-2026-06-2
git -C /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app branch --show-current # fix/ajustes-gestion-2026-06
```

Si alguno no está en su branch, hacer `git checkout <branch>`.

---

### Task 2: Helpers DNMA de sustancia (backend)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/DnmaDatabaseService.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/DnmaDatabaseServiceImpl.java`

- [ ] **Step 1: Declarar los 3 métodos en la interfaz**

En `DnmaDatabaseService`, agregar:

```java
  public Map<String, String> fetchSubstancesByAmpIds(List<String> ampIds);
  public Map<String, String> fetchSubstancesByAmppIds(List<String> amppIds);
  public Map<String, String> fetchSubstancesByVmpIds(List<String> vmpIds);
```

- [ ] **Step 2: Implementar en `DnmaDatabaseServiceImpl`** (mismo patrón JDBC + `dnmaDataSource` que `fetchAmpDetails`)

Agregar al final de la clase, antes del `}` de cierre:

```java
    @Override
    public Map<String, String> fetchSubstancesByAmpIds(List<String> ampIds) {
        if (ampIds == null || ampIds.isEmpty()) { return new HashMap<>(); }
        String idList = ampIds.stream().map(id -> "'" + id + "'").collect(Collectors.joining(","));
        String query = "SELECT a.AMP_Id AS id, GROUP_CONCAT(DISTINCT s.SUSTANCIA_DSC SEPARATOR ' + ') AS substanceName "
                + "FROM amp a "
                + "LEFT JOIN vmp v ON a.VMP_Id = v.VMP_Id "
                + "LEFT JOIN vmp_sustancia vs ON vs.VMP_Id = v.VMP_Id "
                + "LEFT JOIN sustancia s ON s.SUSTANCIA_ID = vs.SUSTANCIA_Id "
                + "WHERE a.AMP_Id IN (" + idList + ") GROUP BY a.AMP_Id";
        return runSubstanceQuery(query);
    }

    @Override
    public Map<String, String> fetchSubstancesByAmppIds(List<String> amppIds) {
        if (amppIds == null || amppIds.isEmpty()) { return new HashMap<>(); }
        String idList = amppIds.stream().map(id -> "'" + id + "'").collect(Collectors.joining(","));
        String query = "SELECT ap.AMPP_Id AS id, GROUP_CONCAT(DISTINCT s.SUSTANCIA_DSC SEPARATOR ' + ') AS substanceName "
                + "FROM ampp ap "
                + "LEFT JOIN amp a ON a.AMP_Id = ap.AMP_Id "
                + "LEFT JOIN vmp v ON a.VMP_Id = v.VMP_Id "
                + "LEFT JOIN vmp_sustancia vs ON vs.VMP_Id = v.VMP_Id "
                + "LEFT JOIN sustancia s ON s.SUSTANCIA_ID = vs.SUSTANCIA_Id "
                + "WHERE ap.AMPP_Id IN (" + idList + ") GROUP BY ap.AMPP_Id";
        return runSubstanceQuery(query);
    }

    @Override
    public Map<String, String> fetchSubstancesByVmpIds(List<String> vmpIds) {
        if (vmpIds == null || vmpIds.isEmpty()) { return new HashMap<>(); }
        String idList = vmpIds.stream().map(id -> "'" + id + "'").collect(Collectors.joining(","));
        String query = "SELECT v.VMP_Id AS id, GROUP_CONCAT(DISTINCT s.SUSTANCIA_DSC SEPARATOR ' + ') AS substanceName "
                + "FROM vmp v "
                + "LEFT JOIN vmp_sustancia vs ON vs.VMP_Id = v.VMP_Id "
                + "LEFT JOIN sustancia s ON s.SUSTANCIA_ID = vs.SUSTANCIA_Id "
                + "WHERE v.VMP_Id IN (" + idList + ") GROUP BY v.VMP_Id";
        return runSubstanceQuery(query);
    }

    /** Ejecuta una query (id, substanceName) y devuelve el mapa id→sustancia. Null-safe ante error. */
    private Map<String, String> runSubstanceQuery(String query) {
        Map<String, String> result = new HashMap<>();
        try (Connection connection = dnmaDataSource.getConnection();
             Statement statement = connection.createStatement();
             ResultSet rs = statement.executeQuery(query)) {
            while (rs.next()) {
                String id = rs.getString("id");
                if (id != null) { result.put(id, rs.getString("substanceName")); }
            }
        } catch (Exception e) {
            System.err.println("DnmaDatabaseService.runSubstanceQuery error: " + e.getMessage());
        }
        return result;
    }
```

(`Connection`, `Statement`, `ResultSet`, `HashMap`, `Map`, `List`, `Collectors` ya están importados en el archivo.)

- [ ] **Step 3: Compilar**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew compileJava -q
```

Expected: compila (solo warnings preexistentes).

- [ ] **Step 4: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/DnmaDatabaseService.java \
        src/main/java/com/recetalia/api/application/service/impl/DnmaDatabaseServiceImpl.java
git commit -m "feat(dnma): helpers de sustancia (principio activo) por AMP/AMPP/VMP"
```

---

### Task 3: Exponer `substanceName` en PrescriptionResponse + enrich (backend)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/response/PrescriptionResponse.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/PrescriptionServiceImpl.java`

- [ ] **Step 1: Campo en el DTO**

En `PrescriptionResponse.java`, después de `private String dispensedPresentation;` (agregado en el batch anterior), agregar:

```java

  @Schema(description = "Generic active ingredient (DNMA substance), derived on read")
  private String substanceName;
```

- [ ] **Step 2: Poblar en `enrichPrescriptionsWithAmpDetails`**

En `PrescriptionServiceImpl.enrichPrescriptionsWithAmpDetails`, después de calcular `ampDetailsMap` y `vmpDetailsMap` (las líneas con `fetchAmpDetails`/`fetchVmpDetails`), agregar la resolución de sustancia en lote:

```java
    Map<String, String> ampSubstanceById = ampIds.isEmpty() ? new HashMap<>() : dnmaDatabaseServiceImpl.fetchSubstancesByAmpIds(ampIds);
    Map<String, String> vmpSubstanceById = vmpIds.isEmpty() ? new HashMap<>() : dnmaDatabaseServiceImpl.fetchSubstancesByVmpIds(vmpIds);
```

Y dentro del `.map(prescription -> { ... })`, en la rama VMP agregar tras `response.setCondvtaId(...)`:

```java
                  response.setSubstanceName(vmpSubstanceById.get(prescription.getProductId()));
```

y en la rama else (AMP) tras `response.setRutLaboratory(...)`:

```java
                response.setSubstanceName(ampSubstanceById.get(prescription.getProductId()));
```

- [ ] **Step 3: Build**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew build -x test
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
git add src/main/java/com/recetalia/api/application/dto/response/PrescriptionResponse.java \
        src/main/java/com/recetalia/api/application/service/impl/PrescriptionServiceImpl.java
git commit -m "feat(prescription): exponer substanceName (principio activo) derivado de DNMA"
```

---

### Task 4: Exponer `prescriptionSubstanceName` en dispensaciones (backend)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/response/DispensationSearchRow.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/response/EnrichedDispensationRow.java`
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/DispensationServiceImpl.java`

- [ ] **Step 1: Getter en la projection**

En `DispensationSearchRow.java`, junto a `getDispensationProductName()` (que también es enriquecido sin columna nativa), agregar:

```java
  String getPrescriptionSubstanceName();
```

(Las filas nativas devuelven null para este getter, igual que `getDispensationProductName`; lo provee el wrapper enriquecido.)

- [ ] **Step 2: Soportarlo en `EnrichedDispensationRow`**

Cambiar el constructor para recibir también la sustancia y overridear el getter.

Reemplazar:

```java
  private final DispensationSearchRow delegate;
  private final String productName;

  public EnrichedDispensationRow(DispensationSearchRow delegate, String productName) {
    this.delegate = delegate;
    this.productName = productName;
  }
```

por:

```java
  private final DispensationSearchRow delegate;
  private final String productName;
  private final String prescriptionSubstanceName;

  public EnrichedDispensationRow(DispensationSearchRow delegate, String productName, String prescriptionSubstanceName) {
    this.delegate = delegate;
    this.productName = productName;
    this.prescriptionSubstanceName = prescriptionSubstanceName;
  }
```

Y junto a `getDispensationProductName()`, agregar:

```java
  @Override public String getPrescriptionSubstanceName() { return prescriptionSubstanceName; }
```

- [ ] **Step 3: Resolver y pasar la sustancia en `DispensationServiceImpl.search()`**

Después de calcular `amppNameById` y `vmpDetailsMap`, agregar la resolución de sustancia en lote (el productId dispensado es AMPP; para VMP, por vmpId):

```java
    Map<String, String> amppSubstanceById = amppIds.isEmpty() ? new HashMap<>() :
        this.dnmaDatabaseServiceImpl.fetchSubstancesByAmppIds(amppIds);
    Map<String, String> vmpSubstanceById = vmpIds.isEmpty() ? new HashMap<>() :
        this.dnmaDatabaseServiceImpl.fetchSubstancesByVmpIds(vmpIds);
```

Dentro del `.map(row -> { ... })`, calcular la sustancia junto al `name` y pasarla al constructor. Reemplazar el cuerpo del map:

```java
        .map(row -> {
          String name = null;
          String substance = null;
          String productId = row.getDispensationProductId();
          if (productId != null) {
            if ("VMP".equals(row.getDispensationProductType())) {
              Map<String, String> vmp = vmpDetailsMap.get(productId);
              if (vmp != null) name = vmp.get("vmp_dsc");
              substance = vmpSubstanceById.get(productId);
            } else {
              name = amppNameById.get(productId);
              substance = amppSubstanceById.get(productId);
            }
          }
          return new EnrichedDispensationRow(row, name, substance);
        })
```

- [ ] **Step 4: Build**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew build -x test
```

Expected: BUILD SUCCESSFUL (verificá que no quede ninguna llamada vieja `new EnrichedDispensationRow(row, name)` de 2 args — debe ser de 3).

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/recetalia/api/application/dto/response/DispensationSearchRow.java \
        src/main/java/com/recetalia/api/application/dto/response/EnrichedDispensationRow.java \
        src/main/java/com/recetalia/api/application/service/impl/DispensationServiceImpl.java
git commit -m "feat(dispensation): exponer prescriptionSubstanceName (principio activo) derivado de DNMA"
```

---

### Task 5: Display en farmacias (frontend)

**Files:**
- Modify: `farmacias-recetalia-app/src/app/model/response/prescription-response.ts`
- Modify: `farmacias-recetalia-app/src/app/model/response/dispensation-search-row.ts`
- Modify: `farmacias-recetalia-app/src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.html`
- Modify: `farmacias-recetalia-app/src/app/pages/application/home/dispensations/dispensations-info/dispensations-info.component.html`
- Modify: `farmacias-recetalia-app/src/app/services/dispensation-file.service.ts`

- [ ] **Step 1: Modelos**

En `prescription-response.ts` agregar: `substanceName?: string | null;`
En `dispensation-search-row.ts` agregar: `prescriptionSubstanceName?: string | null;`

- [ ] **Step 2: Buscar Prescripción — sustancia bajo el nombre del medicamento**

En `prescription-search.component.html`, en el `card-header` del grupo, debajo de `<h6 class="mb-0">{{ prescription.ampDsc }}</h6>`, agregar:

```html
                <small class="text-secondary d-block" *ngIf="prescription.substanceName">{{ prescription.substanceName }}</small>
```

- [ ] **Step 3: Modal de Dispensaciones — sustancia en la sección PRESCRIPCIÓN**

En `dispensations-info.component.html`, reemplazar el bloque PRESCRIPCIÓN:

```html
    <div class="label">PRESCRIPCIÓN</div>
    <div class="value">
      <div>{{ prescription?.ampDsc }} {{ prescription?.vmpDsc }}</div>
    </div>
```

por:

```html
    <div class="label">PRESCRIPCIÓN</div>
    <div class="value">
      <div>{{ prescription?.ampDsc }} {{ prescription?.vmpDsc }}</div>
      <div class="muted" *ngIf="detail.prescriptionSubstanceName">{{ detail.prescriptionSubstanceName }}</div>
    </div>
```

- [ ] **Step 4: Export Excel — columna "Principio activo"**

En `dispensation-file.service.ts`, en `exportDispensationsToExcel`, agregar `'Principio activo'` al array `header` después de `'Medicamento'`, y `(r as any).prescriptionSubstanceName ?? ''` en el data map en el mismo índice (después del `dispensationProductName`). Ajustar `!cols` con un ancho extra (`{ wch: 30 }`) si existe ese array.

- [ ] **Step 5: Export PDF — línea Principio activo**

En `exportDispensationsToPdf`, después del bloque MEDICAMENTO (`{ text: 'MEDICAMENTO', ... }` + su value), agregar:

```javascript
        { text: 'PRINCIPIO ACTIVO', style: 'label', margin: [0, 6, 0, 0] },
        { text: (r as any).prescriptionSubstanceName ?? '', style: 'value' },
```

- [ ] **Step 6: Build + commit**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/farmacias-recetalia-app && npm run build
git add src/app/model/response/prescription-response.ts \
        src/app/model/response/dispensation-search-row.ts \
        src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.html \
        src/app/pages/application/home/dispensations/dispensations-info/dispensations-info.component.html \
        src/app/services/dispensation-file.service.ts
git commit -m "feat(farmacias): mostrar principio activo en buscar prescripción, dispensaciones y exports"
```

---

### Task 6: Display en gestión (frontend)

**Files:**
- Modify: `gestion-recetadigital-app/src/app/model/response/dispensation-search-row.ts`
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/dispensations/dispensations-info/dispensations-info.component.html`
- Modify: `gestion-recetadigital-app/src/app/services/dispensation-file.service.ts`

- [ ] **Step 1: Modelo**

En `dispensation-search-row.ts` (gestión) agregar: `prescriptionSubstanceName?: string | null;`

- [ ] **Step 2: Modal — sustancia en la sección PRESCRIPCIÓN**

En `dispensations-info.component.html` (gestión), reemplazar el bloque PRESCRIPCIÓN:

```html
  <div class="label">PRESCRIPCIÓN</div>
  <div class="value"><div>{{ prescription?.ampDsc }}</div></div>
```

por (ajustar a la indentación real; ubicar por contenido):

```html
  <div class="label">PRESCRIPCIÓN</div>
  <div class="value">
    <div>{{ prescription?.ampDsc }}</div>
    <div class="muted" *ngIf="detail.prescriptionSubstanceName">{{ detail.prescriptionSubstanceName }}</div>
  </div>
```

- [ ] **Step 3: Export Excel — columna "Principio activo"**

En `dispensation-file.service.ts` (gestión), en el `header` de Excel agregar `'Principio activo'` después de `'Medicamento'`, y `(r as any).prescriptionSubstanceName ?? ''` en el data map en el mismo índice (después del `dispensationProductName`). Agregar un ancho a `!cols` (`{ wch: 30 }`).

- [ ] **Step 4: Export PDF — línea Principio activo**

En el `rows.map(...)` del PDF, después del bloque MEDICAMENTO, agregar:

```javascript
        { text: 'PRINCIPIO ACTIVO', style: 'label', margin: [0, 6, 0, 0] },
        { text: (r as any).prescriptionSubstanceName ?? '', style: 'value' },
```

- [ ] **Step 5: Build + commit**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app && npm run build
git add src/app/model/response/dispensation-search-row.ts \
        src/app/pages/application/home/dispensations/dispensations-info/dispensations-info.component.html \
        src/app/services/dispensation-file.service.ts
git commit -m "feat(gestion): mostrar principio activo en dispensaciones (modal y exports)"
```

---

### Task 7: Sync de docs

- [ ] **Step 1:** En `recetalia-api-rest/doc/specs/api-contract.md`, `farmacias-recetalia-app/doc/specs/api-contract.md` y `gestion-recetadigital-app/doc/specs/api-contract.md`: documentar `substanceName` en `PrescriptionResponse` (search por código) y `prescriptionSubstanceName` en `DispensationSearchRow` (search de dispensaciones), derivados de DNMA. Cambios chicos, estilo existente.

- [ ] **Step 2: Commit por repo** con `docs: principio activo (substanceName) en search y dispensaciones`.

---

### Task 8: Build, deploy a PRE y verificación (cuando Pablo lo pida — NO mergear)

- [ ] **Step 1:** Rebuild + push de las 3 imágenes (api-rest, farmacias, gestión) y recreación en PRE (mismos comandos buildx/compose de siempre).

- [ ] **Step 2: Verificación API (PRE):** login `loginBack`; `GET /api/prescriptions/search-available-Prescriptions-by-code?code=20200B` → `substanceName` = "ketoprofeno"; `GET /api/dispensations/search?pharmacyId=...` → `prescriptionSubstanceName` poblado.

- [ ] **Step 3: Verificación visual (Pablo, hard refresh):** Farmacias Buscar Prescripción (sustancia bajo el nombre), modal de Dispensaciones (farmacias y gestión) con el principio activo, y exports Excel/PDF con la columna/línea.
