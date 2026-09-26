# Spec: QF — acceso por invitación y validación de farmacias — 2026-08-24

## Origen

Reporte de Pablo: al reasignar la clave de un QF desde Gestión, la pantalla muestra
«Error interno del servidor». Al investigarlo apareció un problema de fondo más grande, y
dos pedidos de producto que dependen de él.

## Hallazgo medido (2026-08-24)

El log de PRE, sobre `POST /api/pharmaceutical-directors/332211/reassign-password`:

```
ERROR GlobalExceptionHandler: HttpClientErrorException$NotFound: 404
  "answer":"User not found." (security-api-recetalia)
  at PharmaceuticalDirectorRegistrationServiceImpl.reassignPassword:295
```

El login del QF se deriva del CJP (`{cjp}@qf.recetalia.com`, `qf.email-domain` en
`application.yml`). El api-rest pide al security-api renovar la clave de ese usuario, el
usuario no existe, y el 404 no está manejado: sale como 500.

Contraste de ambas bases (consultado directamente, 2026-08-24):

| | QF totales | con `validatedAt` | usuarios `@qf.recetalia.com` en `securitydb.users` |
|---|---|---|---|
| **PRE** | 224 | 224 (221 el 02-ago de un saque) | **5** — y son de prueba (12345, 777001, 777002, 888500, 999999) |
| **PROD** | 221 | 221 (todos el 12-ago) | **0** |

De los 224 QF de PRE, **3 tienen email cargado y 1 tiene celular**.

**Consecuencia:** en producción la bandeja de Gestión afirma «Estos químicos ya tienen
usuario y pueden entrar a su app» y **ninguno de los 221 puede entrar**. Reasignarles la
clave da 500, y habilitarlos da «ya está habilitado» porque `validatedAt` está seteado.
No hay ningún camino por la UI para salir de ese estado.

## Causa raíz

El estado «habilitado» vive en `recetali_receta.pharmaceutical_director.validatedAt` y el
usuario de login vive en `securitydb.users` — **dos almacenes sin integridad entre sí**.
El código asume la invariante `validatedAt ≠ null ⇒ existe el usuario`, que sólo se cumple
si el QF pasó por `validate()`. Los 221/224 se cargaron por SQL, salteando ese camino.

- **Por qué ningún chequeo lo agarró:** no hay ninguno. Ni manejo del 404 en el adapter,
  ni test que cubra el caso, ni contraste de consistencia entre los dos esquemas.
- **Qué lo agarraría la próxima:** que la bandeja deje de *afirmar* el estado de acceso y
  pase a *consultarlo* — el defecto se vuelve visible donde ocurre, en vez de aparecer como
  un 500 cuando alguien intenta operar.

## Decisiones tomadas (Pablo, 2026-08-24)

| Eje | Decisión |
|---|---|
| Cómo obtiene el QF su clave | Link de un solo uso por mail para definirla él |
| Qué hace `reassign-password` ante el 404 | Crea el usuario ahí mismo con esa clave (upsert) |
| Cuándo valida sus farmacias | Obligatorio al primer ingreso, bloqueante |
| Los 221 sin correo | Gestión los carga de a poco; sin import masivo |
| Reenvío del mail | Automático sólo la primera vez + botón «Reenviar invitación» |
| Farmacia rechazada | Se corta el vínculo y queda visible en Gestión; sigue operando |
| Expiración del link | 7 días para invitación, 6 h para recuperación (hoy 6 h para todo) |
| Pruebas de envío de mail | **Sólo contra casillas nuestras** — allowlist por configuración |

## Diseño

### Parte 0 — Fix del 500 y cierre de clase

1. `reassignPassword` captura el 404 de `renewPasswordBack` y hace `registerUserBack` con
   la misma clave. Loguea en WARN: tener que crear el usuario ahí es señal de
   desincronización, no un caso normal.
2. **security-api**: endpoint nuevo para consultar en lote qué usernames existen. Hoy no
   hay ninguno (`SecurityController` sólo expone register/login/renew/reset/refresh).
3. **Gestión**: columna **Acceso** (sí/no) en la bandeja de habilitados, alimentada por ese
   endpoint. Los 221 de PROD van a aparecer en «no», que es la verdad.
4. Test de `reassignPassword` cubriendo el 404 → crea usuario.

### Parte 1 — Invitación por mail al cargar el correo

El choque a resolver: `users.email` es `UNIQUE NOT NULL` y `requestReset` manda el mail a
`user.getEmail()`, que para el QF es la dirección sintética `{cjp}@qf.recetalia.com`. Poner
el correo real ahí chocaría con el `UNIQUE` (un QF que además es médico, dos QF que
comparten casilla). Por eso el mail lo manda el api-rest, no el security-api.

- **security-api** — `POST /request-reset-back`: genera el token y **lo devuelve**, sin
  enviar mail. Mismo patrón «Back» que `registerBack` y `renew-passwordBack`, que ya
  existen para los caminos internos. TTL configurable por request (default 6 h).
- **api-rest** — en `updateContact()`, al guardar un correo: si el QF nunca completó su
  registro (`registeredAt IS NULL`), crea el usuario si falta, pide el token con TTL de 7
  días, arma `https://qf.recetalia.com/registro?code=<token>` y envía la plantilla nueva
  `email.templates.qf-validation`. El precedente exacto de plantilla es `medic-validation`.
- **Reenvío**: automático sólo la primera vez. Endpoint + botón «Reenviar invitación» en la
  bandeja para el resto.
- **app QF** — `/registro` acepta `?code=`: define la clave contra `/reset-password` y sigue
  con el registro (Nº de talonario) que ya existe. La pantalla está hecha; se le agrega la
  entrada por token.

Texto del mail (pedido de Pablo, adaptado al HTML de las otras plantillas):

> Hola {{name}},
> Gracias por ser parte de Recetalia.
> Tu usuario de Químico Farmacéutico fue validado.
> Podés ingresar en el siguiente link: {{link}}
> Si tenés consultas, no dudes en escribirnos a hello@recetalia.com
> ¡Saludos!

### Parte 2 — El QF valida sus farmacias

- **Tabla nueva** `pharmaceutical_director_pharmacy_decision`: QF, farmacia,
  `ACCEPTED|REJECTED`, `decidedAt`. Las farmacias que declaran su CJP y no tienen fila son
  las pendientes — no se materializa el estado «pendiente», así no hay filas que
  sincronizar cuando aparece una farmacia nueva. Sin motivo de rechazo (YAGNI).
  ⚠️ El api-rest **no usa Flyway** y corre con `ddl-auto: none`: la tabla se crea por DDL
  manual en las dos bases, como el resto del esquema de este proyecto.
- **Gate de primer ingreso**: mismo molde que el `registeredGuard` que ya existe en la app
  QF. Si el QF no tomó ninguna decisión todavía, va a la pantalla de validación y no puede
  seguir. Después, las farmacias nuevas aparecen en una sección permanente, sin bloquear.
- **Al rechazar**: se corta el vínculo (`pharmacy.pharmaceuticalDirectorId = NULL`), la
  farmacia queda visible en Gestión como «sin QF válido» y sale **un solo mail** a
  hello@recetalia.com con la lista completa de esa tanda
  (`email.templates.qf-pharmacy-rejection`).
- **`managerCJP` no se toca**: es lo que la farmacia declaró, y es la evidencia de la
  discrepancia que Gestión necesita para llamar a alguien. Los campos `manager*` ya están
  documentados en `Pharmacy.java` como copia derivada; la fuente de verdad es la FK.

Texto del mail de rechazo (pedido de Pablo):

> El {{qf}} rechazó la o las siguientes farmacias:
> {{lista de nombres}}

### Parte 3 — Allowlist de destinatarios (transversal a las Partes 1 y 2)

Restricción de Pablo: los envíos de mail se validan **únicamente contra casillas nuestras**.
No se implementa como disciplina de prueba sino como guard en el envío, porque el disparador
es un flujo de la app (un operador carga un correo) y no una prueba manual.

- Propiedad `email.allowlist` (lista de direcciones y/o dominios) + `email.allowlist.enabled`.
- Con el allowlist activo, todo destinatario fuera de la lista se **loguea y se descarta**,
  sin enviar. Activo en PRE; en PROD se desactiva cuando Pablo lo habilite.
- Aplica a las plantillas nuevas de este spec. No se cambia el comportamiento de los mails
  que ya existen (médicos, farmacias, dispensaciones) para no alterar producción.

## No-objetivos

- No se bloquea a la farmacia rechazada: sigue dispensando normalmente.
- No se hace import masivo de correos de QF.
- No se migra el padrón de 221: se cargan a demanda desde la bandeja.
- No se cambia la semántica del login sintético `{cjp}@qf.recetalia.com`.
- No se toca el flujo de mail de médicos/farmacias/dispensaciones existente.

## Riesgo que queda vivo

Hasta que se le cargue el correo o se le reasigne clave, **ningún QF de PROD puede entrar**.
Este trabajo no lo arregla: lo hace visible (columna Acceso) y destrabable (fix del
reassign + invitación). El vaciado de esa cola es trabajo operativo de Gestión.

## Medidor de cierre

- `reassign-password` sobre un QF sin usuario devuelve 200 y el usuario queda creado
  (test automatizado, y verificable en PRE contra un CJP real).
- La bandeja de Gestión muestra `Acceso = no` para los QF sin usuario en `securitydb`.
- Un QF con correo cargado recibe el link, define su clave y entra (validado **contra una
  casilla nuestra**, nunca contra un QF real).
- Un QF con farmacias pendientes no puede saltear la pantalla de validación.
- Una farmacia rechazada queda con `pharmaceuticalDirectorId = NULL` y aparece en Gestión.
