# Formulario de carga de receta — especificación para replicar

Documento de handoff para un equipo que ya integró con la API de Recetalia y ahora
quiere replicar la pantalla de emisión de recetas en su propia UI.

Describe el formulario **tal como está hoy** en `medics-recetalia-app`, más el
contrato real que la API acepta. Donde los dos no coinciden, está marcado.

Relevado el 2026-09-15 sobre `medics-recetalia-app` y `recetalia-api-rest`.

---

## 1. El flujo, en dos pasos

La pantalla es más simple de lo que sugiere el dominio. Son dos pasos y un botón:

```
┌────────────────────────────────────────────────────────────┐
│  Nueva receta                                              │
│                                                            │
│  Paciente  [ Seleccionar o Crear Paciente          ▾ ]     │
│            └─ busca desde 3 caracteres                     │
│               por nombre, apellido o documento             │
│               + Crear paciente nuevo                       │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ IBUPROFENO 400 mg — Lab. Roemmers                    │  │
│  │ 1 comprimido cada 8 horas durante 6 días   [✎] [🗑]  │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ OMEPRAZOL 20 mg — genérico                           │  │
│  │ 1 cápsula cada 24 horas durante 6 días     [✎] [🗑]  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│            [ + Agregar medicamento ]                       │
│                                                            │
│                                      [   Prescribir   ]    │
└────────────────────────────────────────────────────────────┘
```

**Un paciente, N medicamentos.** Cada medicamento es una tarjeta editable y
eliminable. El botón `Prescribir` sólo aparece si hay paciente elegido **y** al
menos un medicamento cargado.

**Importante:** cada medicamento es **una receta independiente**. No existe el
concepto de "receta con varios ítems" en el modelo de datos. Lo único que une a los
medicamentos de una misma consulta es el prefijo del campo `code` (ver §6).

---

## 2. Paso 1 — Paciente

Único campo de cabecera. No hay diagnóstico, ni fecha, ni centro asistencial, ni
notas a nivel receta.

| | |
|---|---|
| Control | Dropdown con filtro de texto |
| Placeholder | `Seleccionar o Crear Paciente` |
| Dispara la búsqueda | a partir de **más de 2 caracteres** |
| Endpoint | `GET /api/patients/search?name={q}&lastName={q}&document={q}` |
| Comportamiento | el mismo texto va a los tres parámetros; `document` sólo se agrega si el texto es numérico. En la práctica: busca por nombre, apellido **o** documento indistintamente |
| Label de cada opción | `nombre apellido documento` |
| Opción fija | `+ Crear paciente nuevo` (id `'add'`) → abre el modal de alta de paciente |

---

## 3. Paso 2 — Buscar el medicamento

El modal tiene dos pantallas: primero se busca, y al elegir un resultado aparece el
formulario de posología.

| | |
|---|---|
| Label del input | `Busque por nombre y/o principio activo` |
| Comportamiento | dispara en **cada tecla, sin debounce**, si el texto no está vacío |
| Endpoint | `GET /api/amp/search?prodMspLike={q}` — **público, no requiere token** |
| Respuesta | `GenericResponse<Map<String, AMPResponse>>` — es un **mapa indexado por id**, no un array. Hay que hacer `Object.values()` |

**Los resultados se agrupan en dos secciones** según si el item trae `labName`:

- `MEDICAMENTOS COMERCIALES` — tiene `labName`
- `MEDICAMENTOS GENERICOS` — `labName` viene null

**Color de fondo por condición de venta** (`condvtaId`):

| `condvtaId` | Color |
|---|---|
| `11` | verde |
| `12` | naranja |

### Mapeo del resultado elegido al payload

| Campo de `AMPResponse` | Va a |
|---|---|
| `id` | `productId` |
| `productType` | `productType` → `"AMP"` (comercial) \| `"VMP"` (genérico) |
| `name` | `productName` |
| `substanceName` | `substanceName` |
| `dosificationUnit` | `doseUnit` **y también** `dosificationType` |
| `dosificationType` (`VOLUME`\|`QUANTITY`) | `doseType` |
| `labId` | `dnmaLaboratoryId` |
| `condvtaId` | `condvtaId` |

Sí, `dosificationUnit` y `dosificationType` están cruzados respecto de lo que
sugieren sus nombres. Ver §8.

---

## 4. Paso 3 — Posología

Lo que el médico realmente carga: **tres números y dos textos opcionales.**

```
┌─────────────────────────────────────────────────────┐
│  IBUPROFENO 400 mg                                  │
│  Ibuprofeno · Lab. Roemmers                         │
│                                                     │
│  ☐ Crónico                                          │
│                                                     │
│  Indicaciones   [  1  ]  comprimidos                │
│  Frecuencia     [  8  ]  Horas                      │
│  Duración       [  6  ]  Días                       │
│                                                     │
│  ▸ Datos adicionales                                │
│      Afecciones    [                            ]   │
│      Antecedentes  [                            ]   │
│                                                     │
│                                  [   Agregar   ]    │
└─────────────────────────────────────────────────────┘
```

**No hay ni un solo `<select>` en este formulario.** Las tres unidades no se
eligen:

- la de **dosis** la impone el catálogo DNMA (`dosificationUnit` del medicamento),
- la de **frecuencia** es siempre horas,
- la de **duración** es binaria, según el checkbox `Crónico`.

| Label | Control | Campo | Default | Restricciones del control |
|---|---|---|---|---|
| `Crónico` | checkbox | `isCronic` | `false` | cambia labels y unidad de duración |
| `Indicaciones` | number | `dose` | `1` | `min=0.5`, `step=0.5` |
| *(texto fijo al lado)* | read-only | `doseUnit` | — | del catálogo |
| `Frecuencia` | number | `frecuency` | `8` | `min=1` |
| `Horas` *(sufijo fijo)* | read-only | `frecuencyUnit` | `"HOUR"` | no editable |
| `Duración` / `Hasta` | number | `duration` | `6` normal / `8` crónico | `min=1` |
| `Días` / `Meses` *(sufijo)* | read-only | `durationUnit` | `"DAYS"` / `"Meses"` | según checkbox |
| `Afecciones` | textarea | `affections` | `''` | opcional, dentro del accordion "Datos adicionales" |
| `Antecedentes` | textarea | `medicalHistory` | `''` | opcional, mismo accordion |

Botón: `Agregar` (o `Guardar` si se está editando una tarjeta existente).

### Validaciones del formulario

| Regla | Efecto |
|---|---|
| `dose < 0.5` | se fuerza a `1` |
| `dose` no múltiplo de 0.5 | se redondea al 0.5 más cercano |
| `frecuency < 1` | se fuerza a `1` |
| `duration < 1` | se fuerza a `1` |
| Tildar `Crónico` | `duration = 8` — **pisa lo que el médico haya escrito** |
| Destildar `Crónico` | `duration = 6` — ídem |
| Antes de enviar | si `durationUnit === "Meses"` → fuerza `isCronic = true` |

**No hay campos obligatorios.** Todo son inputs con valor por defecto precargado, así
que se puede emitir una receta sin tocar nada: dosis 1, cada 8 horas, 6 días.
Tampoco hay máximos.

---

## 5. Valores literales — las cuatro trampas

Son los que un integrador no adivina y hacen fallar la primera prueba.

| Campo | Qué viaja | Detalle |
|---|---|---|
| `frecuencyUnit` | `"HOUR"` | constante, nunca cambia. La API acepta texto libre (50 chars), así que `"horas"` también funciona |
| `durationUnit` | `"DAYS"` o **`"Meses"`** | **inglés cuando no es crónico, español cuando sí.** Mezcla intencional, no es un error tipográfico |
| `status` | `"PENDING"` | el modal lo arma como `"AVAILABLE"` y **lo pisa** justo antes del POST |
| `frecuency`, `isCronic` | — | se escriben así, con el typo. Está consolidado en el contrato, no lo corrijas |

El `"DAYS"` / `"Meses"` es el que más problemas da.

---

## 6. Lo que el cliente calcula solo

Todo esto hay que replicarlo — no lo genera el servidor cuando se usa
`POST /api/prescriptions`.

| Campo | Cómo se genera |
|---|---|
| `code` | GUID v4 generado en el browser, **truncado a 6 caracteres, en mayúsculas**, + `-` + una letra correlativa por ítem (`String.fromCharCode(65 + i)`). Primer medicamento `-A`, segundo `-B`… Ejemplo: `A3F91C-A`, `A3F91C-B`. **Todos los medicamentos de la misma consulta comparten el prefijo de 6 caracteres** — es la única atadura entre ellos |
| `expireAt` | `now + 45 días`, ISO string. Se calcula **al agregar el medicamento**, no al emitir |
| `status` | `"PENDING"`, inyectado en el submit |
| `patientId` | inyectado en el submit desde el paciente elegido |
| `isCronic` | re-forzado a `true` si `durationUnit === "Meses"` |
| `dateTimeToSend` | existe en el modelo pero **nunca se envía** |

### El envío

Un `POST /api/prescriptions` **por medicamento**, en un loop.

---

## 7. Qué exige la API de verdad

Esto es lo que importa para que la réplica no acepte datos que la API después
rechaza. **Advertencia: ninguno de los endpoints de alta lleva `@Valid`**, así que
las anotaciones de validación del backend no se evalúan. Lo que sigue son los
obligatorios *reales* — por `NOT NULL` en base o por validación manual en el código.

| Campo | Obligatorio real | Límite / valores |
|---|---|---|
| `productType` | **SÍ** | `"AMP"` \| `"VMP"`. El servidor sólo compara contra `"VMP"`; **cualquier otra cosa se trata como AMP**. `varchar(8)` |
| `productId` | **SÍ** | id DNMA. `varchar(40)` |
| `frecuency` | **SÍ** — validación manual | entero `> 0`. Si falta o es ≤0 → **400** con `"La receta debe incluir la frecuencia de la posología (frecuency)."` |
| `frecuencyUnit` | **SÍ** — validación manual | no vacío, texto libre, 50 chars. Si falta → **400** con `"La receta debe incluir la unidad de frecuencia de la posología (frecuencyUnit)."` |
| `status` | **SÍ** | `varchar(255)`. Valores del sistema: `AVAILABLE`, `DISPENSED`, `CANCELLED`, `DISPENSED_BY_PROVIDER`. **No se valida en el alta** |
| `duration` | condicional | si `isCronic=true` y `duration` es null → **500** |
| `dose` | no | `decimal(5,1)` |
| `doseUnit` | no | texto libre, 50 chars (`"mg"`) |
| `doseType` | no | texto libre, 50 chars. **Sin enum**, pese al nombre |
| `durationUnit` | no | 50 chars. `"Meses"` (case-insensitive) **fuerza `isCronic=true`** |
| `medicalHistory` | no | 500 chars |
| `affections` | no | 500 chars |
| `dnmaLaboratoryId` | no | entero, persiste |
| `condvtaId` | no | **el backend lo guarda como String tal cual**. Mandar el valor de base: `"11"` / `"12"`. La traducción desde `GREEN`/`ORANGE` está comentada en el código |

### Campos que la API acepta e **ignora**

No hace falta mandarlos, y mandarlos no tiene efecto:

| Campo | Qué pasa |
|---|---|
| `code` | **lo pisa el servidor** en `upsert-and-create`. En `POST /api/prescriptions` sí hay que mandarlo |
| `medicId` | ignorado — el médico sale del token |
| `patientId` | ignorado en `upsert-and-create` — sale del documento del paciente |
| `dateTimeToSend` | **pisado** con `Instant.now()` |
| `substanceName` | **aceptado y nunca leído.** No se persiste; en las lecturas se deriva del DNMA |
| `expireAt` | se respeta **sólo si `isCronic=false`**. Si es crónica, se pisa (ver §9) |

---

## 8. Tres defectos conocidos — decidir si replicar o corregir

Están en el código actual del app de médicos. Si el objetivo es paridad exacta hay
que replicarlos; si el objetivo es una integración limpia, conviene no arrastrarlos.

1. **`medicId` lleva el id del medicamento, no el del médico.**
   El modal escribe `medicId: selectedMedicine?.id` — el mismo valor que `productId`.
   **Sin consecuencia práctica:** el backend ignora `medicId` y resuelve el médico
   desde el JWT. Pero es dato basura en el request.

2. **`dosificationType` y `doseType` están cruzados.**
   El `'VOLUME'`/`'QUANTITY'` del catálogo va a `doseType`; en `dosificationType` va la
   unidad en texto. Los nombres sugieren lo contrario.

3. **Sin validación de obligatorios en el front.**
   Ver §4. Combinado con que el backend tampoco evalúa `@Valid`, la única red que
   queda son las dos validaciones manuales de frecuencia y los `NOT NULL` de base.

---

## 9. Recetas crónicas — la semántica que hay que entender

`isCronic = true` **no** crea una receta larga: crea **N recetas**, donde
`N = duration`.

- El front, al tildar `Crónico`, pone `duration = 8` y `durationUnit = "Meses"`.
  Eso genera **8 recetas**.
- Cada una vence escalonada: `now + i * 40 días` para la i-ésima. El `expireAt` que
  mandes se ignora.
- Los `code` salen `<PREFIJO>-A1`, `-A2`, … en vez de `-A`.
- La respuesta trae las N en el array `answer`.

Es el mecanismo de tratamiento prolongado: una receta por mes de tratamiento, cada
una dispensable en su ventana.

---

## 10. Endpoints

### Alta de receta

| Ruta | Body | Cuándo usarlo |
|---|---|---|
| `POST /api/prescriptions/upsert-and-create` | `{ medic, patient, prescription }` | **El de integración.** Da de alta médico y paciente si no existen, genera el `code`, crea la receta |
| `POST /api/prescriptions` | `PrescriptionRequest` plano | El que usa el app de médicos. El médico sale del token; hay que generar el `code` propio |

**Claves de upsert en `upsert-and-create`:**

- **Médico:** por `medic.email`. Si no existe, lo crea — y le registra usuario en el
  servicio de seguridad. `medic.especialityId` es obligatorio en la práctica: si no
  existe o viene null → **404**. `medic.medicalProviderId` se ignora y se fuerza al
  del token.
- **Paciente:** por `patient.document.number` + `patient.document.type`. Si no existe,
  lo crea.

### Autorización

```
POST /api/prescriptions/upsert-and-create
  → ROLE_MEDICAL_PROVIDER  o  ROLE_MEDICAL_PROVIDER_API
```

JWT HS512 en `Authorization: Bearer <token>`. El token debe traer un claim `mail`
que resuelva a un prestador existente; si no, **404**.

### Respuesta del alta

HTTP 200 siempre que haya salido bien:

```json
{
  "status": "SUCCESS",
  "answer": [ { "id": "...", "code": "A3F91C-A", "status": "AVAILABLE",
                "expireAt": "...", "link": "...", "productId": "...", "…": "…" } ],
  "applicationProvider": "recetalia-api-rest",
  "metadata": null,
  "serverDateTime": "2026-09-15T12:00:00.000"
}
```

`answer` es **siempre una lista** — un elemento, o N si la receta es crónica.

⚠️ En el alta, `ampDsc`, `vmpDsc` y `substanceName` vienen **null**: el enriquecimiento
contra DNMA sólo ocurre en los GET.

### Buscar el medicamento

| Ruta | Params | Auth | Campo que va a `productId` |
|---|---|---|---|
| `GET /api/amp/search` | `prodMspLike` | **pública** | `id` del `AMPResponse`. Trae además `productType`, `dnmaLaboratoryId` y `condvtaId` en el mismo response — **es la que conviene** |
| `GET /api/dnma/amp/search` | `description`, `page=0`, `size=20` | autenticada | `id` del `AmpDnmaDto` |
| `GET /api/dnma/amp/{id}` | path | autenticada | — |

### Errores

| Situación | HTTP | Cuerpo |
|---|---|---|
| Falta `frecuency` o `frecuencyUnit` | 400 | `GenericResponse` con el mensaje literal |
| Email o valor único duplicado | 400 | `"El email X ya está en uso..."` |
| Falta un query param | 400 | `"Falta un parámetro requerido"` |
| Especialidad / localidad / prestador inexistente | 404 | mensaje del recurso |
| Paciente ya existe | **409** | ⚠️ **no** viene como `GenericResponse` — es el body de error por defecto de Spring |
| Cualquier otra cosa | 500 | `"Error interno del servidor"` |

---

## 11. Payload de ejemplo

`POST /api/prescriptions/upsert-and-create`

```json
{
  "medic": {
    "email": "medico@ejemplo.com",
    "name": "Ana",
    "lastname": "Pérez",
    "especialityId": "3",
    "document": { "number": "12345678", "type": "CI" },
    "status": "ACTIVE"
  },
  "patient": {
    "name": "María",
    "lastname": "González",
    "document": { "number": "87654321", "type": "CI" },
    "birthdate": "1980-01-01",
    "sex": "F"
  },
  "prescription": {
    "productType": "AMP",
    "productId": "100421000179106",
    "dose": 1,
    "doseUnit": "comprimido",
    "doseType": "QUANTITY",
    "frecuency": 8,
    "frecuencyUnit": "HOUR",
    "duration": 6,
    "durationUnit": "DAYS",
    "isCronic": false,
    "status": "AVAILABLE",
    "condvtaId": "11",
    "dnmaLaboratoryId": 188,
    "affections": "",
    "medicalHistory": ""
  }
}
```

---

## 12. Nota sobre la documentación existente

`recetalia-api-rest/doc/specs/api-contract.md` **no cubre el alta de recetas**: no
menciona ninguno de los dos endpoints de creación, ni los DTOs, ni las claves de
upsert, ni los roles, ni la semántica de `isCronic`. Este documento cubre ese hueco
para el caso de uso de emisión; si el integrador necesita dispensaciones o QF, eso sí
está allá.
