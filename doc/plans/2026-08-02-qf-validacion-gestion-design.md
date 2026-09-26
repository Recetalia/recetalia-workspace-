# Spec: Gestión valida al Químico Farmacéutico y le asigna la clave — 2026-08-02

**Estado:** diseño aprobado por Pablo el 2026-08-02. Sin implementar.

Un QF nuevo no puede entrar a su app hasta que **Gestión lo habilite**, y la clave inicial se la **asigna Gestión**, no la farmacia. Es la Fase 2 del [roadmap](2026-08-01-qf-pendientes-roadmap.md).

**Esto modifica lo ya construido y probado** ([Plan 1](2026-07-31-qf-registro-backend-plan.md), [Plan 2b](2026-07-31-qf-lookup-formularios-plan.md), [Plan 2c](2026-08-01-qf-bandeja-gestion-plan.md)) — no es un agregado.

---

## Por qué

Hoy la farmacia declara el CJP de su QF **y le pone la clave inicial**. Eso significa que cualquiera que dé de alta una farmacia crea, de hecho, un usuario con acceso al módulo de control de recetas verdes de todas las farmacias donde ese CJP figure como D.T. Recetalia no interviene.

El QF es un rol de control: es quien firma el libro de medicamentos controlados. Su acceso tiene que estar habilitado por Recetalia, no por un tercero.

---

## Decisiones tomadas — no las revisites

| Decisión | Quién | Por qué |
|---|---|---|
| **Los 220 QF actuales quedan habilitados por la migración** | Pablo | No se toca nada de ellos. Pablo los contacta aparte para su acceso |
| **La clave la escribe el operador de Gestión** | Pablo | La comunica él por otro medio. No hace falta generarla ni mandarla por mail |
| **Cambio de clave obligatorio en el primer ingreso** | Pablo | La clave que circula por WhatsApp o teléfono deja de servir apenas se usa |
| ~~**Email del QF: opcional**~~ · **REVERTIDO 2026-08-18** | Pablo | ~~Si está, Gestión lo contacta directo; si no, vía la farmacia. **Solo email, no teléfono**: la entidad lo guarda como objeto `Phone` con converter y `PharmacyRequest` no tiene `managerPhone`, así que sumarlo obliga a tocar el tipo embebido y el componente de teléfono del front — desproporcionado para un dato de contacto que además es opcional~~<br><br>**En la release 2.3.0 el email y el celular del QF pasan a obligatorios en el registro de farmacia.** El costo que motivaba el descarte no existía: la columna `pharmaceutical_director.phone` ya estaba creada (`text`, nullable) y vacía en las 223 filas, así que no hizo falta migración ni tocar el converter — sólo sumar `managerPhone` al DTO. Lo que sí faltaba era la vía para los **221 QF ya habilitados sin email**, que nunca pasaron por un formulario que se los pidiera: se resolvió con `POST /api/pharmaceutical-directors/{cjp}/contact` y un modal "Editar contacto" en la bandeja. Detalle en [2026-08-18-qf-contacto-obligatorio-plan.md](2026-08-18-qf-contacto-obligatorio-plan.md) |
| **Reset de clave desde la misma bandeja** | Pablo | Mismo modal, mismo endpoint. Sin él no hay salida operativa cuando un QF pierde la clave |
| **`validatedAt` y no un cuarto valor de `status`** | Diseño | Un QF puede estar sin validar **y** con CJP colisionado. Con un enum habría que definir precedencias |
| **Validación de a uno, no en lote** | Consecuencia | La clave es manual: el lote no aporta nada |

---

## El modelo

Se agrega **`pharmaceutical_director.validatedAt`** (`TIMESTAMP NULL`, null = sin validar), espejo del `registeredAt` que ya existe.

```
opera  ⟺  status = 'ACTIVE'  ∧  validatedAt IS NOT NULL  ∧  registeredAt IS NOT NULL
```

Los tres bloqueos son **ortogonales** y cada uno tiene su propia causa:

| Estado | Significa | Se resuelve |
|---|---|---|
| `validatedAt` null | Recetalia todavía no lo habilitó | Gestión lo valida |
| `status = NEEDS_REVIEW` | Su CJP figura con más de un titular | Curación de CJPs (Plan 2a) |
| `registeredAt` null | No completó sus datos | El QF entra a `/registro` |

### Migración

```sql
ALTER TABLE pharmaceutical_director ADD COLUMN validatedAt TIMESTAMP NULL;
UPDATE pharmaceutical_director SET validatedAt = NOW();
```

**Todos los existentes quedan validados**, incluidos los 19 en `NEEDS_REVIEW` — que siguen bloqueados por su `status`, que es lo correcto: son cosas distintas. Nadie pierde el acceso que tiene hoy.

⚠️ `ddl-auto: none`: la migración se aplica **a mano**, y **antes** de deployar el código.

---

## El cambio central: cuándo nace el usuario de login

Hoy [`PharmaceuticalDirectorRegistrationServiceImpl.resolveForPharmacy`](../../recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java) (línea ~65) exige `managerPassword` y llama a `securityApiRecetaliaPort.registerUser(...)` en el acto.

| | Hoy | Nuevo |
|---|---|---|
| Alta de farmacia con CJP nuevo | Crea el QF **+ su usuario de login** | Crea el QF **sin usuario de login** |
| Alta con CJP existente | Reusa el QF tal cual | Igual, sin cambios |
| Validación desde Gestión | No existe | Crea el usuario con la clave tipeada, `mustChangePassword = true` |

Se elimina el bloque que exige `managerPassword` y la llamada a `registerUser`. El campo sale de `PharmacyRequest`.

### La consecuencia que simplifica el alcance

Como el usuario de login **no existe** hasta que Gestión valida, un QF sin validar **no puede ni intentar entrar**: el login falla en el security-api porque no hay tal usuario.

Eso **elimina la Fase 2.4 del roadmap**: no hay que programar el mensaje *"tu cuenta todavía no fue habilitada"* en la app del QF, porque nunca llega a esa pantalla. Una pieza menos, y ninguna regla de negocio duplicada entre servicios.

---

## Los flujos

### A — Alta de farmacia con un CJP nuevo

1. La farmacia declara CJP, nombre, apellido, documento y —opcionalmente— el email del QF.
2. Se crea la fila en `pharmaceutical_director` con `validatedAt = NULL` y **sin usuario de login**.
3. El formulario muestra: *"El acceso del Químico Farmacéutico será habilitado por Recetalia."*
4. La farmacia opera normalmente. El QF no bloquea la dispensación.

### B — Validación desde Gestión

1. Solapa **"Pendientes de validación"**: QF con `validatedAt` null, con sus farmacias asociadas y el contacto si lo hay.
2. Acción por fila → modal → el operador tipea la clave → confirma.
3. El backend, en una transacción: `registerUserBack(email, clave, ROLE_PHARMACEUTICAL_DIRECTOR, mustChangePassword=true)` y `validatedAt = NOW()`. **`registerUserBack` y no `registerUser`**: éste último espera la clave cifrada AES (la manda el front del alta de farmacia) y guardaría el texto tipeado tal cual como password.
4. Si el security-api falla, **no se marca `validatedAt`**: no puede quedar un QF "validado" sin poder entrar.
5. Pablo le pasa la clave al QF por el medio que corresponda.

### C — Primer ingreso del QF

Entra con esa clave, el token trae `mustChangePassword = true`, y la app lo obliga a cambiarla antes de usarla. Ya está construido: el campo existe en `TokenResponse`, en `UserRequest`, en la entidad `User` y en la columna `must_change_password`.

### D — Reset de clave

Un QF ya validado muestra **"Reasignar clave"** en la bandeja: el mismo modal, pero por debajo llama a `renewPassword` en vez de `registerUser`, y vuelve a dejar `mustChangePassword = true`.

---

## Qué se toca

| Repo | Qué |
|---|---|
| `recetalia-api-rest` | Columna `validatedAt` + migración · sacar `managerPassword` de `resolveForPharmacy` y de `PharmacyRequest` · campo de email opcional · endpoints de validar y reasignar · `currentQf()` exige `validatedAt` |
| `gestion-recetadigital-app` | Solapa "Pendientes de validación" + modal de clave · sacar el campo de clave del modal de farmacia |
| `farmacias-recetalia-app` | Sacar el campo de clave del registro · agregar email opcional · el aviso del punto A.3 |
| `qf-recetalia-app` | **Nada.** Ver la consecuencia de arriba |

---

## Qué NO se hace

- **Validación en lote** — la clave es manual.
- **Mensaje de "no validado" en la app del QF** — no puede loguear.
- **"Olvidé mi clave"** para el QF — el reset lo hace Gestión.
- **Generar la clave automáticamente** — la escribe el operador.
- **Tocar los 220 existentes** — sólo la migración les pone la fecha.
- **Mandar la clave por email** — la comunica Pablo.

---

## Riesgos

**La migración va antes que el deploy.** Si el código sale primero, `validatedAt` no existe y toda consulta de QF falla. Mismo orden que la migración de `prescription.origin`.

**Un QF que hoy entra y mañana no.** No debería pasar —la migración valida a todos— pero si la migración corre a medias, un QF activo pierde el acceso sin explicación. Verificar `COUNT(*) WHERE validatedAt IS NULL = 0` después de correrla.

**El alta de farmacia es pública.** Sigue siéndolo: cualquiera puede crear una fila en `pharmaceutical_director`. Lo que ya no puede es crear un usuario con acceso. Ese es exactamente el punto de la feature.

**El `resolveForPharmacy` tiene un `catch` que borra el QF si falla el registro del usuario.** Al sacar la creación del usuario, ese catch queda sin sentido y hay que revisarlo: hoy borra la fila recién creada.
