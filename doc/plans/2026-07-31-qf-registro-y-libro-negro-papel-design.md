# Spec: QF — registro propio, recetas en papel y Nº de talonario — 2026-07-31

Tres features sobre el módulo QF / Libro Negro entregado el 2026-07-23
(ver [2026-07-22-qf-control-recetas-verdes-design.md](2026-07-22-qf-control-recetas-verdes-design.md)):

1. **Registro del QF** — el Químico Farmacéutico define su propia clave, verifica sus datos
   personales y ve todas las farmacias que lo asociaron como D.T.
2. **Mantenimiento de Libro Negro** — la farmacia carga al sistema recetas emitidas en papel.
3. **Nº de receta** — los listados muestran el número del talonario además del código Recetalia.

Proyectos tocados: `recetalia-api-rest`, `farmacias-recetalia-app`, `gestion-recetadigital-app`,
`qf-recetalia-app`. `security-api-recetalia` no cambia.

---

## Contexto y problema

El módulo QF actual resuelve el control de recetas verdes, pero arrastra tres huecos.

**El QF no existe como entidad.** Sus datos viven copiados en cada farmacia
(`pharmacy.managerName`, `managerLastname`, `managerCJP`, `managerDocument`). Un mismo QF que es
D.T. de tres farmacias tiene sus datos escritos tres veces y pueden divergir — ya pasó en PRE con
el CJP 999999. Además el usuario de login se crea solo, con la clave fija `Recetalia2026` para
todos, sin que nadie le avise al QF ni valide que es él.

**Las recetas verdes en papel no entran al sistema.** No todas las recetas se emiten por Recetalia;
la farmacia recibe recetas en papel que igual tiene que asentar en su libro de controlados. Hoy no
hay forma de cargarlas.

**El número de talonario no se guarda en ningún lado.** Verificado contra el código y contra la DB
de PRE: no existe columna para él ni en `prescription` ni en `dispensation`, y ningún formulario lo
pide. Lo más parecido es `dispensation.loteNumber`, que es el lote del medicamento.

---

## Alcance

### Entra

- Entidad `pharmaceutical_director` con el CJP como clave, y el alta/selección del QF desde los
  formularios de farmacia.
- Pantalla de registro / primer ingreso en `qf-recetalia-app`.
- Pantalla "Mantenimiento de Libro Negro" en `farmacias-recetalia-app` para cargar recetas en papel
  (crea receta + dispensación en un solo acto).
- Nº de talonario en el listado del QF, en el Libro Negro de Farmacias y en el Excel de controlados.
- Backfill de los QF que ya existen denormalizados en `pharmacy`.

### No entra

- Capturar el Nº de talonario en las recetas **digitales** — no se toca `medics-recetalia-app`. Las
  recetas emitidas por Recetalia siguen sin número de talonario y la columna sale vacía para ellas.
- Invitación por email o token de activación del QF: el alta la hace la farmacia y la clave inicial
  se entrega en mano.
- Notificaciones al QF.

---

## Decisiones de diseño

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| La receta de papel reusa `prescription` + `dispensation` con un flag `origin` | Tabla `paper_prescription` aparte | Con el flag, el Libro Negro, el listado del QF, el Excel y los dashboards siguen andando sin tocar una query. La tabla aparte obligaba a rehacer todas esas consultas con `UNION`. |
| Cargar una receta de papel crea la receta **y** su dispensación en el mismo acto | Cargar solo la receta y dispensarla después por el flujo normal | Es el flujo real del mostrador: la farmacia tiene el papel en la mano porque ya entregó el medicamento. |
| Médico y paciente de papel se crean como registros reales, con dedupe por CJP y por documento | Guardar los datos sueltos como texto en la receta | Mantiene la trazabilidad por paciente, que es todo el sentido del libro negro, y no obliga a parchear los JOIN de todas las consultas. |
| El QF pasa a ser una entidad con el CJP como clave única | Seguir con los `manager*` denormalizados | Sin entidad no hay dónde guardar email, teléfono ni el estado de registro, y el mismo CJP puede divergir entre farmacias. |
| El alta del QF la hace la farmacia, con clave inicial entregada en mano | Auto-registro del QF tipeando su CJP | Con auto-registro, cualquiera que conozca un CJP podría reclamar la cuenta. |
| Los KPIs de actividad de Gestión filtran `origin = 'DIGITAL'` | Contar todo | Una receta que la farmacia transcribió de un papel no es actividad de la plataforma. El Libro Negro, el listado del QF y el Excel de controlados sí incluyen las dos. |
| `paperIssuedAt` guarda la fecha del papel; la dispensación queda fechada al momento de la carga | Dejar que la farmacia feche la dispensación a mano | El libro negro conserva la fecha legal de la receta, pero la farmacia no puede retrodatar el registro para tapar una carga tardía. |

---

## Modelo de datos

Los tres cambios van en `recetali_receta`. **`recetalia-api-rest` tiene `ddl-auto: none` y no usa
Flyway** — los `ALTER TABLE` se aplican a mano en cada ambiente.

### Tabla nueva `pharmaceutical_director`

| Columna | Tipo | Null | Notas |
|---|---|---|---|
| `id` | varchar(36) | NO | PK, UUID asignado por la app |
| `cjp` | varchar(150) | NO | **UNIQUE** — la clave real del QF |
| `name` | varchar(150) | NO | |
| `lastname` | varchar(150) | NO | |
| `document` | text | SÍ | JSON vía `DocumentConverter` |
| `email` | varchar(200) | SÍ | De contacto. El login sigue siendo `{cjp}@qf.recetalia.com` |
| `phone` | text | SÍ | JSON vía `PhoneConverter` |
| `status` | varchar(255) | NO | `ACTIVE` / `INACTIVE` / `NEEDS_REVIEW` |
| `registeredAt` | timestamp(6) | SÍ | NULL = nunca completó su registro |
| `createdAt` / `updatedAt` | timestamp(6) | NO | |

**Sin `deletedAt`, a diferencia del resto de las entidades.** El CJP es un identificador
profesional permanente con un `UNIQUE` encima: soft delete más unicidad es una trampa conocida —
borrado lógicamente un QF, su CJP no se puede volver a registrar nunca. La baja de un QF se expresa
con `status = 'INACTIVE'`, que ya cubre el caso.

### `pharmacy`

Columna nueva `pharmaceuticalDirectorId varchar(36)` con FK a `pharmaceutical_director.id`.

Los cuatro `manager*` **se conservan** — los usan el Excel de farmacias, el perfil y varias
consultas — pero dejan de ser la fuente de verdad: se escriben desde el QF vinculado en cada alta y
edición.

### `prescription`

```sql
ALTER TABLE prescription
  ADD COLUMN origin        VARCHAR(10) NOT NULL DEFAULT 'DIGITAL',
  ADD COLUMN paperNumber   VARCHAR(50) NULL,
  ADD COLUMN paperIssuedAt DATETIME    NULL;
```

`origin` ∈ {`DIGITAL`, `PAPER`}. `paperNumber` es el Nº del talonario. `paperIssuedAt` es la fecha
que dice el papel. Las recetas que ya existen quedan con `origin = 'DIGITAL'` por el default y los
otros dos en NULL, sin necesidad de tocarlas.

### Backfill

Script idempotente: por cada `TRIM(managerCJP)` distinto en `pharmacy` (no borradas), crear un
`pharmaceutical_director` con los datos de la farmacia modificada más recientemente, y setear
`pharmaceuticalDirectorId` en todas las farmacias de ese CJP. `registeredAt` queda NULL, así el QF
cae en la pantalla de registro la próxima vez que entre.

**El CJP viene sucio y hay que contemplarlo.** Medido sobre los datos reales de DEV: 20 CJPs están
compartidos por personas con nombres distintos, y afectan a 65 de 337 farmacias. El peor caso es el
CJP `1`, con siete farmacias y seis personas. Hay además CJPs que ni siquiera son numéricos
(`fdsfsdf`, `asfsd`) y uno con espacio inicial que sin `TRIM` genera dos QFs para la misma persona.

Esos CJPs colisionados **se crean igual, pero con `status = 'NEEDS_REVIEW'`**. No son identidades
confiables: un QF marcado así no puede completar su registro ni firmar recetas, y sus farmacias
quedan vinculadas pero inertes hasta que alguien cure el dato. La alternativa —dejar que el
`ROW_NUMBER` elija un nombre y seguir— materializaría una identidad falsa sobre la que después se
autoriza el acceso a medicamentos controlados.

Verificación: `COUNT(DISTINCT TRIM(managerCJP))` en `pharmacy` == `COUNT(*)` en
`pharmaceutical_director`, cero farmacias activas con `managerCJP` no vacío y
`pharmaceuticalDirectorId` nulo, y la cantidad de `NEEDS_REVIEW` igual a la cantidad de CJPs
colisionados.

### Cómo se cura un CJP marcado

Un QF en `NEEDS_REVIEW` no puede registrarse, así que tampoco puede arreglar su propio nombre:
la salida tiene que venir de Gestión.

**Recálculo automático.** Cada vez que se guarda una farmacia con un CJP, el backend recalcula el
estado de ese CJP: si ya no figura con más de un titular, el QF pasa solo a `ACTIVE`. Así, corregir
el `managerCJP` de las farmacias equivocadas —cosa que el modal de Gestión ya permite— destraba al
QF sin que nadie tenga que acordarse de un paso extra. Y si mañana alguien vuelve a cargar un CJP
repetido, el marcado vuelve a aplicarse solo.

**Bandeja en Gestión.** Una pantalla nueva lista los QF en revisión con la cantidad de farmacias y
los titulares en conflicto, y permite saltar a esas farmacias para corregirlas. Sin ella la
curación es posible pero invisible: habría que ir farmacia por farmacia sin saber cuáles faltan.

---

## Feature 1 — Registro del QF

### 1.A Alta / selección desde la farmacia

El D.T. se carga hoy como texto libre en cuatro pantallas:

- `farmacias-recetalia-app`: `pages/application/register` y `pages/application/home/profile`
- `gestion-recetadigital-app`: `pages/application/home/pharmacy/pharmacy-update` y
  `pages/application/home/pharmacy/profile`

Las cuatro pasan a disparar un lookup al salir del campo CJP:

```
CJP del D.T.  [51697        ]  ← al blur, busca

┌─ ENCONTRADO ──────────────────┐   ┌─ NO ENCONTRADO ───────────────┐
│ ✓ JUAN PEREZ — CJP 51697      │   │ CJP 51697 — QF nuevo          │
│                               │   │ Nombre    [            ]      │
│ Ya registrado en Recetalia.   │   │ Apellido  [            ]      │
│ Se asocia a esta farmacia.    │   │ Documento [            ]      │
│                               │   │ Clave inicial [        ]      │
│ (sin campos editables)        │   │ ↳ entregásela al QF en mano   │
└───────────────────────────────┘   └───────────────────────────────┘
```

**Endpoint** `GET /api/pharmacies/pharmaceutical-director-lookup/{cjp}` → 200 con
`{cjp, name, lastname}` o 404. Es **público** porque el alta de farmacia lo es, y por eso devuelve
**solo nombre y apellido**: nunca documento, email ni teléfono. Tipear CJPs al azar no puede filtrar
datos personales.

Va colgado de `/api/pharmacies/**` a propósito, y se agrega a la lista de `permitAll` de
`SecurityConfiguration`. No puede vivir bajo `/api/pharmaceutical-director/**`, que está reservado
para los endpoints del QF autenticado: un path parecido y público al lado de uno protegido es
exactamente la clase de vecindad que después se abre de más por accidente.

**Backend.** `PharmacyServiceImpl.ensurePharmaceuticalDirectorUser(cjp)` se reemplaza por
`resolvePharmaceuticalDirector(request)`:

1. Busca por CJP. **Existe** → vincula la farmacia y sincroniza los `manager*`. No toca ni un dato
   del QF ni su clave.
2. **No existe** → crea la fila y llama a `securityApiRecetaliaPort.registerUserBack` con
   `{cjp}@qf.recetalia.com`, la clave que mandó la farmacia, rol `ROLE_PHARMACEUTICAL_DIRECTOR`,
   app `qf-recetalia-app`, `mustChangePassword = true`.
3. Si el security-api falla, se revierte la fila del QF — mismo patrón que `MedicServiceImpl`.

La clave inicial viaja cifrada AES-ECB con el `info` dinámico, igual que el resto de los passwords
del alta de farmacia. La property `qf.default-password` de `application.yml` se elimina.

### 1.B Primer ingreso en la app del QF

`/change-password` (que solo pide clave nueva) se reemplaza por `/registro`, en un solo paso:

- **Datos personales** — nombre, apellido y documento precargados con lo que cargó la farmacia,
  editables. Email y teléfono vacíos, los completa el QF.
- **Farmacias que lo asociaron** — solo lectura: nombre y dirección. Le permite detectar que alguien
  lo declaró D.T. sin avisarle.
- **Clave nueva** + confirmación (mínimo 6 caracteres, igual que la pantalla actual).

**Disparo:** `mustChangePassword` en el token **o** `registeredAt IS NULL`. El `authGuard` no lo deja
salir de `/registro` hasta completar: sin registro no puede firmar recetas.

**Endpoints:**

- `GET /api/pharmaceutical-director/me` → datos del QF + sus farmacias, para precargar.
- `POST /api/pharmaceutical-director/register` → actualiza la fila, sella `registeredAt`, propaga
  los datos a los `manager*` de todas sus farmacias y llama a `renew-password` del security-api
  (que ya pone `mustChangePassword = false`).

Ambos bajo `/api/pharmaceutical-director/**`, que ya exige
`hasAuthority("ROLE_ROLE_PHARMACEUTICAL_DIRECTOR")` (el doble prefijo es el quirk conocido del
converter JWT).

**Corrección derivada:** `PharmaceuticalDirectorServiceImpl.buildQfName()` hoy arma el nombre del
firmante leyendo `pharmacy.managerName` de la farmacia de esa dispensación, así que el mismo QF
podía firmar con nombres distintos según la sucursal. Pasa a leer de la entidad QF.

---

## Feature 2 — Mantenimiento de Libro Negro

Ítem nuevo en el sidebar de `farmacias-recetalia-app`, para `ROLE_PHARMACY` y `ROLE_PHARMACY_ADMIN`
(el admin de cadena elige sucursal primero, igual que en el Libro Negro). La pantalla lista las
recetas que esa farmacia cargó en papel, con el botón **+ Cargar receta en papel**.

Se cargan recetas de cualquier tipo, aunque en la práctica van a ser casi todas verdes.

### Formulario

Sigue el orden del documento impreso de la receta:

| Bloque | Campos |
|---|---|
| Paciente | Nombre, Apellido, Tipo + Nº de documento |
| Médico | Nombre, Apellido, CJP |
| Receta | Nº de receta del papel, Fecha de la receta |
| Medicamento | Buscador DNMA — `GET /api/amp/search?prodMspLike=`, el mismo de la app de médicos |
| Administración | Dosis + unidad, Frecuencia + unidad, Duración + unidad |
| Dispensación | Cantidad de cajas, Lote, Vencimiento del lote, A quién se entregó |

El lote es obligatorio: `dispensation.loteNumber` es `NOT NULL` y es el mismo dato que ya pide el
flujo de dispensación normal.

Del medicamento salen `productType`, `productId`, `condvtaId`, `dnmaLaboratoryId` y el principio
activo. **El tipo de receta no se elige**: se muestra como chip (Verde / Naranja / Blanca) derivado
del `condvtaId`, igual que en las recetas digitales. "A quién se entregó" viene precargado con el
paciente y es editable.

**La frecuencia es obligatoria.** Si va NULL, el tope de cajas al dispensar no aplica y la app
muestra "1 comprimido cada `[vacío]` horas" — ya pasó con las recetas de prueba viejas.

### Backend

`POST /api/prescriptions/paper`, `@PreAuthorize` para `ROLE_PHARMACY` o `ROLE_PHARMACY_ADMIN`. No
reusa `upsert-and-create`, que es de médicos y providers y exige otro rol y otro payload. Todo en
una transacción:

1. **Médico** — `findByCjp(cjp)`. Si no existe, se crea con email sintético
   `{cjp}@papel.recetalia.com`, sin teléfono y sin `medicalProviderId`. Si el médico ya receta
   digitalmente en Recetalia, se reusa el existente.
2. **Paciente** — `findByDocumentNumberAndType`. Si no existe, se crea sin teléfono.
3. **Receta** — código con el `generateUniqueBaseCode()` de siempre (6 hex + sufijo `-A`),
   `origin = 'PAPER'`, `paperNumber`, `paperIssuedAt`, `status = 'DISPENSED'`,
   `dateTimeToSend = NULL`, `dispensationPendingReminderSended = 1`.
4. **Dispensación** — `status = 'DISPENSED'`, `dispensedById` = el dispensador logueado,
   `pharmacyId` resuelto del usuario (no del body), cantidad, lote, `dispensedTo*`.
5. Devuelve el código Recetalia generado, que la pantalla muestra en la confirmación.

`medic.phone`, `patient.phone` y `medic.birthdate` son `NOT NULL` en la DB: van con valores vacíos
(`{}` en los campos JSON). Es feo, pero evita cambiar el schema de dos tablas centrales.

**Notificaciones: ninguna.** Garantizado por partida doble — los flags de la receta la sacan de los
dos schedulers (el de WhatsApp de recetas `PENDING` y el de recordatorio de no-retiro), y el
paciente de papel no tiene teléfono a donde recibirlas.

### Anulación

La farmacia puede anular una receta de papel que cargó mal. **No es soft delete**: las consultas del
Libro Negro y del QF filtran `deletedAt IS NULL`, así que borrarla la haría desaparecer del registro,
que es justo lo contrario de lo que un libro de controlados necesita.

Se anula con `dispensation.status = 'CANCELLED'` + `dispensedCancelledById` (columnas que ya
existen) y `prescription.status = 'CANCELLED'`. La fila queda visible y tachada en el listado de
mantenimiento, y el QF la ve como anulada — que es el estado "Cancelada" del mockup.

---

## Feature 3 — Nº de receta en los listados

La query nativa de `DispensationRepository.searchDispensations` suma `pr.paperNumber` y `pr.origin`
a la proyección `DispensationSearchRow`. Los mismos dos campos se agregan a los modelos
`dispensation-search-row.ts` de `qf-recetalia-app` y `farmacias-recetalia-app`.

La columna CÓDIGO pasa a dos líneas:

```
CÓDIGO
O222R4          ← código Recetalia
Nº 0648345      ← paperNumber, gris chico
```

Sin `paperNumber`, la segunda línea no se renderiza. Aplica al listado del QF y al Libro Negro de
Farmacias. El Excel de controlados suma una columna "Nº receta".

---

## Manejo de errores

| Situación | Comportamiento |
|---|---|
| Lookup de CJP devuelve 404 | Se habilitan los campos de alta del QF |
| Lookup de CJP falla por red/timeout | Se muestra el error y **no** se habilita el alta — un timeout no puede terminar creando un QF duplicado |
| `registerUserBack` falla al crear el QF | Se revierte la fila del QF y el alta de farmacia informa el error |
| `renew-password` falla en el registro del QF | No se sella `registeredAt`; puede reintentar |
| Cualquier paso de la carga de papel falla | Rollback de la transacción completa: no queda receta sin dispensación |
| `paperNumber` repetido en la misma farmacia | Advertencia, no bloqueo — los talonarios se repiten entre farmacias |

**Deuda que se aprovecha a pagar:** `farmacias-recetalia-app` tiene el mismo bug de `AuthInterceptor`
que se arregló en `qf-recetalia-app` (manda `Bearer` a `/api/auth/*` y el security-api responde
401). Hoy no molesta porque la app solo pega a api-rest con token válido, pero la pantalla nueva lo
destapa.

---

## Seguridad

- **Un QF en `NEEDS_REVIEW` no ve ni firma nada.** El módulo QF que ya está deployado autoriza por
  CJP: `getGreenDispensations` y el control de dispensaciones le muestran al QF todas las farmacias
  con su `managerCJP`. Con los CJPs compartidos que hay en los datos, eso significa que hoy quien
  entra con el CJP `1` ve las recetas verdes de siete farmacias ajenas. El agujero es anterior a
  este trabajo, pero se cierra acá: `getMyPharmacies`, `getGreenDispensations` y
  `controlDispensation` rechazan a los QF marcados.
- El lookup público de CJP devuelve solo nombre y apellido.
- `POST /api/prescriptions/paper` ignora la `pharmacyId` del body: la resuelve del usuario logueado,
  o la valida contra la franquicia si es admin de cadena.
- El QF solo ve y firma dispensaciones de farmacias con su CJP (ya implementado).
- Se endurece por rol el Excel de controlados
  (`/api/dispensations/controlled-medications/excel`), que quedó en `authenticated()` desde julio.

---

## Testing

**Unitarios (backend)**

- `PharmaceuticalDirectorServiceImplTest`: resolve cuando el QF existe (no pisa datos), cuando no
  existe (crea + registra usuario), y rollback si el security-api falla.
- `PaperPrescriptionServiceTest`: dedupe de médico por CJP, dedupe de paciente por documento, flags
  anti-notificación seteados, código generado único, `origin = 'PAPER'`.
- `PharmacyServiceImplTest` actualizado para el nuevo resolve.

**Migración**

Backfill idempotente (correrlo dos veces no duplica) + verificación de conteos.

**E2E en PRE**

Farmacia da de alta un QF nuevo → el QF entra con la clave inicial y se registra → una segunda
farmacia con el mismo CJP lo selecciona sin pisarlo → carga de receta verde en papel → aparece en el
Libro Negro y en el listado del QF con su Nº → el QF la firma → export a Excel. Con verificación
explícita de que no se generó ningún WhatsApp (tabla `whatsapp_message` y consola de Twilio).

---

## Orden de implementación

Cuatro planes encadenados:

1. **Backend del QF** — tabla, backfill, lookup por CJP, resolve, `/me`, `/register`, corrección de
   `buildQfName`.
2. **Formularios de alta del D.T.** — las cuatro pantallas de Farmacias y Gestión.
3. **App QF** — pantalla de registro, guard, y el Nº en el listado.
4. **Mantenimiento de Libro Negro** — endpoint de carga de papel, pantalla, anulación, columna en el
   Excel.

El 4 depende del 1 solo por el `origin`/`paperNumber` del schema; los demás son secuenciales.
