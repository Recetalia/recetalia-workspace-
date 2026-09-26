# QF — Mi Perfil y habilitación por invitación — Implementation Plan

Origen: `RC - QF.docx` (4 pedidos de Pablo, 2026-09-02). Rama única en los 3 repos:
**`feat/qf-perfil-y-habilitacion`**. Continúa
[2026-08-24-qf-acceso-y-validacion-farmacias-plan.md](2026-08-24-qf-acceso-y-validacion-farmacias-plan.md)
(releases 2.4.0 / 2.4.1, en PROD y PRE).

## Estado y decisiones

- **2026-09-02** — El docx trae 4 capturas, una por pedido; resuelven la ambigüedad del punto 1
  (el recuadro rojo marca el párrafo de la solapa «Pendientes de habilitación», no otro).
- **2026-09-02 — Pablo** — punto 1: **borrar el párrafo entero**, no reemplazarlo.
- **2026-09-02 — Pablo** — punto 2: sin correo cargado, el modal de habilitar **pide el correo**
  (prellenado si ya está) **más una confirmación del correo**, y habilita + invita en un paso.
  Descartadas: bloquear el botón, y habilitar sin mandar mail.
- **No mergear a `2.x.y` ni tocar PROD sin OK explícito de Pablo.**

## Alcance

| # | Pedido | Proyectos |
|---|---|---|
| 1 | Sacar el texto de «Pendientes de habilitación» | gestión |
| 2 | Habilitar deja de asignar clave y manda la invitación por mail | gestión + api-rest |
| 3 | **Bug**: el celular no se prellena en `qf/registro` | qf-app |
| 4 | «Mi Perfil» en el menú del QF, con celular y mail editables | qf-app + api-rest |

## Hallazgo medido — punto 3, causa raíz (2026-09-02)

**El dato nunca fue el problema.** El QF de la captura (CJP `0129836`) **sí tiene el celular
guardado** en PROD — `{"international":"+598 94 462 626", ...}`, leído por
`GET /api/pharmaceutical-directors/validated` con el usuario de Gestión. La pantalla igual salía
vacía con sólo «+598».

**Causa raíz:** `angular-phone-number-input` renderiza su caja de texto como
`<input type="number">` (verificado en el template de la librería). `extractValues` le saca el
prefijo al `international` y le pasa el resto **con los espacios del formato**; el navegador
descarta todo valor que no sea un número válido y deja el input en `""`. El estado interno del
componente es correcto — lo que se pierde es el render.

Medido sobre el DOM real, escribiendo directo en el input:

| Valor | `input.value` resultante |
|---|---|
| `94462626` | `94462626` |
| `' 94 462 626'` | `""` |

⚠️ **El primer experimento dio un falso «los espacios no importan»** y casi manda el diagnóstico
para otro lado. El motivo: el widget escribe al DOM con `[(ngModel)]`, que difiere el `setValue`
a un microtask, así que **con una sola pasada de detección de cambios el input queda vacío aunque
el valor sea correcto**. Con 2 pasadas, el número sin espacios aparece. Cualquier test sobre este
widget necesita la segunda pasada, o mide otra cosa — está encapsulado en `renderCompleto()` de
`registro.component.spec.ts`.

**Por qué no lo cazó nada:** la app QF no tenía ningún test sobre `/registro` (es literalmente
DT-5 del plan anterior), y el spec de `toPhonePayload` cubre sólo la dirección de salida
(formulario → payload), nunca la de entrada (guardado → formulario).

**Cierre de la clase:** `shared/utils/phone-input.util.ts` (`toPhoneInput`), con spec propio, es
el único camino para prellenar un teléfono en esta app. Antes cada pantalla lo resolvía a su
manera: médicos con un `.replace(/\s+/g,'')` suelto
(`medics-recetalia-app/.../profile.component.ts:127`), el QF sin resolverlo. «Mi Perfil» del
punto 4 era la cuarta oportunidad de equivocarse igual.

## Cómo se mide el avance

Misma definición de «hecho» que el plan anterior (D1 test que falla antes y pasa después · D2
suite en verde · D4 desplegado y verificado en PRE · D5 doc en el mismo commit). Las fases que
mandan mail suman **D6: verificado contra una casilla nuestra**.

⚠️ **El allowlist de mail sigue ACTIVO en PRE**: los envíos a correos que no sean
`@recetalia.com` o `pbl.mendez@gmail.com` se descartan con un WARN, y la UI igual dice que la
invitación salió. Para probar el punto 2 en PRE hay que usar una casilla de la lista.

## Checklist

- [x] **Punto 1** — Sacar el texto · D2 ✓ D4 ✓ D5 ✓
- [~] **Punto 2** — Habilitar por invitación · D1 ✓ D2 ✓ D4 ✓ D5 ✓ · **D6 bloqueado por DT-7**
- [x] **Punto 3** — Bug del celular · D1 ✓ D2 ✓ D4 ✓ D5 ✓
- [x] **Punto 4** — Mi Perfil · D1 ✓ D2 ✓ D4 ✓ D5 ✓

Commits: `recetalia-api-rest@44ec908` · `gestion-recetadigital-app@130328f` ·
`qf-recetalia-app@bdc4938`, todos en `feat/qf-perfil-y-habilitacion`. **Sin mergear a `2.x.y`.**

### Medido al cerrar (2026-09-02)

| Proyecto | Suite | Baseline en HEAD limpio |
|---|---|---|
| `recetalia-api-rest` | **309** tests, 0 fallos | 285 antes de este trabajo |
| `gestion-recetadigital-app` | 15/15 en los specs de QF | DT-2 sigue: 18 rojos preexistentes en el resto |
| `qf-recetalia-app` | **23 SUCCESS / 2 FAILED** | **11 SUCCESS / 2 FAILED** (medido con `git stash`) |

Los 2 rojos de la app QF son DT-3, atribuidos con medición y no por suposición. De este
trabajo: **cero**.

### D4 — verificado en PRE el 2026-09-02

Contra la API de PRE, **por dentro del server** (`172.18.0.12:8092`): el nginx del `.98` está
caído y no hay ingress — ver abajo. La API de PRE escucha en **8092**, no 8094.

| Qué | Resultado |
|---|---|
| `validate` sin correo cargado | **400** — «no tiene correo cargado: no hay a dónde mandarle la invitación» |
| `validate` con correo mal formado | **400** — «no tiene formato válido» |
| `validate` con correo permitido (`pbl.mendez@gmail.com`) | Crea el usuario de login ✓, pide el token ✓, llama al mailer ✓ → **el mail muere en el SMTP (DT-7)** |
| Estado tras ese fallo | `validatedAt` **NULL** y `email` **NULL**: la transacción revirtió limpio. **Nadie queda «habilitado» sin haber recibido el link** |
| Allowlist | Dejó pasar `pbl.mendez@gmail.com` (llegó hasta el transversal), como corresponde |

Datos de prueba creados y **borrados** al terminar (CJP `9990001` + su usuario en `securitydb`).
No se tocó el QF real pendiente de PRE (Daniel Carbajal, `@iwtg.com` — fuera del allowlist).

Marcadores en los bundles desplegados, **cada uno con su control positivo** (si el control da 0,
lo roto es la técnica y no el deploy):

| App | Marcador | Esperado | Medido |
|---|---|---|---|
| Gestión | «Pendientes de habilitaci» *(control+)* | >0 | **2** |
| Gestión | «hacerles llegar por fuera del sistema» *(punto 1)* | 0 | **0** |
| Gestión | «Confirmá el email» *(punto 2)* | >0 | **4** |
| Gestión | «Anotala antes de confirmar» *(modal viejo)* | 0 | **0** |
| QF | «Mis farmacias» *(control+)* | >0 | **2** |
| QF | «Mi Perfil» *(punto 4)* | >0 | **1** |
| QF | «Guardar cambios» *(punto 4)* | >0 | **1** |
| QF | `p{Z}` — el regex de `toPhoneInput` *(punto 3)* | >0 | **1** |

## PRE estaba sin ingress — diagnosticado y RESUELTO (2026-09-02)

`recetalia-nginx` del `.98` estaba en crash loop: vivía **1,8 s**, salía con código 1,
`RestartCount = 134` **antes** de este deploy. Nada escuchaba en 80/443 → ninguna URL `*pre`
respondía, tampoco `pre.ape.org.uy` ni los `pre` de DoctorConsultas/DoctorSuite.

Descartado **con medición**, no por descarte mental:

| Sospechoso | Cómo se descartó |
|---|---|
| La config | `nginx -t` con los volúmenes reales montados: `syntax is ok / test is successful` |
| Los certificados | Los 6 que piden las confs existen y vencen entre el 11/10 y el 29/11/2026 |
| Un puerto ocupado | Nada escuchaba en 80/443, ni contenedor ni proceso del host |
| Este deploy | Los 134 reinicios son anteriores |
| El disco | 11 GB libres (81 %) |
| Los vhosts de PROD en el `.98` *(mi hipótesis inicial)* | **Falsa.** Un contenedor de diagnóstico con la MISMA imagen, los MISMOS volúmenes y las MISMAS confs corrió 90 s sin problema |
| `60-ape.conf` como archivo regular en vez de symlink | Ruido: el contenido es idéntico al del host (mismo md5) |

**Arreglado con `docker compose up -d --force-recreate --no-deps nginx`.** El contenedor viejo
arrastraba estado propio en su capa de escritura; qué exactamente **no se pudo aislar**, porque
el `--force-recreate` se llevó el overlay antes de que pudiera diffearlo. Queda como causa no
identificada — lo honesto es decirlo, no inventarla.

⚠️ `docker compose up nginx` en el `.98` **arrastra a `recetalia-site`**, cuyo contexto de build
(`/opt/recetalia/recetalia-site`) no existe en ese server. Hay que usar `--no-deps`.

### Lo que el arreglo rompió, y que es el hallazgo que vale

El `--force-recreate` dejó a `pre.ape.org.uy` en **502 `ape-aplicacion-1 could not be resolved`**.
Motivo: el nginx del `.98` es el ingress de **cuatro** productos, y las redes de los otros tres
(`ape-net`, `compose_dc-net`, `doctorsuite-net`) estaban conectadas **a mano** con
`docker network connect` — estado no declarado en ningún lado. Cualquier recreate las perdía.

**Clase cerrada** en `deploy-recetalia@5d9f7ae`: las tres van declaradas como `external: true` en
`docker-compose.dev98.yml`, que es el override que **sólo** carga el `.98` (en el compose base
abortaría el `up` del `.217`, que no tiene esas redes).

**Verificado inyectando la operación que causaba el defecto**: tras un
`docker compose up -d --force-recreate --no-deps nginx`, el contenedor vuelve con las 4 redes
solo, y los 7 vhosts responden **200** — incluido `pre.ape.org.uy`.

| URL | http |
|---|---|
| `apipre.recetalia.com/recetalia-api-rest/api/especialities` | 200 |
| `gestionpre` · `qfpre` · `farmaciaspre` · `medicospre` · `prestadorespre` `.recetalia.com` | 200 |
| `pre.ape.org.uy` | 200 |
| `qfpre.doctorconsultas.com` | **sin registro DNS**; forzando la resolución al `.98` da 200. Ajeno a esto |

### Verificado por la URL pública, ya con ingress

| Qué | Resultado |
|---|---|
| `POST /pharmaceutical-directors/{cjp}/validate` sin correo, vía `apipre.recetalia.com` | **400** con el mensaje nuevo — la cadena Cloudflare → nginx → api-rest sirve el código nuevo |
| Chunk lazy del Home de la app QF (`chunk-UFLY25TG.js`) servido por nginx | 200 · «Mis farmacias» *(control+)* = 2 · «Mi Perfil» = 1 · «Guardar cambios» = 1 |
| Chunk con `toPhoneInput` (`chunk-DYC46WHT.js`) servido por nginx | 200 · `p{Z}` = 1 |

## Corrección a la doc existente

`[[pre-environment-access]]` decía que `external.api.security-api-recetalia` de PRE apuntaba a
PROD. **Ya no**: medido el 2026-09-02, el contenedor de PRE tiene
`EXTERNAL_API_SECURITY_API_RECETALIA=http://security-api-recetalia:8091` y
`EXTERNAL_API_TRANSVERSAL_API_RECETALIA=http://transversal-recetalia-api:8093/api`. Probar los
flujos de registro/clave en PRE **no** toca PROD.

## Lo que queda pendiente

- **D6 del punto 2** — que el mail llegue a una casilla. Bloqueado por **DT-7** (el SMTP de PRE
  devuelve `535 5.7.8 authentication failed`, verificado hoy en el log del transversal). Es
  anterior a este trabajo y afecta también a las altas de médico y farmacia.
- **Click-through a ojo de las 4 pantallas** — el código está verificado servido por nginx (tabla de arriba), pero nadie las miró en el navegador todavía.
- **Consecuencia de diseño a decidir con Pablo:** habilitar ahora **depende del servicio de
  mail**. Antes, con el SMTP roto, Gestión igual podía habilitar (tipeaba una clave); ahora
  falla y no habilita. Es lo correcto —no deja a nadie marcado como habilitado sin acceso— pero
  significa que **si el SMTP se cae, nadie se puede habilitar**. En PRE eso es hoy el estado.

## Cierre en producción — 2026-09-03

**Release `2.5.0`**, mergeado a `main` y tageado en los 4 repos (`recetalia-api-rest`,
`gestion-recetadigital-app`, `qf-recetalia-app`, `deploy-recetalia`), pusheado. Los otros repos
del workspace siguen en 2.4.x — **el número volvió a quedar desalineado**, igual que después de
2.4.1; unificarlo es trabajo aparte.

Desplegado en el `.217` (rsync + `docker compose build` + `up -d --no-deps` de los 3 servicios).
**El nginx de PROD no se tocó** (Up 6 semanas). Ese server es sólo Recetalia: su nginx está en
una única red, así que el fix de redes del `.98` no aplica ahí.

| Verificación en PROD | Resultado |
|---|---|
| `api` · `gestion` · `qf` · `farmacias` · `medicos` `.recetalia.com` | **200** |
| Gestión: «Pendientes de habilitaci» *(control+)* / texto viejo / «Confirmá el email» / modal viejo | **2 / 0 / 4 / 0** |
| QF: «Mis farmacias» *(control+)* / «Mi Perfil» / `p{Z}` de `toPhoneInput` | **2 / 1 / 1** |
| `validate` sin correo | **400** con el motivo |

### D6 — CERRADO. El mail sale de verdad (lo que PRE no dejó probar)

Con el allowlist **apagado** en PROD (`EMAIL_ALLOWLIST_ENABLED=false`, verificado en el `.env` y
en el contenedor), se habilitó un QF de prueba contra **una casilla propia** —
`pbl.mendez@gmail.com`, nunca un QF real:

```
INFO PharmaceuticalDirectorInvitationService : El QF 9998887@qf.recetalia.com no tenia usuario
     de login: se crea al invitarlo
INFO PharmaceuticalDirectorInvitationService : Invitacion generada para el QF 9998887 ->
     pbl.mendez@gmail.com
INFO ...RegistrationServiceImpl              : QF 9998887 habilitado por Gestion, invitacion
     enviada a pbl.mendez@gmail.com
```

`validatedAt` sellado (`2026-09-03 00:49:27`), correo persistido, usuario creado en `securitydb`,
y **0 errores en el transversal**. O sea que el SMTP de PROD funciona y la cadena entera anda —
justo lo contrario que en PRE (DT-7).

🧹 **Dato de prueba VIVO en PROD**: CJP **9998887** («PRUEBA INVITACION»), habilitado y visible en
la solapa «Habilitados» de Gestión. Se dejó a propósito para que Pablo pueda clickear el link del
mail y validar `/definir-clave` end-to-end. **Borrarlo con** `bash /tmp/d6.sh limpiar` en el
`.217` (borra la fila y su usuario en `securitydb`).

### Lo que sigue sin validarse

- **Click-through a ojo** de las 4 pantallas, en PRE o en PROD. El código está verificado servido,
  pero nadie las miró en el navegador.
- **El link de la invitación** (`/definir-clave?code=`) por el camino nuevo — depende de que Pablo
  abra el mail.
