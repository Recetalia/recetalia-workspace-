# Recetas en papel — Plan 4b: la pantalla

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que la farmacia pueda cargar al sistema una receta emitida en papel desde una pantalla propia, ver lo que cargó, y anular lo que cargó mal.

**Architecture:** Una pantalla nueva en `farmacias-recetalia-app` con dos partes: un listado (copiado del Libro Negro, filtrando por origen) y un formulario de alta. Consume `POST /api/prescriptions/paper` y `.../cancel`, que ya existen y están validados. Del lado del backend falta una sola cosa: poder filtrar el listado por origen.

**Tech Stack:** Angular 18.2 (NgModule), Reactive Forms, Bootstrap 5 + PrimeNG 17. Backend: Java 21 / Spring Boot 3.3.

**Spec:** [2026-07-31-qf-registro-y-libro-negro-papel-design.md](2026-07-31-qf-registro-y-libro-negro-papel-design.md) — Feature 2.
**Backend:** [2026-08-01-recetas-papel-backend-plan.md](2026-08-01-recetas-papel-backend-plan.md), completo y validado en DEV.

---

## Decisiones ya tomadas — no las revisites

| Decisión | Por qué |
|---|---|
| **La pantalla es solo para `ROLE_PHARMACY`** | El backend resuelve la farmacia con `getCurrentPharmacy()`, que busca por email en la tabla `pharmacy`. Un `ROLE_PHARMACY_ADMIN` **no tiene fila ahí** (se vincula por `franchise.adminEmail`) → 404. Que cada farmacia cargue lo suyo es además lo natural: es quien tiene el papel en la mano |
| **Se agrega `origin` a `/api/dispensations/search`** | Ese endpoint no permite filtrar por origen, y filtrar en el cliente rompería la paginación server-side |
| **Ítem nuevo en el sidebar**, ruta `libro-negro/mantenimiento` | Es lo que dice el diseño. El Libro Negro actual queda intacto |

---

## Contexto imprescindible

**Ramas:** `recetalia-api-rest` sigue en `feat/qf-registro-y-papel` (HEAD `05dc9d2`, 156 tests). `farmacias-recetalia-app` sigue en `feat/qf-lookup-cjp` (HEAD `c55e2a0`), working tree limpio.

**El contrato del backend, textual** (`PaperPrescriptionRequest.java`). Los `*` son obligatorios:

```
patientName*, patientLastname*, patientDocument*{number,type}
medicName*, medicLastname*, medicCjp*          ← "medicCjp", NO "medicCJP"
paperNumber*, paperIssuedAt* (Instant ISO)
productType*, productId*, condvtaId (String), dnmaLaboratoryId (Integer)
dose, doseUnit, doseType
frecuency* (Integer, horas), frecuencyUnit*, duration, durationUnit
qty*, loteNumber* (NotBlank), loteExpireAt, dispensedById*
```

Respuesta: `{prescriptionCode, prescriptionId, dispensationId}` dentro del envelope `ApiResponse`.
Anulación: `POST /api/prescriptions/paper/{id}/cancel`, donde **`{id}` es el `prescriptionId`, no el `dispensationId`**.

**Datos de prueba ya cargados en DEV** (no los borres, sirven para probar): recetas `CA4DB5-A` (Nº `0648345`) y `B001D3-A` (Nº `0999111`), farmacia "Test" (`e9e4ed5e-fc32-4168-9afb-660a09885498`), dispenser `e8480c67-d8e5-43ec-a275-85f0234fe74b`.

**Esta app no tiene tests.** La verificación es en el browser. Build: `npm run build`. `strict` y `strictTemplates` están activos.

---

## Las trampas que encontró el relevamiento

Leelas antes de escribir código. Cada una costó tiempo de encontrar.

**`getCurrentUser()` emite `null` primero.** Sin `filter(u => u != null), take(1)` el componente se rompe. `libro-negro.component.ts:54-56` lo hace bien; copiá ese patrón.

**El `<p-table>` lazy dispara `onLazyLoad` al montarse**, antes de que resuelva el usuario. Por eso `loadDispensations` arranca con un guard `if (!this.effectivePharmacyId) { ...; return; }`. Copialo o la primera carga sale sin farmacia.

**`MedicineListComponent` no es reusable tal cual.** Es un híbrido que hace de buscador *y* de formulario de posología, y cierra el diálogo devolviendo **dos tipos incompatibles** según por dónde salga: un `MedicineResponse` crudo en `onMedicineSelect()` y un `PrescriptionRequest` armado en `submitPrescription()`. Escribí un buscador nuevo y chico que solo emita el `MedicineResponse`, copiando el template de `medicine-list.component.html:8-35` podado.

**La búsqueda actual no tiene debounce**: dispara un HTTP por tecla y no cancela el anterior, así que las respuestas llegan fuera de orden. En el componente nuevo usá `debounceTime(300)` + `switchMap`.

**`condvtaId` cambia de tipo según de dónde salga**: `number` en `MedicineResponse`, `string` en `AmppResponse` y en el request. Convertí explícitamente.

**`AmppResponse` declara `dnmaLaboratoryId` y `laboratorioId`.** El código que dispensa usa **`laboratorioId`**. Usá ese.

**`DialogModule` y `ButtonModule` no están importados en `HomeModule`.** El `p-dialog` de `profile` "funciona" solo porque `CUSTOM_ELEMENTS_SCHEMA` se traga el tag desconocido y el diálogo directamente no renderiza. Si usás `p-dialog`, importalos de verdad.

**El `catchError` de los servicios descarta el mensaje del backend** y devuelve un texto fijo. Acá el backend manda `BusinessRuleException` con mensajes útiles ("Solo se pueden anular recetas cargadas en papel"), así que el servicio nuevo necesita su propio `catchError` que lea `err.error?.answer`.

**No existe ninguna UI de lote ni vencimiento en toda la app** — hoy la dispensación los hardcodea a `'0000'` y `null`. Se construye de cero.

---

### Task 1: Backend — filtrar por origen

**Files:**
- Modify: `recetalia-api-rest/.../domain/repository/DispensationRepository.java`
- Modify: `recetalia-api-rest/.../service/DispensationService.java` + `impl/`
- Modify: `recetalia-api-rest/.../controller/DispensationController.java`

- [ ] **Step 1: El filtro en la query**

En `searchDispensations`, agregá un parámetro `origin` con el idiom que ya usa el resto de los filtros opcionales de esa query:

```sql
      AND ( :origin IS NULL OR pr.origin = :origin )
```

⚠️ **En el `value` Y en el `countQuery`.** Los dos tienen la misma cláusula `WHERE`; si el filtro va solo en uno, la paginación miente: el total no coincide con las filas.

⚠️ Agregá el `@Param("origin")` a la firma y **actualizá el único call site**, `DispensationServiceImpl.search(...)`, más el de `PharmaceuticalDirectorServiceImpl.getGreenDispensations` que delega ahí — que tiene que pasar `null` para seguir viendo las dos.

- [ ] **Step 2: El parámetro en el controller**

`@RequestParam(required = false) String origin` en `GET /api/dispensations/search`, propagado hasta el repositorio.

- [ ] **Step 3: Verificar que no rompiste nada**

`./gradlew build` → los 156 tests verdes.

Y **probá la query contra DEV** antes de seguir, porque el SQL no se valida al compilar: con `origin=PAPER` tienen que salir las 2 recetas de prueba, con `origin=DIGITAL` el resto, y **sin el parámetro tienen que salir todas** — esa última es la que garantiza que no rompiste el Libro Negro ni el listado del QF.

- [ ] **Step 4: Commit**

```
feat(papel): filtro por origen en la busqueda de dispensaciones
```

---

### Task 2: El servicio y los modelos del front

**Files (en `farmacias-recetalia-app`):**
- Modify: `src/app/model/response/dispensation-search-row.ts`
- Create: `src/app/model/request/paper-prescription-request.ts`
- Create: `src/app/model/response/paper-prescription-response.ts`
- Create: `src/app/services/paper-prescription.service.ts`
- Modify: `src/app/services/dispensation.service.ts`

- [ ] **Step 1: Los campos que faltan en el modelo**

`dispensation-search-row.ts` de esta app **no declara** `prescriptionPaperNumber` ni `prescriptionOrigin`, aunque el backend ya los devuelve. El de `qf-recetalia-app` sí: copiá esas dos líneas de `qf-recetalia-app/src/app/model/response/dispensation-search-row.ts`.

- [ ] **Step 2: El request y el response**

Espejo exacto del contrato de arriba. **Cuidado con `medicCjp`**, que no es `medicCJP`.

- [ ] **Step 3: El servicio**

`create(request)` y `cancel(prescriptionId)` contra los dos endpoints, siguiendo el patrón `ApiResponse → map → catchError` del repo, **pero con un `catchError` que propague `err.error?.answer`**: los mensajes del backend son lo que se le muestra al usuario.

- [ ] **Step 4: El parámetro `origin` en `DispensationService.search`**

Agregalo a las opciones que ya acepta ese método, como query param opcional.

- [ ] **Step 5: Build y commit**

---

### Task 3: El buscador de medicamentos

Un componente nuevo, chico, que se abre como modal y emite el medicamento elegido. **No reuses `MedicineListComponent`** — ver las trampas.

**Files:**
- Create: `src/app/pages/application/home/libro-negro/mantenimiento/medicine-picker/medicine-picker.component.{ts,html}`

- [ ] **Step 1: El componente**

- Input de búsqueda con `debounceTime(300)` + `switchMap` sobre `AmpService.getSearchByprodMspLike()`.
- Lista de resultados separando comerciales (`labName != null`) de genéricos, con las clases `back_green` / `back_orange` según `condvtaId` — copiá el template de `medicine-list.component.html:8-35`, podado y con los textos en español (los actuales están en inglés).
- Al elegir un AMP, cargar sus presentaciones con `AmppService.getAmppsByAmpId()` y ofrecer un `p-dropdown` para elegir una.
- Cerrar el diálogo emitiendo **un solo tipo**: `{ productType, productId, condvtaId, dnmaLaboratoryId, doseUnit, doseType, substanceName, displayName }`, ya resuelto según haya AMPP o no.

**El mapeo, que es la parte que importa** (regla tomada de `prescription-search.component.ts:473-496`):

| Campo | Con AMPP elegida | Sin AMPPs |
|---|---|---|
| `productId` | `ampp.id` | `medicine.id` |
| `productType` | `medicine.productType` | `medicine.productType` |
| `condvtaId` | `ampp.condvtaId` (ya string) | `String(medicine.condvtaId)` o `null` |
| `dnmaLaboratoryId` | `ampp.laboratorioId` | `null` |

⚠️ Un AMP puede **no tener** presentaciones — es un caso real y frecuente en el catálogo. Si `getAmppsByAmpId` devuelve vacío, el flujo tiene que seguir con el AMP, no quedarse esperando.

- [ ] **Step 2: Build y commit**

---

### Task 4: La pantalla de mantenimiento

**Files:**
- Create: `src/app/pages/application/home/libro-negro/mantenimiento/mantenimiento.component.{ts,html,scss}`
- Modify: `home-routing.module.ts`, `home.module.ts`, `components/sidebar/sidebar.component.html`

- [ ] **Step 1: El listado**

Copiá `libro-negro.component.ts` como esqueleto —resolución de rol, `p-table` lazy, guard de `effectivePharmacyId`, rango de fechas— y cambiá el filtro: en vez de `condvtaId = 'GREEN'`, `origin = 'PAPER'`.

**Como la pantalla es solo para `ROLE_PHARMACY`**, se puede simplificar: no hace falta el selector de sucursal ni la rama de admin. Si entra un `ROLE_PHARMACY_ADMIN`, mostrale un aviso explicando que la carga se hace desde cada sucursal, en vez de dejarlo con una pantalla que le va a dar 404.

Columnas: Código (con el `Nº` en segunda línea, copiando `qf-recetalia-app/.../green-dispensations-list.component.html:20-25`), Paciente, Médico, Medicamento, Fecha del papel, Estado, y una acción de **Anular**.

Las anuladas tienen que verse **tachadas, no desaparecer**: el estado viene en `dispensationStatus`.

- [ ] **Step 2: El formulario**

Un `p-dialog` (o una sección desplegable) con los seis bloques del diseño, en este orden:

1. **Paciente** — nombre, apellido, tipo + número de documento. Tipos: `UY | AR | PASSPORT | RUT | OTHER`.
2. **Médico** — nombre, apellido, CJP.
3. **Receta** — Nº de talonario, fecha del papel (`p-calendar`).
4. **Medicamento** — botón que abre el buscador de la Task 3; una vez elegido, mostrarlo con el chip de tipo de receta (Verde / Naranja / Blanca) derivado del `condvtaId`. **El tipo no se elige a mano.**
5. **Administración** — dosis + unidad, frecuencia + unidad, duración + unidad. **La frecuencia es obligatoria**: si va NULL el tope de cajas no aplica y la app muestra "1 comprimido cada `[vacío]` horas".
6. **Dispensación** — cantidad, lote, vencimiento del lote, y el dropdown de dispensador. Para el dispensador **reusá `PharmacyDispensersService.getAllPharmacyToken()` y el ítem sentinela `id:'add'` que abre `PharmacyDispenserAddComponent`**, tal como lo hace `prescription-search.component.ts:524-588`.

Al guardar, mostrar **el código Recetalia generado** en la confirmación: es lo que la farmacia necesita anotar en el papel.

- [ ] **Step 3: La anulación**

Botón por fila, con confirmación. Llama a `cancel(prescriptionId)` — ojo, **el id de la receta, no el de la dispensación**. Al volver, refrescar el listado.

⚠️ **Puede fallar por el SMTP.** El backend manda un email al anular y rethrowea si falla, así que si el servidor de correo está mal configurado la anulación no se completa. Mostrá el mensaje del backend tal cual en vez de un "no se pudo anular" genérico.

- [ ] **Step 4: Ruta, módulo y sidebar**

Ruta hija `libro-negro/mantenimiento`. Declarar el componente en `home.module.ts` e importar ahí `DialogModule` y `ButtonModule`, que **no están**. Ítem en el sidebar debajo de "Libro Negro", visible solo para `ROLE_PHARMACY` (el sidebar ya tiene ese patrón de `*ngIf` por rol).

- [ ] **Step 5: Build y commit**

---

### Task 5: El Nº en el Libro Negro que ya existe

- [ ] Agregar la segunda línea con el `Nº` a la columna Código de `libro-negro.component.html`, idéntica a la de la pantalla nueva. Con el modelo ya actualizado en la Task 2, es solo el template.
- [ ] Build y commit.

---

### Task 6: Validación en DEV

- [ ] **Deploy** de `recetalia-api-rest` y `farmacias-recetalia-app` al `.98`. Builds **en serie**; `up -d --no-deps` nombrando los servicios — un `up -d` a secas recrea nginx y rompe PRE.

- [ ] **Que no se rompió nada de lo que ya andaba**, que es el riesgo de haber tocado la query compartida: el Libro Negro sigue listando, el listado de recetas verdes del QF sigue andando, y el Excel de controlados baja bien.

- [ ] **El circuito completo en el browser**: cargar una receta de papel de punta a punta, ver el código generado, que aparezca en el listado nuevo con su Nº, que aparezca también en el Libro Negro, y anularla.

- [ ] **Regresión**: los 5 frontends de PRE en 200, ningún contenedor caído salvo `observatorio-cpa`.

---

## Nota sobre el nivel de detalle

Este plan es deliberadamente más de estructura y decisiones que de código literal, a diferencia de los anteriores. La razón: la pantalla se arma copiando y adaptando cuatro componentes que ya existen, y reproducirlos acá habría sido transcribir código sin poder verificarlo. Cada paso apunta al archivo y las líneas exactas de donde sacar el patrón.

**Lo que el plan sí fija con precisión, porque es donde se rompe:** el contrato del backend, el mapeo del medicamento a los cuatro campos del request, y las trampas de la app. Si algo no encaja al implementar, preguntá antes de improvisar.
