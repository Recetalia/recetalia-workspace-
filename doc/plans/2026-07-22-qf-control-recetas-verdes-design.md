# Spec: Químico Farmacéutico (Regente / D.T.) — control de recetas verdes — 2026-07-22

## Contexto y objetivo

Los **químicos farmacéuticos (QF)** — también *regente* o *Director Técnico (D.T.)* — son
los responsables legales de las farmacias por los medicamentos controlados (**recetas
verdes**, `condvtaId='11'`, lo que va al "Libro Negro"). Cada farmacia tiene su QF, y un
mismo QF puede ser regente de varias farmacias (incluso de distintas cadenas).

Se necesita:

1. Un **perfil/app propia para el QF** (`qfpre.doctorconsultas.com`): al loguearse ve el listado
   de farmacias que tiene a cargo y, por cada una, el listado de **recetas verdes
   dispensadas**, con un **check de control ("firma")** por receta.
2. En el **módulo de Farmacias**, un listado de sus recetas verdes dispensadas que muestre
   si el QF ya las validó, con **exportación a Excel** en el formato "Informe de
   Medicamentos controlados por Farmacia".

Todo se despliega en **PRE (.98)** contra la **BD de PRE**.

## Decisiones tomadas (brainstorming)

- **Universo controlado por el QF:** recetas **verdes DISPENSADAS** por las farmacias que
  tiene a cargo (no las emitidas/disponibles). Coincide con las columnas del Excel
  ("Sucursal Dispensada", "Fecha+Hora Dispensada").
- **Identidad del QF = CJP.** Una sucursal cuyo `Pharmacy.managerCJP` = X ⇒ esa farmacia
  tiene a ese QF como regente. **No se crea entidad nueva**; el QF se deriva de los campos
  `manager*` de `Pharmacy`, agrupados por CJP.
- **"Firmar" = registro de control simple** (fecha + identidad del QF). Sin criptografía.
- **Login = CJP + password genérico**, que el QF **cambia obligatoriamente en el primer
  ingreso**. Su vista muestra todas las farmacias vinculadas por su CJP. Puede **cruzar
  cadenas** (identidad global por CJP).
- **Alta del QF:** dual-creation al crear/editar una sucursal en Gestión (keyed por CJP).
- **Datos del reporte:** completos (el nombre enmascarado del sample era anonimización del
  ejemplo; el Libro Negro real va con datos reales).

## Modelo de datos actual (relevante)

- `Pharmacy` (recetalia-api-rest): tiene `email` (login ROLE_PHARMACY),
  `managerName`, `managerLastname`, `managerCJP`, `managerDocument` (el regente = QF),
  `rut`, `name`, dirección (`addressLocalityId`, `addressStreet`, ...), `franchiseId`.
  **No tiene email/login del regente.**
- Recetas verdes ya modeladas: enum `Condvta` → `GREEN` = `'11'`. `Prescription.condvtaId`
  y `Dispensation.condvtaId` (con la lógica `IF(d.condvtaId='N', pr.condvtaId, d.condvtaId)`).
- `DispensationRepository.searchDispensations(...)` ya filtra por `pharmacyId` y `condvtaId`
  y devuelve una projection `DispensationSearchRow`.
- security-api: `users` (username, email únicos, roles ManyToMany), `roles` (seed en
  `V2__data.sql`). Login por **email**; JWT lleva claim `mail` y `role` (con doble prefijo
  `ROLE_ROLE_*` al llegar a api-rest).
- Patrón dual-creation existente: `FranchiseServiceImpl.applyAdmin` crea el usuario del
  admin de cadena en security-api (`ROLE_PHARMACY_ADMIN`, resuelto por `franchise.adminEmail`).

## Cambios de modelo

### security-api
- **Rol nuevo** `ROLE_PHARMACEUTICAL_DIRECTOR` (regente / director técnico). Seed en nueva
  migration.
- **`users.mustChangePassword`** (boolean, default false) para forzar el cambio en el 1er
  ingreso. Se expone en `TokenResponse`.

### recetalia-api-rest
- **Registro de control D.T.** en `Dispensation` (1:1 con las columnas del Excel):
  - `dtControlAt` (Instant, nullable) → "Fecha Control D.T."
  - `dtControlName` (String, nullable) → nombre del QF que controló
  - `dtControlCjp` (String, nullable) → CJP del QF
  - Un registro por dispensación. **Idempotente**: si ya está controlada, no re-firma.

Sin cambios en el modelo de recetas verdes.

## Identidad y autenticación del QF

- El usuario del QF en security-api se crea con `username = CJP` y `email = CJP` (o
  sintético `{cjp}@qf.recetalia.com` si hiciera falta un email válido), rol
  `ROLE_PHARMACEUTICAL_DIRECTOR`, password genérico, `mustChangePassword = true`.
- El QF ingresa **CJP + password**. El JWT lleva el CJP (en `mail`/`sub`).
- La app QF y api-rest resuelven las farmacias con `Pharmacy WHERE managerCJP = cjp`.
- **Dual-creation (keyed por CJP):** al crear/editar una sucursal con `managerCJP`, api-rest
  asegura el usuario QF en security-api (crear si ese CJP no existe; si existe, no-op — no
  duplica). Mismo patrón que `FranchiseServiceImpl.applyAdmin`.

## Endpoints

### security-api
- Seed rol `ROLE_PHARMACEUTICAL_DIRECTOR`.
- `POST /api/auth/registerBack` (existente) — lo invoca api-rest para crear el usuario QF.
- Login existente (`/loginBack`, `/login` con AES) — sin cambios; "email" = CJP.
- Cambio de contraseña: reusar el mecanismo existente (`renewPassword`/change) + exponer
  `mustChangePassword` en el login.

### recetalia-api-rest
- **Dual-creation en `PharmacyServiceImpl.create/update`**: si hay `managerCJP`, asegurar
  usuario QF en security-api.
- `GET /api/pharmacies/by-manager-cjp/{cjp}` → farmacias del QF. El `cjp` de autorización
  sale del **token**, no del path.
- **Listado de verdes dispensadas del QF por farmacia:** reusar
  `DispensationRepository.searchDispensations` con `pharmacyId` + `condvtaId='11'`, agregando
  a la projection `dtControlAt/dtControlName/dtControlCjp`. Endpoint scopeado al QF (valida
  que la farmacia tenga su CJP).
- **Firmar/controlar:** `POST /api/dispensations/{id}/dt-control` → setea `dtControlAt=now`,
  `dtControlName`, `dtControlCjp` con la identidad del token. **Idempotente** (no-op/409 si
  ya controlada). Autorización: la dispensación debe pertenecer a una farmacia cuyo
  `managerCJP` = CJP del token.
- **Matcher de seguridad** para el rol nuevo:
  `hasAuthority("ROLE_ROLE_PHARMACEUTICAL_DIRECTOR")` (doble prefijo, ya conocido).

### Módulo Farmacias (export)
- `GET /api/dispensations/controlled-medications/excel?pharmacyId=&startDate=&endDate=`
  (o reusar el search con `condvtaId='11'` + generador de Excel nuevo).

## App QF — `qf-recetalia-app` → `qfpre.doctorconsultas.com`

Angular 18 SSR, **clonada de `farmacias-recetalia-app`** y reducida.

- **Login** por CJP + password (mismo AES/ECB). `authGuard` valida
  `ROLE_PHARMACEUTICAL_DIRECTOR`.
- **Primer ingreso:** si `mustChangePassword`, pantalla de cambio de contraseña
  obligatoria antes de entrar.
- **Home = listado de farmacias** del QF (`by-manager-cjp`). Fila/card por farmacia.
- **Detalle por farmacia = recetas verdes dispensadas** (estilo Libro Negro: código,
  paciente, médico, medicamento, fecha dispensación) + **check "Controlar/Firmar"** por
  fila. Al tildar → `POST dt-control` → la fila queda "Controlada DD/MM/YYYY". Filtros de
  fecha/estado.
- Environment `qfpre.doctorconsultas.com` (front) → `apipre.recetalia.com` (API).

## Módulo Farmacias — listado + Excel

En `farmacias-recetalia-app` (ROLE_PHARMACY / ROLE_PHARMACY_ADMIN):

- **Nuevo listado** "Medicamentos controlados" = recetas verdes dispensadas de la farmacia
  + estado de control del QF (Controlada / Pendiente, con fecha y QF).
- **Export Excel** con el formato del archivo de referencia (Apache POI, método nuevo):
  - **Cabecera** (bloque A:B): Farmacia (`name`), Rut, Dirección, Departamento, Localidad.
  - **Tabla (9 columnas):**
    1. Código Único + Fecha Prescripción
    2. Prestador (nombre del prestador o "Particular")
    3. Nombre Paciente + Cédula
    4. Nombre Médico + CJP
    5. Medicamento
    6. Sucursal Dispensada
    7. Fecha + Hora Dispensada
    8. Fecha Control D.T. (vacía si pendiente)
    9. Nombre + CJP D.T. (vacía si pendiente)
  - Lista **todas** las verdes dispensadas del período; las columnas D.T. se llenan solo
    cuando el QF firmó.

## Deploy (PRE / .98)

- **DNS (ya creado):** `qfpre.doctorconsultas.com` → **A 138.197.150.98** (.98 = PRE),
  **DNS only** (NO proxied por Cloudflare) → el browser pega directo al .98.
- `qf-recetalia-app` al stack de deploy: servicio en compose + bloque nginx
  `qfpre.doctorconsultas.com`.
- **Cert TLS propio en el .98** para `qfpre.doctorconsultas.com` (al ser DNS-only no lo
  cubre el edge de Cloudflare → Let's Encrypt en el nginx del .98, como el resto de los
  `*pre` DNS-only del .98).
- **CORS:** agregar `https://qfpre.doctorconsultas.com` como origin permitido en la API
  (`apipre.recetalia.com`) y en security-api — es cross-origin (front en `doctorconsultas.com`,
  API en `recetalia.com`).
- Migrations: rol nuevo (security DB) + columnas `dtControl*` (receta DB) + posible
  `mustChangePassword` — aplicadas en PRE.
- Build en server (serial), verificación por curl + login por CJP.
- Ramas de trabajo, **sin merge hasta OK explícito de Pablo** (regla no-merge-sin-ok).

## Alcance / no incluido (YAGNI)

- No hay firma digital criptográfica (solo registro de control).
- No se crea una entidad `PharmaceuticalDirector` separada (se deriva por CJP).
- No se despliega a PROD (.217) en esta iteración.
- No se enmascaran datos del paciente en el reporte.
- El control es **one-way** (no se contempla "des-controlar" en V1).

## Riesgos / puntos a cuidar

- **Consistencia del CJP** entre sucursales: la identidad del QF depende de que el mismo CJP
  se cargue igual en todas sus sucursales (trim/normalización).
- **Doble prefijo `ROLE_ROLE_`** en el matcher del rol nuevo (verificar como en los otros).
- **Login por CJP** en un sistema pensado para login por email: cuidar unicidad de
  `username`/`email` = CJP en `users`.
- **Dual-creation idempotente**: no duplicar el usuario QF cuando varias sucursales
  comparten CJP; manejar el 404 (crear) vs existente (no-op) como en `applyAdmin`.
- **Excel**: replicar exactamente el layout (cabecera A:B filas 2-6, tabla desde fila 9).
