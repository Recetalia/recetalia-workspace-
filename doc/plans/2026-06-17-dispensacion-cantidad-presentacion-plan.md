# Cantidad de cajas + presentación dispensada — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mostrar la cantidad de cajas y la presentación dispensada en el modal y la tabla de Dispensaciones, y en Buscar Prescripción para recetas ya dispensadas.

**Architecture:** El dato ya está persistido (`dispensation.qty`, `dispensation.productId`). Parte A es solo frontend (el `dispensationQty` ya viaja en la respuesta). Parte B enriquece la respuesta del search por código con `dispensedQty` + `dispensedPresentation` (AMPP resuelto contra tabla `ampp`, mismo patrón ya usado) y quita el filtro que excluía recetas totalmente dispensadas.

**Tech Stack:** Angular 18 NgModule (farmacias-recetalia-app), Spring Boot 3.3 / Java 21 (recetalia-api-rest).

**Spec:** [2026-06-17-dispensacion-cantidad-presentacion-design.md](2026-06-17-dispensacion-cantidad-presentacion-design.md)

**Regla de flujo:** NO mergear hasta OK de Pablo. Branch `fix/ajustes-farmacias-2026-06-2` (ya existe en farmacias; crear en api-rest).

**Nota de testing:** la lógica de Parte B vive en `PrescriptionServiceImpl`, un servicio con muchas dependencias `@Autowired` (sin tests unitarios en el repo). Igual que el fix previo de resolución de AMPP, se verifica por **integración contra PRE** (API + visual), no por unit test. Las partes de frontend son template puro: se verifican por build + visual.

---

### Task 1: Branch de trabajo en api-rest

(`fix/ajustes-farmacias-2026-06-2` ya existe en farmacias-recetalia-app con el fix del layout-shift.)

- [ ] **Step 1: Crear branch desde 2.x.y**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
git fetch -q origin 2.x.y
git checkout 2.x.y && git pull -q origin 2.x.y
git checkout -b fix/ajustes-farmacias-2026-06-2
```

Expected: branch creada, working tree limpio.

---

### Task 2: Parte A — Cantidad de cajas en el modal de Dispensaciones (frontend)

**Files:**
- Modify: `farmacias-recetalia-app/src/app/pages/application/home/dispensations/dispensations-info/dispensations-info.component.html`

- [ ] **Step 1: Agregar la línea de cantidad en la sección MEDICAMENTO**

Reemplazar el bloque actual:

```html
    <div class="label">MEDICAMENTO</div>
    <div class="value">
      <div>{{ detail.dispensationProductName }}</div>
      <div class="muted" *ngIf="detail.dispensationSubstitute">
        Sustitución: {{ ( detail.dispensationSubstitute == "N" ? 'NO': 'SI') }}
      </div>
    </div>
```

por:

```html
    <div class="label">MEDICAMENTO</div>
    <div class="value">
      <div>{{ detail.dispensationProductName }}</div>
      <div class="muted" *ngIf="detail.dispensationQty != null">
        Cantidad: {{ detail.dispensationQty }} {{ detail.dispensationQty === 1 ? 'caja' : 'cajas' }}
      </div>
      <div class="muted" *ngIf="detail.dispensationSubstitute">
        Sustitución: {{ ( detail.dispensationSubstitute == "N" ? 'NO': 'SI') }}
      </div>
    </div>
```

(`dispensationQty` ya existe en el modelo `DispensationSearchRow` y en `detail`.)

- [ ] **Step 2: Build**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/farmacias-recetalia-app
npm run build
```

Expected: "Application bundle generation complete" (los warnings NG8107 son preexistentes).

- [ ] **Step 3: Commit**

```bash
git add src/app/pages/application/home/dispensations/dispensations-info/dispensations-info.component.html
git commit -m "feat(dispensaciones): mostrar cantidad de cajas en el modal de detalle"
```

---

### Task 3: Parte A — Columna "Cantidad" en la tabla de Dispensaciones (frontend)

**Files:**
- Modify: `farmacias-recetalia-app/src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.html`

- [ ] **Step 1: Agregar el header de la columna**

Reemplazar:

```html
      <th>MEDICAMENTO</th>
      <th pSortableColumn="dispensationCreatedAt">Fecha disp. <p-sortIcon field="dispensationCreatedAt"></p-sortIcon>
```

por:

```html
      <th>MEDICAMENTO</th>
      <th>Cantidad</th>
      <th pSortableColumn="dispensationCreatedAt">Fecha disp. <p-sortIcon field="dispensationCreatedAt"></p-sortIcon>
```

- [ ] **Step 2: Agregar la celda en el body**

Reemplazar:

```html
      <td>{{ r.dispensationProductName }}</td>
      <td>{{ r.dispensationCreatedAt | date:'yyyy-MM-dd HH:mm' }} <br>
```

por:

```html
      <td>{{ r.dispensationProductName }}</td>
      <td>{{ r.dispensationQty }} {{ r.dispensationQty === 1 ? 'caja' : 'cajas' }}</td>
      <td>{{ r.dispensationCreatedAt | date:'yyyy-MM-dd HH:mm' }} <br>
```

- [ ] **Step 3: Build**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/farmacias-recetalia-app && npm run build
```

Expected: bundle generation complete.

- [ ] **Step 4: Commit**

```bash
git add src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.html
git commit -m "feat(dispensaciones): columna Cantidad (cajas) en la tabla"
```

---

### Task 4: Parte B — Campos `dispensedQty` / `dispensedPresentation` en PrescriptionResponse (backend)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/response/PrescriptionResponse.java`

- [ ] **Step 1: Agregar los dos campos opcionales**

Después del campo `private String condvtaId;` (última propiedad de la clase), agregar:

```java

  @Schema(description = "Boxes dispensed (from dispensation.qty); null if not dispensed", example = "3")
  private Integer dispensedQty;

  @Schema(description = "Dispensed AMPP presentation name; null if not dispensed")
  private String dispensedPresentation;
```

(Es `@Data` de Lombok → getters/setters generados. Campos nuevos opcionales, no rompen otros consumidores.)

- [ ] **Step 2: Compilar**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew compileJava -q
```

Expected: compila (solo warnings preexistentes de MapStruct).

- [ ] **Step 3: Commit**

```bash
git add src/main/java/com/recetalia/api/application/dto/response/PrescriptionResponse.java
git commit -m "feat(prescription): campos dispensedQty/dispensedPresentation en PrescriptionResponse"
```

---

### Task 5: Parte B — Finder batch de dispensaciones por prescripción (backend)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java`

- [ ] **Step 1: Agregar el método de búsqueda en lote**

Junto a `findByPrescription_IdAndDeletedAtIsNull`, agregar:

```java
    /**
     * Dispensaciones activas (no borradas) de un conjunto de prescripciones.
     * Para enriquecer la búsqueda por código con lo dispensado.
     */
    List<Dispensation> findByPrescription_IdInAndDeletedAtIsNull(List<String> prescriptionIds);
```

Verificar que `java.util.List` y `Dispensation` ya estén importados (lo están: el repo ya usa `List<Dispensation>`).

- [ ] **Step 2: Compilar**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew compileJava -q
```

Expected: compila.

- [ ] **Step 3: Commit**

```bash
git add src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java
git commit -m "feat(dispensation): finder batch por prescriptionId para enriquecer search"
```

---

### Task 6: Parte B — Quitar filtro + enriquecer con dispensación en el search (backend)

**Files:**
- Modify: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/PrescriptionServiceImpl.java`

- [ ] **Step 1: Inyectar `DispensationRepository`**

Junto a los otros `@Autowired` (cerca de `dnmaDatabaseServiceImpl`), agregar:

```java
  @Autowired
  private com.recetalia.api.application.domain.repository.DispensationRepository dispensationRepository;
```

- [ ] **Step 2: Quitar el filtro de grupo y llamar al enriquecimiento de dispensación**

Reemplazar el cuerpo de `searchAvailablePrescriptionsByCodePrefix` (desde el `List<Prescription> prescriptions = ...` hasta el `return ...;`) por:

```java
    List<Prescription> prescriptions = prescriptionRepository.findPrescriptionsByCodePrefix(codePrefix);

    // Devolver TODAS las prescripciones del código (incl. totalmente dispensadas), para
    // poder mostrar lo entregado. (Antes se filtraban los grupos sin AVAILABLE/CANCELLED.)
    List<PrescriptionResponse> responses = enrichPrescriptionsWithAmpDetails(prescriptions);
    enrichWithDispensationInfo(responses);
    return responses;
```

Esto deja sin uso a `extractGroupKey` SI no se usa en otro lado — verificar con `grep -n "extractGroupKey" PrescriptionServiceImpl.java`; si solo lo usaba este método, dejarlo (no molesta) o borrarlo. No borrar si tiene otros usos.

- [ ] **Step 3: Agregar el método privado `enrichWithDispensationInfo`**

Debajo de `enrichPrescriptionsWithAmpDetails` (después de su `}` de cierre, ~línea 334):

```java
  /**
   * Para cada PrescriptionResponse que tenga dispensación activa, completa
   * dispensedQty (cajas) y dispensedPresentation (nombre del AMPP dispensado,
   * resuelto contra la tabla ampp). Las no dispensadas quedan en null.
   */
  private void enrichWithDispensationInfo(List<PrescriptionResponse> responses) {
    if (responses == null || responses.isEmpty()) { return; }

    List<String> prescriptionIds = responses.stream()
            .map(PrescriptionResponse::getId)
            .filter(java.util.Objects::nonNull)
            .collect(Collectors.toList());
    if (prescriptionIds.isEmpty()) { return; }

    List<com.recetalia.api.application.domain.model.entities.Dispensation> dispensations =
            dispensationRepository.findByPrescription_IdInAndDeletedAtIsNull(prescriptionIds);
    if (dispensations.isEmpty()) { return; }

    // productId dispensado = AMPP id → resolver descripción contra tabla ampp (en lote)
    List<String> amppIds = dispensations.stream()
            .map(com.recetalia.api.application.domain.model.entities.Dispensation::getProductId)
            .filter(java.util.Objects::nonNull)
            .distinct()
            .collect(Collectors.toList());
    Map<String, String> amppNameById = amppIds.isEmpty() ? new HashMap<>() :
            dnmaDatabaseServiceImpl.fetchAmppDetails(amppIds).stream()
                    .filter(m -> m.get("AMPP_Id") != null)
                    .collect(Collectors.toMap(m -> m.get("AMPP_Id"), m -> m.get("AMPP_DSC"), (a, b) -> a));

    Map<String, com.recetalia.api.application.domain.model.entities.Dispensation> byPrescriptionId =
            dispensations.stream()
                    .filter(d -> d.getPrescription() != null && d.getPrescription().getId() != null)
                    .collect(Collectors.toMap(d -> d.getPrescription().getId(), d -> d, (a, b) -> a));

    for (PrescriptionResponse r : responses) {
      com.recetalia.api.application.domain.model.entities.Dispensation d = byPrescriptionId.get(r.getId());
      if (d != null) {
        r.setDispensedQty(d.getQty());
        r.setDispensedPresentation(amppNameById.get(d.getProductId()));
      }
    }
  }
```

(`HashMap`, `Map`, `Collectors`, `List` ya están importados en el archivo.)

- [ ] **Step 4: Build completo**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew build -x test
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/impl/PrescriptionServiceImpl.java
git commit -m "feat(prescription): search por código incluye dispensadas + enriquece qty/presentación"
```

---

### Task 7: Parte B — Mostrar lo dispensado en Buscar Prescripción (frontend)

**Files:**
- Modify: `farmacias-recetalia-app/src/app/model/response/prescription-response.ts`
- Modify: `farmacias-recetalia-app/src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.ts`
- Modify: `farmacias-recetalia-app/src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.html`

- [ ] **Step 1: Agregar los campos al modelo**

En `prescription-response.ts`, dentro de la interfaz, agregar:

```typescript
    dispensedQty?: number | null;
    dispensedPresentation?: string | null;
```

- [ ] **Step 2: Helper `isGroupFullyDispensed` en el componente**

En `prescription-search.component.ts`, debajo de `isGroupChronic(groupKey)`:

```typescript
  isGroupFullyDispensed(groupKey: string): boolean {
    const list = this.groupedPrescriptions[groupKey]?.prescriptions || [];
    return list.length > 0 && list.every((p: any) => p.isDispensed);
  }
```

- [ ] **Step 3: Template — listar lo dispensado y ocultar el form si está todo dispensado**

En `prescription-search.component.html`, justo DESPUÉS del párrafo de Administración y su `<hr />` (la línea `<hr />` que está antes de `<div *ngIf="!groupedPrescriptions[groupKey].sustituteSelect">`), insertar el bloque de dispensados:

```html
                <!-- Lo ya dispensado de este grupo -->
                <ng-container *ngFor="let p of groupedPrescriptions[groupKey].prescriptions; let i = index">
                  <div class="alert alert-success py-2 mb-2"
                       *ngIf="$any(p).isDispensed && $any(p).dispensedPresentation">
                    <strong>Dispensado{{ isGroupChronic(groupKey) ? ' (mes ' + (i + 1) + ')' : '' }}:</strong>
                    {{ $any(p).dispensedPresentation }}
                    <span *ngIf="$any(p).dispensedQty != null">
                      — {{ $any(p).dispensedQty }} {{ $any(p).dispensedQty === 1 ? 'caja' : 'cajas' }}
                    </span>
                  </div>
                </ng-container>
```

Luego, envolver TODO el formulario de dispensación (desde el `<div *ngIf="!groupedPrescriptions[groupKey].sustituteSelect">` hasta el `<div class="card-footer ...">` con el botón Dispensar, inclusive) en un contenedor que solo se muestre si el grupo NO está totalmente dispensado. Es decir, agregar la condición de grupo a las secciones existentes:

  - Cambiar `<div *ngIf="!groupedPrescriptions[groupKey].sustituteSelect">` (bloque presentación normal) por
    `<div *ngIf="!groupedPrescriptions[groupKey].sustituteSelect && !isGroupFullyDispensed(groupKey)">`.
  - Cambiar el `<div class="form-check mb-2">` del checkbox "Entregar sustituto": envolverlo en
    `<ng-container *ngIf="!isGroupFullyDispensed(groupKey)"> ... </ng-container>` (incluye el checkbox y el bloque sustituto `*ngIf="groupedPrescriptions[groupKey].sustituteSelect"`).
  - Cambiar el `<div class="card-footer text-center bg-white">` (botón Dispensar) por
    `<div class="card-footer text-center bg-white" *ngIf="!isGroupFullyDispensed(groupKey)">`.

Resultado: si el grupo está totalmente dispensado se ve solo la(s) línea(s) "Dispensado: …"; si hay meses disponibles, se ven las líneas dispensadas + el formulario para los disponibles.

- [ ] **Step 4: Build**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/farmacias-recetalia-app && npm run build
```

Expected: bundle generation complete (sin errores nuevos de strictTemplates; `$any(p)` evita choques de tipo con `isDispensed`).

- [ ] **Step 5: Commit**

```bash
git add src/app/model/response/prescription-response.ts \
        src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.ts \
        src/app/pages/application/home/prescriptions/prescription-search/prescription-search.component.html
git commit -m "feat(buscar): mostrar presentación y cajas dispensadas en recetas ya dispensadas"
```

---

### Task 8: Sync de docs

**Files:**
- Modify: `farmacias-recetalia-app/doc/specs/api-contract.md` y `recetalia-api-rest/doc/specs/api-contract.md`

- [ ] **Step 1: Documentar** en ambos: que `search-available-Prescriptions-by-code` ahora devuelve TODAS las prescripciones del código (incl. dispensadas) con `dispensedQty` + `dispensedPresentation`; y que la búsqueda de dispensaciones expone `dispensationQty` (ya existía) ahora mostrado en UI. Estilo existente, cambios chicos.

- [ ] **Step 2: Commit en cada repo**

```bash
# en cada repo tocado
git add doc/specs/api-contract.md && git commit -m "docs: cantidad de cajas + presentación dispensada en search y dispensaciones"
```

---

### Task 9: Build, deploy a PRE y verificación (cuando Pablo lo pida — NO mergear)

- [ ] **Step 1: Rebuild + push de las 2 imágenes** (farmacias + api-rest):

```bash
cd /Users/pablo/iwtg/recetalia-workspace
docker buildx build --builder f2a-builder --platform linux/amd64 -t registrypre.recetadigital.uy/recetalia/recetalia-api-rest:latest --push recetalia-api-rest
docker buildx build --builder f2a-builder --platform linux/amd64 --build-arg CONFIGURATION=preprod -t registrypre.recetadigital.uy/recetalia/farmacias-recetalia-app:latest --push farmacias-recetalia-app
```

- [ ] **Step 2: Recrear en el server** `root@138.197.150.98`:

```bash
cd /opt/recetalia/deploy-recetalia && docker compose pull recetalia-api-rest farmacias-recetalia-app && docker compose up -d --force-recreate recetalia-api-rest farmacias-recetalia-app
```

- [ ] **Step 3: Verificar por API** que el search devuelve los campos: login `loginBack` (usuario `api-c3@recetalia.com`/`ApiTest2026`/info `000`); `GET /api/prescriptions/search-available-Prescriptions-by-code?code=DD264F` → la prescripción dispensada trae `dispensedQty` y `dispensedPresentation`.

- [ ] **Step 4: Verificación visual** (Pablo, con hard refresh): modal de Dispensaciones muestra "Cantidad: N cajas"; tabla muestra la columna Cantidad; Buscar Prescripción de un código dispensado muestra "Dispensado: … — N cajas".
