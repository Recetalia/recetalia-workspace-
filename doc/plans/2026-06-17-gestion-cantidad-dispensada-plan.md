# Cantidad de cajas en Gestión — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) o superpowers:executing-plans. Steps usan checkbox (`- [ ]`).

**Goal:** Mostrar la cantidad de cajas dispensada en la tabla y el modal de dispensaciones de gestión, y en los exports Excel/PDF. Cubre Gestión > Dispensaciones y Gestión > Farmacias > detalle (reusan el mismo componente).

**Architecture:** Frontend puro en `gestion-recetadigital-app`. El backend ya devuelve `dispensationQty` y el modelo `dispensation-search-row.ts` ya lo tiene; solo falta pintarlo/exportarlo. La presentación (AMPP) ya se muestra, no se toca.

**Tech Stack:** Angular 18.2 NgModule + PrimeNG 17 (tabla/dialog), XLSX (Excel), pdfmake (PDF).

**Spec:** [2026-06-17-gestion-cantidad-dispensada-design.md](2026-06-17-gestion-cantidad-dispensada-design.md)

**Regla de flujo:** NO mergear hasta OK de Pablo.

---

### Task 1: Branch de trabajo en gestión

- [ ] **Step 1: Crear branch desde 2.x.y**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app
git fetch -q origin 2.x.y
git checkout 2.x.y && git pull -q origin 2.x.y
git checkout -b fix/ajustes-gestion-2026-06
```

Expected: branch creada, working tree limpio.

---

### Task 2: Cantidad en tabla + modal de Dispensaciones (frontend)

**Files:**
- Modify: `src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.html`
- Modify: `src/app/pages/application/home/dispensations/dispensations-info/dispensations-info.component.html`

- [ ] **Step 1: Columna "Cantidad" en el header de la tabla**

En `dispensation-list.component.html`, reemplazar:

```html
            <th>MEDICAMENTO</th>
            <th pSortableColumn="dispensationCreatedAt">
```

por:

```html
            <th>MEDICAMENTO</th>
            <th>Cantidad</th>
            <th pSortableColumn="dispensationCreatedAt">
```

- [ ] **Step 2: Celda de cantidad en el body de la tabla**

En el mismo archivo, reemplazar:

```html
            <td>{{ displayDispensationProductName(r) }}</td>
```

por:

```html
            <td>{{ displayDispensationProductName(r) }}</td>
            <td>{{ r.dispensationQty }} {{ r.dispensationQty === 1 ? 'caja' : 'cajas' }}</td>
```

(La celda nueva queda en la misma posición que el header "Cantidad": entre MEDICAMENTO y FECHA DISP.)

- [ ] **Step 3: Línea de cantidad en el modal de detalle**

En `dispensations-info.component.html`, reemplazar:

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

(Si el HTML real difiere levemente en indentación, ubicá el bloque por contenido. La línea de cantidad va ENTRE el nombre del producto y la de Sustitución.)

- [ ] **Step 4: Build**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app
npm run build
```

Expected: "Application bundle generation complete" (los warnings preexistentes se ignoran; no debe haber errores nuevos de template).

- [ ] **Step 5: Commit**

```bash
git add src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.html \
        src/app/pages/application/home/dispensations/dispensations-info/dispensations-info.component.html
git commit -m "feat(gestion-dispensaciones): mostrar cantidad de cajas en tabla y modal"
```

---

### Task 3: Cantidad en exports Excel y PDF (frontend)

**Files:**
- Modify: `src/app/services/dispensation-file.service.ts`

- [ ] **Step 1: Excel — agregar "Cantidad" al header**

Reemplazar:

```javascript
    const header = [
      ['Fecha', 'Prescripcion', 'Paciente', 'Documento', 'Medicamento', 'Estado', 'Dispensado por', 'Tipo de Receta']
    ];
```

por:

```javascript
    const header = [
      ['Fecha', 'Prescripcion', 'Paciente', 'Documento', 'Medicamento', 'Cantidad', 'Estado', 'Dispensado por', 'Tipo de Receta']
    ];
```

- [ ] **Step 2: Excel — agregar la cantidad en el data map**

Reemplazar:

```javascript
      (r as any).dispensationProductName ?? '',
      this.statusText(r.dispensationStatus),
```

por:

```javascript
      (r as any).dispensationProductName ?? '',
      (r as any).dispensationQty ?? '',
      this.statusText(r.dispensationStatus),
```

(Queda alineado: "Cantidad" en el header y `dispensationQty` en data ocupan el mismo índice, justo después de Medicamento.)

- [ ] **Step 3: Excel — ajustar el ancho de columnas**

Reemplazar:

```javascript
    (ws as any)['!cols'] = [
      { wch: 12 }, { wch: 12 }, { wch: 26 }, { wch: 16 }, { wch: 60 }, { wch: 12 }, { wch: 26 }
    ];
```

por:

```javascript
    (ws as any)['!cols'] = [
      { wch: 12 }, { wch: 12 }, { wch: 26 }, { wch: 16 }, { wch: 60 }, { wch: 10 }, { wch: 12 }, { wch: 26 }
    ];
```

(Se agrega el ancho de la columna Cantidad después del de Medicamento.)

- [ ] **Step 4: PDF — agregar el bloque CANTIDAD**

En `exportDispensationsToPdf`, dentro del `rows.map(...)`, reemplazar:

```javascript
        { text: 'MEDICAMENTO', style: 'label', margin: [0, 6, 0, 0] },
        { text: (r as any).dispensationProductName ?? '', style: 'value' },

        { text: 'ADMINISTRACION', style: 'label', margin: [0, 6, 0, 0] },
```

por:

```javascript
        { text: 'MEDICAMENTO', style: 'label', margin: [0, 6, 0, 0] },
        { text: (r as any).dispensationProductName ?? '', style: 'value' },

        { text: 'CANTIDAD', style: 'label', margin: [0, 6, 0, 0] },
        { text: (r as any).dispensationQty != null
            ? ((r as any).dispensationQty + ((r as any).dispensationQty === 1 ? ' caja' : ' cajas'))
            : '', style: 'value' },

        { text: 'ADMINISTRACION', style: 'label', margin: [0, 6, 0, 0] },
```

- [ ] **Step 5: Build**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app
npm run build
```

Expected: bundle generation complete, sin errores nuevos.

- [ ] **Step 6: Commit**

```bash
git add src/app/services/dispensation-file.service.ts
git commit -m "feat(gestion-dispensaciones): cantidad de cajas en exports Excel y PDF"
```

---

### Task 4: Sync de docs

**Files:**
- Modify: `gestion-recetadigital-app/doc/specs/api-contract.md` (si documenta dispensaciones)

- [ ] **Step 1:** Documentar que la pantalla de dispensaciones (y el detalle de farmacia, que la reusa) muestra `dispensationQty` (cajas) en tabla, modal y exports. Cambio chico, estilo existente. Si el doc no menciona dispensaciones, agregar nota mínima coherente.

- [ ] **Step 2: Commit**

```bash
git add doc/specs/api-contract.md && git commit -m "docs: cantidad de cajas en dispensaciones de gestión"
```

---

### Task 5: Build, deploy a PRE y verificación (cuando Pablo lo pida — NO mergear)

- [ ] **Step 1: Rebuild + push de la imagen de gestión:**

```bash
cd /Users/pablo/iwtg/recetalia-workspace
docker buildx build --builder f2a-builder --platform linux/amd64 --build-arg CONFIGURATION=preprod \
  -t registrypre.recetadigital.uy/recetalia/gestion-recetadigital-app:latest --push gestion-recetadigital-app
```

- [ ] **Step 2: Recrear en el server** `root@138.197.150.98`:

```bash
cd /opt/recetalia/deploy-recetalia && docker compose pull gestion-recetadigital-app && docker compose up -d --force-recreate gestion-recetadigital-app
```

- [ ] **Step 3: Verificación visual** (Pablo, con hard refresh) en https://gestionpre.recetadigital.uy:
  - Gestión > Dispensaciones: columna "Cantidad" + "Cantidad: N cajas" en el modal.
  - Gestión > Farmacias > (una farmacia) > Dispensaciones: ídem (mismo componente).
  - Exportar Excel y PDF: la cantidad aparece.
  - Datos de prueba: dispensaciones con qty 3 / 100 / 8 (códigos DD264F-A, 62A4CD-C, 0D1D38-A).
