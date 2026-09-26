# QF y recetas en papel — Todo lo pendiente

Estado al 2026-08-01. Consolida lo que falta de las tres features, más un cambio de alcance nuevo y la deuda que apareció trabajando.

**Nada está mergeado ni pusheado. Producción no fue tocada.**

---

## Cambio de alcance nuevo: Gestión valida a los QF

**Lo que pidió Pablo:** un QF nuevo no puede entrar a la app hasta que **Gestión lo valide**, y **la clave se la asigna Gestión**, no la farmacia. En el primer ingreso el QF la cambia a su gusto.

Esto **modifica** lo que ya está construido y probado — no es un agregado.

### Qué cambia respecto de lo hecho

| Hoy | Nuevo |
|---|---|
| La farmacia carga la clave inicial del QF en el formulario | **Se saca ese campo.** La farmacia solo declara CJP, nombre, apellido y documento |
| El QF nace con usuario de login y puede entrar | Nace **sin poder entrar** |
| Nadie aprueba nada | Gestión valida, y al validar asigna la clave |
| Los 220 del backfill están operativos | **Los 220 pasan a pendientes de validación** |

### El modelo

Se agrega `pharmaceutical_director.validatedAt` (timestamp, null = sin validar), espejo del `registeredAt` que ya existe.

**Por qué no un cuarto valor de `status`:** hoy `status` vale `ACTIVE` / `INACTIVE` / `NEEDS_REVIEW`, y un QF puede perfectamente estar sin validar **y** tener el CJP compartido. Con un enum habría que definir precedencias y el código se llena de casos. Con dos campos independientes la regla es una línea:

```
opera  ⟺  status = 'ACTIVE'  ∧  validatedAt IS NOT NULL  ∧  registeredAt IS NOT NULL
```

Los tres bloqueos son ortogonales y cada uno tiene su propio mensaje para el usuario:

| Estado | Qué ve el QF |
|---|---|
| `validatedAt` null | "Tu cuenta todavía no fue habilitada por Recetalia" |
| `status = NEEDS_REVIEW` | "Tu CJP figura con más de un titular. Contactate con Recetalia" |
| `registeredAt` null | Cae en `/registro` a completar sus datos y su clave |

### ⚠️ La consecuencia que hay que mirar de frente

Son **220 validaciones a mano** antes de que el módulo QF le sirva a nadie. Si la bandeja las presenta de a una, es inviable. **La pantalla tiene que permitir validar en lote**: seleccionar varias filas y aprobarlas juntas, generando una clave por cada una.

Además hay que resolver **cómo le llega la clave a cada QF**. Hoy la farmacia se la daba en mano; ahora la asigna Gestión, que no tiene contacto con él. Es una decisión abierta: que Gestión se la comunique a la farmacia, que se genere una y se muestre para copiar, o mandarla por email si el QF cargó uno.

---

## Lo que tenemos que hacer, en orden

### Fase 1 — Cerrar lo que está a medias

**1.1 Validar la carga de recetas en papel en DEV.** El backend está con 156 tests pero **nunca se ejecutó una carga real**. Cargar una receta por API y verificar: que no dispara notificaciones, que aparece en el Libro Negro, en el listado del QF y en el Excel con su Nº, y que la anulación deja todo en `CANCELLED` sin borrar. *(Es el Plan 4a Task 6, ya escrito.)*

**1.2 Plan 4b — la pantalla de carga.** "Mantenimiento de Libro Negro" en Farmacias: formulario con buscador DNMA, listado de lo cargado, anulación, y el Nº en la columna Código del Libro Negro. **Sin esto la feature 2 no existe para el usuario.**

### Fase 2 — La validación por Gestión

**2.1 Backend.** Columna `validatedAt` + migración que deja los 220 en pendiente. Endpoint de validación (uno y en lote) que asigna la clave. `currentQf()` y el registro exigen `validatedAt`. Y sacar `managerPassword` de `resolveForPharmacy`: el QF nace sin usuario de login, que se crea recién al validar.

**2.2 Los dos formularios de farmacia.** Sacar el campo de clave inicial del registro de Farmacias y del modal de Gestión. El resto del lookup por CJP queda igual.

**2.3 La bandeja de Gestión.** Hoy lista solo los `NEEDS_REVIEW`. Pasa a tener dos solapas: **Pendientes de validación** (con selección múltiple y validación en lote) y **En revisión por CJP**, que es lo que ya existe.

**2.4 La app del QF.** Mensaje propio para el QF sin validar, distinto del de CJP en revisión.

### Fase 2.bis — Infraestructura de correo

**El servidor SMTP cambió: `mail01.iwtg.com` → `mail.iwtg.com`.** Hay que actualizarlo donde esté configurado. Buscar en `transversal-recetalia-api` (que es quien manda los emails), en el `.env` de `deploy-recetalia`, y en `recetalia-site/mailer/`.

Toca más de lo que parece: por ahí salen el email de bienvenida de farmacia, el de validación de perfil, el de anulación de dispensación y el formulario de contacto del sitio. **Y el de anulación es bloqueante**: `DispensationService.cancel` rethrowea si el envío falla, así que con el SMTP mal configurado no se puede anular ninguna dispensación. Es exactamente lo que impidió validar la anulación de recetas de papel en DEV.

Aprovechar para revisar el pendiente viejo del buzón `hello@recetalia.com`, que acepta correo pero rebota porque no es un buzón real.

### Fase 3 — Seguridad

Ninguna la introdujo este trabajo; todas aparecieron mientras lo hacíamos.

**3.1 `GET /api/dispensations/search` no valida `pharmacyId`.** Mismo agujero que ya cerramos en el Excel de controlados, pero en el Libro Negro: cambiando el id en la URL se ven las dispensaciones de otra farmacia.

**3.2 `@EnableMethodSecurity` no existe** → los 4 `@PreAuthorize` del proyecto nunca se evalúan. **Corregir esos cuatro antes de activarla**: hoy usan prefijo simple y los tokens traen doble, así que activarla de golpe deja afuera a la app de prestadores y al usuario-API.

**3.3 Rotar la password de la base en DigitalOcean.** Salió del `application.yml`, pero sigue en el historial de git.

**3.4 Rate limit en nginx** sobre el lookup público de CJP: es un padrón iterable sin autenticación.

**3.5 Rotar el `jwt.secret`**, hoy hardcodeado y compartido con el security-api. Requiere coordinar los dos servicios a la vez.

### Fase 4 — Datos y decisiones de Pablo

**4.1 Curar los 19 CJPs** (`qf-cjps-a-curar.csv`) — bloquea a 65 de 337 farmacias.

**4.2 El NBSP del CJP `56130`**: es un falso positivo (misma persona, un espacio de no separación). Limpiar los 2 registros, o normalizar en la query — que obliga a tocar backfill y recálculo, que deben quedar idénticos.

**4.3 El `documentValidator` muerto**: en las dos apps lee `idNumber`/`idType` pero los formularios usan `manager*`, así que el documento del D.T. no se valida. Activarlo puede empezar a rechazar altas que hoy pasan.

**4.4 El encoding.** La conexión JDBC escribe UTF-8 dentro de columnas `latin1`: cualquier nombre con acento se corrompe al guardarse. Afecta a toda la plataforma, no solo a esto. Es la razón por la que hay que probar el registro del QF con un nombre sin tildes.

### Fase 5 — Release

En este orden, y ninguno antes que el anterior:

1. Pablo prueba las pantallas en PRE.
2. **Crear el remoto de `qf-recetalia-app`** — hoy ese repo existe solo en su máquina, no hay nada que taggear.
3. Mergear las cuatro ramas (requiere su OK explícito).
4. Push y tag **2.2.0** en los nueve repos.
5. **Correr la migración en la base de producción ANTES de deployar.** Al revés se rompen el dashboard, el Libro Negro y el listado del QF a la vez: 22 queries del dashboard ahora dependen de `prescription.origin`.
6. Deploy al `.217`.

---

## Lo que Pablo tiene que probar en PRE

Cuatro cosas, dos minutos cada una. Todo en el `.98`.

| # | Dónde | Qué |
|---|---|---|
| 1 | `farmaciaspre.recetalia.com/register/` | CJP `999999` → verde y campos ocultos · `000000` → pide clave inicial · `1` → rojo y botón bloqueado |
| 2 | `gestionpre` → Farmacias → editar ALBISU | El aviso rojo sale solo al abrir el modal, Guardar bloqueado |
| 3 | `gestionpre` → Farmacias → Químicos | 20 filas; la del CJP `1` con 7 farmacias y 6 titulares |
| 4 | `qfpre.recetalia.com` → CJP `999999` / `Recetalia2026!` | Cae en `/registro`, ve sus 3 farmacias, no puede salir sin completar |

⚠️ La prueba 4 **cambia la clave del QF de prueba** — anotá cuál ponés. Y **usá un nombre sin acentos**, o vas a reproducir el bug de encoding.

⚠️ Las pruebas 1 y 2 quedan **obsoletas** cuando se haga la Fase 2: el campo de clave inicial desaparece. Vale probarlas igual para validar el lookup, que se queda.

---

## Estado de lo hecho

| | |
|---|---|
| Feature 1 — Registro del QF | Backend, los 2 formularios, pantalla del QF y bandeja. **Cambia con la Fase 2** |
| Feature 3 — Nº de talonario | Backend y listado del QF. Falta en Libro Negro y Excel (van en el 4b) |
| Feature 2 — Recetas en papel | Backend hecho **pero sin validar**. Pantalla sin empezar |

**Ramas vivas:** `recetalia-api-rest` → `feat/qf-registro-y-papel` (apila sobre `feat/qf-control-recetas-verdes`, tampoco mergeada) · `farmacias-recetalia-app` y `gestion-recetadigital-app` → `feat/qf-lookup-cjp` · `qf-recetalia-app` → `feat/qf-registro-app`, **sin remoto**.
