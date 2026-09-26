# Spec: Fixes Testeo DEV & PRE — 2026-04-28

Diseño consolidado de las correcciones derivadas del testing de pre-prod reportado en el PDF *"Recetalia - Testeo DEV & PRE"* (entregado por el usuario el 2026-04-28).

> Este documento es el **spec/design**. El plan de implementación detallado se escribe luego en `doc/plans/2026-04-28-fixes-testeo-dev-pre-plan.md` con el skill `superpowers:writing-plans`.

## 1. Objetivo

Aplicar 18 correcciones en 4 proyectos del workspace y redeployar a pre-prod (`138.197.150.98`) en un solo ciclo:

- **medics-recetalia-app** (5 ítems)
- **farmacias-recetalia-app** (4 ítems)
- **gestion-recetadigital-app** (9 ítems)
- **recetalia-api-rest** (4 cambios técnicos que sirven a 6 de los 9 ítems de gestión: G4, G7, G8, G9, G10, G11)

Tres ítems del PDF original (M4 Crear Paciente, F4 Dispensadores, F5 AMPP) quedan **descartados** del scope a pedido del usuario.

## 2. Alcance — 18 ítems

Numeración heredada del catálogo del análisis del PDF (M = medics, F = farmacias, G = gestión).

### medics-recetalia-app

| ID | Pantalla | Tipo | Resumen |
|---|---|---|---|
| M1 | Modal "Buscar medicamento" | UI | Eliminar dropdowns de "Horas" y "Días" → texto fijo |
| M2 | Modal "Buscar medicamento" | UI | Margen del checkbox "Crónico" |
| M3 | Lista de Prescripciones | Bug FE | `ngOnInit` no llama `loadPrescriptions()` — loader infinito |
| M5 | Sidebar | UX | Mostrar desplegado por defecto |
| M6 | Sidebar | UX | Mostrar nombre del médico (`firstName + lastName`) |

### farmacias-recetalia-app

| ID | Pantalla | Tipo | Resumen |
|---|---|---|---|
| F1 | Sidebar | UX | Mostrar desplegado por defecto |
| F2 | Sidebar | UX | Mostrar nombre comercial de la farmacia (`name`, fallback a `businessName`) |
| F3 | Lista de Dispensaciones | Bug FE | `ngOnInit` espera `pharmacyId` async y nunca dispara `refreshTable()` |
| F6 | Pantalla "Buscar Prescripción" | Bug FE | Tras dispensar, el código sigue en el input |

### gestion-recetadigital-app

| ID | Pantalla | Tipo | Resumen |
|---|---|---|---|
| G1 | Farmacias | Bug FE | No carga listado por defecto al entrar |
| G2 | Pacientes | UX | Invertir orden — más reciente primero (`createdAt DESC`) |
| G3 | Modal Paciente > Prescripciones | Bug FE | `loadPrescriptions()` no se dispara en init del modal |
| G5 | Prescripciones | Feature FE | Agregar columna **MÉDICO** (`medicName + medicLastname`) — backend ya lo trae |
| G6 | Prescripciones | Bug FE | Filtro **MÉDICO** no funciona — diagnóstico runtime durante implementación |
| G7-FE | Prescripciones | Bug FE | Medicamentos vacíos — agregar fallback `productId` |
| G9-FE | Dispensaciones | Feature FE | Agregar columnas **MÉDICO** + **FARMACIA**; verificar columna **ESTADO** (ya mapeada) |
| G10 | Dispensaciones | Bug FE | Filtros **MÉDICO** (diag), **FARMACIA** (handler roto), **ESTADO** (no declarado) |
| G11-FE | Dispensaciones | Bug FE | Mismo helper de fallback que G7 |

### recetalia-api-rest

4 cambios técnicos en backend que **cubren 6 ítems user-visible del frontend** (G4, G7, G8, G9, G10, G11). Mismos archivos se tocan varias veces — los cambios se acumulan:

| Cambio técnico | Cubre ítems | Tipo | Resumen |
|---|---|---|---|
| Timezone fix | G4, G8 | Bug BE | `ZoneId.systemDefault()` → `ZoneId.of("America/Montevideo")` en 2 controllers |
| Fix NPE silencioso en lookup DNMA | G7-BE, G11-BE | Bug BE | Sacar try-catch que silencia, log WARN con `productId`; campos quedan en null |
| Extender `DispensationSearchRow` con farmacia | G9-BE | Feature BE | SQL nativa + interfaz proyectada con `pharmacyId`, `pharmacyName`, `pharmacyBusinessName` |
| Filtros faltantes en `DispensationController.search` | G10-BE | Feature BE | Verificar/agregar `@RequestParam Optional<String> pharmacyId` y `@RequestParam Optional<String> status` |

## 3. Decisiones tomadas

| # | Tema | Decisión | Razón |
|---|---|---|---|
| 1 | Estructura del trabajo | **Un único spec, un único plan, un único redeploy.** | Coherencia narrativa con el PDF, redeploy es un único build+push+deploy igual, hay overlap técnico real (timezone afecta G4/G8 a la vez; null-DNMA afecta G7/G11). |
| 2 | Sidebar — qué nombre mostrar | Médico: `firstName + lastName`. Farmacia: `name` con fallback a `businessName`. | Consistente con el resto de la UI ("Test Paciente de Prueba" en modal Dispensar usa este formato). |
| 3 | Sidebar — default desplegado | Siempre desplegado al cargar; no se persiste preferencia. | Lo más simple, alineado con la solicitud literal del PDF. |
| 4 | Fallback medicamentos vacíos | Mostrar `productId` como fallback visible. | Da trazabilidad — el equipo de gestión puede reportar exactamente cuál producto falla. Backend complementa con log WARN. |
| 5 | Fix de timezone | `ZoneId.of("America/Montevideo")` hardcoded en los 2 controllers. | Cambio quirúrgico, bajo riesgo, no rompe contrato. Si después necesitan multi-TZ, se cambia a `OffsetDateTime` en una iteración planificada. |
| 6 | F4 / F5 | **Descartados** del scope. | Decisión del usuario. |
| 7 | M4 (Crear Paciente bug) | **Descartado** del scope. | Decisión del usuario. |
| 8 | G6, G10 (filtros que "no funcionan") | Diagnóstico runtime durante implementación. | El código se ve OK estáticamente; el bug se confirma probando en pre-prod. No necesita decisión de UX. |
| 9 | Branches | Continuar en branches deployados (`register_medic` para api, `feature/workspace-bootstrap` para frontends y deploy). | Son los branches con código que está corriendo en pre-prod; cualquier branch nuevo introduciría regresión silenciosa. |
| 10 | Quien dispara el redeploy | Claude (build-and-push.sh + deploy.sh desde local). | El usuario lo prefirió así. |

## 4. Cambios técnicos por proyecto

### 4.1. recetalia-api-rest (branch `register_medic`)

**Archivos afectados:**

| Archivo | Cambio |
|---|---|
| `src/main/java/com/recetalia/api/application/controller/PrescriptionController.java` | Reemplazar `ZoneId.systemDefault()` por constante `MONTEVIDEO_ZONE = ZoneId.of("America/Montevideo")` en líneas 216-217 |
| `src/main/java/com/recetalia/api/application/controller/DispensationController.java` | Idem en líneas 121-127. Verificar/agregar `@RequestParam Optional<String> pharmacyId` y `@RequestParam Optional<String> status` |
| `src/main/java/com/recetalia/api/application/service/impl/PrescriptionServiceImpl.java` | Métod `mapPrescriptionWithAmpDetailsOption2` (líneas 266-294): sacar try-catch silencioso, agregar null-checks explícitos en `vmpDetails`/`ampDetails`, log WARN con `productId` cuando el lookup DNMA devuelve vacío |
| `src/main/java/com/recetalia/api/application/dto/response/DispensationSearchRow.java` | Agregar getters `getPharmacyId()`, `getPharmacyName()`, `getPharmacyBusinessName()` |
| `src/main/java/com/recetalia/api/application/domain/repository/DispensationRepository.java` | SQL nativa (líneas 80-113): añadir `LEFT JOIN pharmacies ph ON d.pharmacy_id = ph.id` (si no está) y `ph.id AS pharmacyId, ph.name AS pharmacyName, ph.business_name AS pharmacyBusinessName` al SELECT. Agregar al WHERE `(:pharmacyId IS NULL OR d.pharmacy_id = :pharmacyId)` y `(:status IS NULL OR d.status = :status)` si los `@RequestParam` se introducen |

**Test coverage:**

- Test unitario por controller verificando `LocalDate → Instant` con TZ Montevideo (no la TZ del runner CI).
- Test unitario que mockee `dnmaDatabaseServiceImpl` con map vacío y verifique sin throw + log WARN + campos null en el response.

**Bonus (opcional, low risk):** corregir `<` → `<=` en `DispensationRepository.java:153` para simetría con `PrescriptionRepository.java:58`. Sin efecto funcional perceptible (sólo afecta el último nanosegundo del día).

**Compatibilidad backward:** sí. Nuevos campos en `DispensationSearchRow` son adicionales; nuevos `@RequestParam` son `Optional`; el cambio de TZ corrige un bug, no cambia contrato.

### 4.2. medics-recetalia-app (branch `feature/workspace-bootstrap`)

| ID | Archivo | Cambio |
|---|---|---|
| M1 | Componente del modal "Buscar medicamento" (`medicamento-form` o equivalente — confirmar durante impl) | Eliminar `<p-dropdown>` de Horas/Días, reemplazar por `<span>` con texto fijo. Hardcodear `frecuencyUnit`/`durationUnit` en el request |
| M2 | SCSS del modal | Agregar `padding-left` o `margin-left` al wrapper del checkbox "Crónico" |
| M3 | `src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.ts:139-159` | Agregar `this.loadPrescriptions({ first: 0, rows: this.size })` al final de `ngOnInit` |
| M5/M6 | Componente shell del HomeModule (sidebar/header) | Setear flag de colapso (`sidenavOpened` o equivalente) a `true` por defecto. Leer médico vía `AuthService` (decoded JWT mail → `MedicService.getByEmail()`) y mostrar `firstName + lastName` |

### 4.3. farmacias-recetalia-app (branch `feature/workspace-bootstrap`)

| ID | Archivo | Cambio |
|---|---|---|
| F1/F2 | Componente shell del HomeModule | Análogo a M5/M6 con `Pharmacy.name` (fallback `businessName`) |
| F3 | `src/app/pages/application/home/dispensations/dispensation-list/dispensation-list.component.ts:110-119` | Reescribir el init para leer `pharmacyId` desde `localStorage`/JWT decodificado sincrónico; si no, `getCurrentUser()` con `filter(u => !!u?.pharmacyId)` antes del `take(1)`. Si tras todo no hay `pharmacyId`, mostrar mensaje de error en UI (no loader infinito) |
| F6 | Componente que dispara `dispensar()` (probable `dispensation-search-form.component` o equivalente) | Tras éxito, `this.codigoControl.setValue('')` + `this.searchForm.reset()` |

### 4.4. gestion-recetadigital-app (branch `feature/workspace-bootstrap`)

| ID | Archivo | Cambio |
|---|---|---|
| G1 | `pharmacy-list.component.ts` | Disparar la llamada paginada al endpoint `/api/pharmacies/paginated` en `ngOnInit` |
| G2 | Service o componente de Pacientes (donde se construye el `HttpParams` del paginado) | Setear `sort=createdAt,desc` como default. Si el backend elige el sort, hacerlo allá con `Sort.by("createdAt").descending()` |
| G3 | `src/app/pages/application/home/prescriptions/prescription-list/prescription-list.component.ts:166-200` | Agregar `this.loadPrescriptions({ first: 0, rows: this.size })` al final del `ngOnInit` del modal, después de setear `patientId` desde `config.data.patient` |
| G5 | Template del listado de Prescripciones | Agregar `<th>Médico</th>` y celda `{{ prescription.medicName }} {{ prescription.medicLastname }}` |
| G6 | Componente de Prescripciones | Diagnóstico runtime durante implementación. Hipótesis ordenadas: (1) dropdown no popula, (2) `selectedMedicId` no dispara refresh, (3) backend no aplica filtro |
| G7-FE | Componente de Prescripciones | Reemplazar `<span *ngIf="productType == 'VMP'">{{ vmpDsc }}</span>` etc. por helper `displayPrescriptionProductName(p)` que devuelve `p.vmpDsc \|\| p.ampDsc \|\| p.prodMsp \|\| p.productId \|\| '—'` (en este orden de preferencia) |
| G9-FE | Template del listado de Dispensaciones | Agregar `<th>Médico</th>` con `r.medicName + r.medicLastname` (campos ya en response). Agregar `<th>Farmacia</th>` con `r.pharmacyName \|\| r.pharmacyBusinessName` (campos nuevos tras G9-BE). Confirmar Estado (`r.dispensationStatus`) ya visible — si no, fix de layout |
| G10 | Componente y template de Dispensaciones | (a) Médico: igual diag que G6. (b) Farmacia: corregir `onPharmacySelect($event)` para `$event.value` y disparar `refreshTable()`. (c) Estado: agregar `<p-dropdown>` con valores `AVAILABLE / DISPENSED / CANCELLED` (verificar enum exacto), handler `onStatusSelect`, query param `status` |
| G11-FE | Template de Dispensaciones | Helper `displayDispensationProductName(r)` que devuelve `r.dispensationProductName \|\| r.productId \|\| '—'` (helper distinto al de Prescripciones porque los campos del row son distintos) |

## 5. Validación

### 5.1. Validación local antes de pushear

| Ítem | Cómo se valida |
|---|---|
| M1, M2 | `npm start` medics, abrir modal — confirmar dropdowns eliminados y margen aplicado |
| M3, F3, G1, G3 | `npm start` proyecto, login, navegar a la pantalla — datos cargan sin acción manual |
| M5/M6, F1/F2 | `npm start`, login — sidebar expandido + nombre completo |
| F6 | Login farmacia, dispensar, confirmar input vacío |
| G2 | Login gestión > Pacientes — primer paciente es el más reciente (verificar columna CREACIÓN) |
| G4/G8 | Test unitario backend con TZ Montevideo. Smoke test post-deploy con rango 26-03 → 24-04 |
| G5 | Login gestión > Prescripciones — columna MÉDICO con valores |
| G6, G10 | Probar filtros en runtime, network tab debe mostrar query params correctos |
| G7/G11 | Test unitario backend mockeando map vacío. Validación visual del fallback `productId` requiere productos rotos en DNMA — validación principal post-deploy |
| G9-BE | Curl al endpoint con JWT, verificar JSON con `pharmacyName` |
| G9-FE | Login gestión > Dispensaciones — columnas FARMACIA y MÉDICO con valores |

### 5.2. Criterios de éxito post-deploy

1. Las 4 pantallas que "no levantaban" (M3, F3, G3, G1) muestran datos al primer load.
2. Login en medics y farmacias muestra sidebar expandido y nombre del usuario.
3. Gestión > Prescripciones con rango 2026-03-26 → 2026-04-24 muestra registros del 26-03 al 23-04.
4. Gestión > Prescripciones con columna MÉDICO + filtro Médico funcional.
5. Gestión > Dispensaciones con columnas FARMACIA, MÉDICO + filtros Farmacia/Médico/Estado funcionales.
6. Productos sin lookup DNMA muestran `productId` y la API loguea WARN con esos IDs.
7. Modal de medicamento sin dropdowns innecesarios y con margen del checkbox.
8. Tras dispensar, el código se limpia.
9. Pacientes ordenados con el más reciente primero.

### 5.3. Fuera de scope

- Reset password con token largo (TODO general).
- Spring Security en `transversal-recetalia-api`.
- Eliminar typos del contrato (`frecuency`, `Droug`, etc.).
- Tests E2E nuevos en frontends (no hay infra hoy).
- Migración de passwords plain-text a hashes.

## 6. Estrategia de redeploy

### 6.1. Pre-condiciones

- 18 ítems commiteados en sus branches.
- Cada repo afectado compila local: `./gradlew build` (api) y `npm run build` con configs `production` + `preprod` (frontends).
- Tests verdes en api (los frontends no tienen suite activa).

### 6.2. Pasos

1. `cd /Users/pablo/iwtg/recetalia-workspace/deploy-recetalia && ./scripts/build-and-push.sh` → buildea las 7 imágenes y las pushea al registry self-hosted.
2. Verificar `curl -u $REGISTRY_USER:$REGISTRY_PASSWORD https://registrypre.recetadigital.uy/v2/_catalog` muestra las 7 imágenes.
3. `./scripts/deploy.sh root@138.197.150.98 /opt/recetalia` → rsync compose y `docker compose up -d` en el server.
4. Verificar `docker compose ps` en el server: 8 servicios running.
5. Smoke tests sobre los 9 criterios de éxito.

### 6.3. Rollback

- **Recomendado:** revertir el commit del proyecto que rompe → rebuild + push de esa imagen → redeploy parcial.
- **Si rotamos imágenes con timestamp además de `:latest`** (decisión opcional durante implementación): retag del timestamp previo y deploy. Si no, dependemos de `git revert + rebuild`.

### 6.4. Riesgos

| Riesgo | Mitigación |
|---|---|
| Dockerfile no compila tras los cambios | Build local de cada imagen antes de pushear |
| Registry no autentica | `docker login` antes de empezar |
| Server sin disco para pulls | `docker system prune -af` previo si hace falta |
| Cambios de DTO en `DispensationSearchRow` rompen serialización | Smoke test del endpoint vía curl antes del frontend |
| Bug que sólo aparezca en pre-prod (TZ real del contenedor) | El test unitario de TZ atrapa la mayoría; smoke del rango 26-03/24-04 confirma |

## 7. Próximos pasos

1. **Spec self-review** (este turno) — chequeo placeholders, contradicciones, ambigüedad, scope.
2. **User review** — el usuario lee este spec y confirma o pide cambios.
3. **`superpowers:writing-plans`** — generar el plan de implementación detallado, paso a paso, con criterios verificables y commits por ítem.
4. Implementación — sigue el plan generado.
5. Build + push + deploy — ver sección 6.
6. Smoke tests post-deploy + cierre del ciclo.
