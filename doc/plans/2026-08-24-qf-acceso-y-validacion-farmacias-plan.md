# QF — acceso por invitación y validación de farmacias — Implementation Plan

Spec: [2026-08-24-qf-acceso-y-validacion-farmacias-design.md](2026-08-24-qf-acceso-y-validacion-farmacias-design.md)

## Estado y decisiones

- **2026-08-24** — Diseño aprobado por Pablo. Alcance: todo el spec, no sólo el fix del 500.
- **2026-08-24** — Expiración del link: 7 días invitación / 6 h recuperación (default del agente,
  no objetado).
- **2026-08-24** — REGLA DURA de Pablo: **los envíos de mail se validan únicamente contra casillas
  nuestras**. Implementado como allowlist de destinatarios por configuración (Fase 1), no como
  disciplina de prueba. **Ningún envío real a un QF, médico o farmacia durante este trabajo.**

## Regla dura: orden de los tracks

```
Fase 0 (fix del 500)  →  se puede entregar sola. NO depende de nada de abajo.
Fase 1 (allowlist)    →  BLOQUEA a las fases 3 y 5. Ningún código que envíe mail
                         se mergea antes de que el allowlist exista y esté activo en PRE.
```

El allowlist va **antes** que las plantillas nuevas. Al revés, el primer operador que cargue un
correo en PRE dispara un mail a un QF real, que es exactamente lo que la regla prohíbe.

## Cómo se mide el avance

Definición única de «hecho» por fase. **«Implementado» ≠ «cerrado»:**

| # | Ítem | Verificación |
|---|------|--------------|
| D1 | Test que falla antes del cambio y pasa después | `./gradlew test` / `npm test` del proyecto |
| D2 | Suite completa del proyecto en verde | ídem, sin filtro |
| D3 | DDL aplicado en **las dos** bases (si la fase toca esquema) | consulta de verificación, abajo |
| D4 | Deployado a PRE y verificado ahí | marcador grepeado en el contenedor (ver infra-map) |
| D5 | Doc actualizada en el mismo commit | el diff |

Las fases que envían mail suman **D6: verificado contra una casilla nuestra**, nunca contra un
destinatario real.

### Métrica del árbol

**Caminos del QF que rompen con 500 ante desincronización entre `pharmaceutical_director` y
`securitydb.users` = 0**, y **afirmaciones de estado de acceso sin consultarlo = 0**.

Hoy: 2 (el `reassign-password` que rompe, y la bandeja que afirma «ya pueden entrar»).

### Medidor

```bash
# APIs
cd recetalia-api-rest    && ./gradlew test
cd security-api-recetalia && ./gradlew test
# Fronts
cd gestion-recetadigital-app && npm test -- --watch=false --browsers=ChromeHeadless
cd qf-recetalia-app          && npm test -- --watch=false --browsers=ChromeHeadless
```

Consistencia entre esquemas (operativo, corre contra cada ambiente — ver infra-map para el acceso):

```sql
SELECT COUNT(*) AS qf_habilitados_sin_login
FROM recetali_receta.pharmaceutical_director d
WHERE d.validatedAt IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM securitydb.users u
                  WHERE u.username = CONCAT(TRIM(d.cjp), '@qf.recetalia.com'));
```

Al 2026-08-24: **PRE 219 · PROD 221**. Este plan **no** lleva ese número a 0 — eso es trabajo
operativo de Gestión. Lo que cierra el plan es que ese número sea **visible** (columna Acceso) y
**destrabable** (fix del reassign + invitación), no que sea cero.

## Fases

| Fase | Alcance | Proyectos | volumen |
|---|---|---|---:|
| 0 | Fix del 500 en `reassign-password` (upsert ante 404) | api-rest | S |
| 1 | Allowlist de destinatarios de mail | api-rest | S |
| 2 | Endpoint de existencia de usuarios + columna Acceso | security-api, api-rest, gestión | M |
| 3 | Invitación por mail al cargar el correo | security-api, api-rest, gestión | L |
| 4 | Entrada por token en la app QF (`/registro?code=`) | qf-app | M |
| 5 | Validación de farmacias por el QF | api-rest, qf-app, gestión | L |

Fase 5 es la más grande; su desglose:

| Sub-fase | Alcance | volumen |
|---|---|---:|
| 5a | Tabla `..._pharmacy_decision` + entidad + repo + DDL en ambas bases | S |
| 5b | Endpoints `/me/pharmacies` y POST de decisiones + corte de vínculo | M |
| 5c | Mail de rechazo a hello@recetalia.com (una tanda = un mail) | S |
| 5d | Pantalla de validación + guard bloqueante en la app QF | M |
| 5e | Vista «farmacias sin QF válido» en Gestión | S |

## Riesgos que el plan no resuelve

1. **Los 221 de PROD siguen sin poder entrar** hasta que Gestión les cargue el correo o les
   reasigne clave. Es trabajo operativo, no de código. El plan lo hace visible, no lo vacía.
2. **Doble dueño del estado de acceso.** `validatedAt` y `securitydb.users` siguen siendo dos
   almacenes sin integridad referencial entre sí — son bases distintas, no hay FK posible. La
   columna Acceso lo hace visible; no lo elimina.
3. **El allowlist es un guard de ambiente, no de código.** Si alguien lo desactiva en PRE, los
   mails salen. Queda documentado en el `.env` de los dos servers.

## No-objetivos

- No se bloquea a la farmacia rechazada.
- No se hace import masivo de correos de QF.
- No se migra el padrón de 221.
- No se cambia el login sintético `{cjp}@qf.recetalia.com`.
- No se toca el flujo de mail existente (médicos, farmacias, dispensaciones).
- No se mergea a `2.x.y` ni se deploya a PROD sin OK explícito de Pablo.

## Checklist

**Único dueño del estado de cada fase.** `[x]` sólo con todos los ítems de «hecho» cumplidos.

- [x] **Fase 0** — Fix del 500 · D1 ✓ D2 ✓ D4 ✓ D5 ✓
- [x] **Fase 1** — Allowlist de mail · D1 ✓ D2 ✓ D4 ✓ D5 ✓ (activo en PRE)
- [x] **Fase 2** — Endpoint de existencia + columna Acceso · D1 ✓ D2 ✓ D4 ✓ D5 ✓
- [x] **Fase 3** — Invitación por mail · D1 ✓ D2 ✓ D4 ✓ D5 ✓ **D6 ✓ en PROD (2026-08-27):
  el mail llegó a hello@recetalia.com y Pablo lo confirmó.** El SMTP de PRE sigue roto (DT-7),
  así que la verificación se hizo en producción con el allowlist puesto — que es exactamente
  para lo que se construyó. Lo que sigue abajo era el estado anterior: **el SMTP de PRE tiene
  las credenciales rotas** (`535 authentication failed` en el transversal). Ningún
  mail sale de PRE, ni éste ni las altas de médico/farmacia. No es de este trabajo — ver DT-7.
  Verificado hasta el borde: el link se genera, el mail se arma y llega al sender; lo que no
  se pudo ver es la casilla.
- [x] **Fase 4** — Entrada por token en app QF · D1 n/a D2 ✓ D4 ✓ D5 ✓
- [x] **Fase 5a** — Tabla de decisiones + DDL · D1 ✓ D2 ✓ **D3 ✓ en PRE y en PROD** D5 ✓
- [x] **Fase 5b** — Endpoints de validación de farmacias · D1 ✓ D2 ✓ D4 ✓ D5 ✓
- [~] **Fase 5c** — Mail de rechazo · D1 ✓ D2 ✓ D4 ✓ D5 ✓ · D6: el canal quedó probado con la
  invitación, pero **este mail concreto (a hello@) no se disparó todavía** — hace falta que un
  QF rechace una farmacia.
- [x] **Fase 5d** — Pantalla + guard en app QF · D1 n/a D2 ✓ D4 ✓ D5 ✓
- [x] **Fase 5e** — Vista en Gestión · D1 n/a D2 ✓ D4 ✓ D5 ✓

D1 «n/a» en las fases de front: son componentes y guards nuevos sin lógica propia que un test
unitario distinga de su template; se verifican con el build y en PRE. Es deuda declarada, no
un ítem cumplido — ver DT-5.

### D4 — verificado en PRE el 2026-08-24, contra el dato real

| Qué | Resultado |
|---|---|
| `POST /332211/reassign-password` — **el error reportado por Pablo** | HTTP 200. Antes: 500 |
| ¿Creó el usuario de verdad? | Sí: `users-exist-back` lo devuelve, y **loguea** con rol `ROLE_PHARMACEUTICAL_DIRECTOR` y `mustChangePassword: true` |
| Columna Acceso sobre la bandeja real | 224 habilitados · 6 con acceso · 218 sin · 0 desconocidos. Coincide con la consulta directa a la base |
| Allowlist deja pasar lo permitido | `pbl.mendez@gmail.com` llegó al transversal (y ahí murió por el SMTP) |
| Allowlist **bloquea** lo ajeno | `nadie@dominio-ajeno-de-prueba.test` → `WARN ... NO se envía a [...]`, sin llamar al transversal |
| El fallo de mail NO tumba el guardado | El contacto quedó persistido con la invitación en error. Es el best-effort diseñado |
| Rutas nuevas de la app QF | `/definir-clave?code=` y `/validar-farmacias` → HTTP 200 |
| `GET /pharmacies-without-qf` | HTTP 200, 0 farmacias (nadie rechazó nada todavía) |

**Falso diagnóstico intermedio, anotado para que no se repita:** un `updateContact` respondió
200 y el dato **no quedó**, y por un rato eso se leyó como un bug de la transacción del código
nuevo. No lo era: el disco del `.98` estaba al 100 % y **MySQL crasheaba en pleno `commit`**
(`ERROR 1114: table is full`), con transacciones colgadas y el login en 504. Repetido con
disco libre, el mismo request persiste en 4 s. Ver [[deploy-98-gotchas-medidos]].

### Medido al cerrar la implementación (2026-08-24)

| Proyecto | Tests nuevos | Suite completa |
|---|---:|---|
| `recetalia-api-rest` | 6 archivos / 35 casos | **285** tests, 0 fallos |
| `security-api-recetalia` | 3 archivos / 13 casos | **22** tests, 0 fallos |
| `gestion-recetadigital-app` | 3 casos | 26 SUCCESS / 18 FAILED **preexistentes** (baseline en HEAD limpio: 23/18) |
| `qf-recetalia-app` | 0 | 8 SUCCESS / 2 FAILED **preexistentes** (baseline idéntico) |

Los fallos de los dos fronts se midieron con `git stash` sobre HEAD limpio antes de atribuirlos:
son de este trabajo **cero**.

## Cierre en producción — 2026-08-27

**Release `2.3.0`** (7 repos, 26 commits) + **`2.3.1`** (hotfix, 3 repos). Runbook ejecutado:
[../runbooks/2026-08-27-cutover-qf-a-produccion.md](../runbooks/2026-08-27-cutover-qf-a-produccion.md).

Medido en PROD antes y después, contra el mismo CJP `9876543`:

| Métrica del plan | Antes | Después |
|---|---|---|
| `reassign-password` sobre un QF sin usuario | **500** | **200**, y el QF **loguea** con rol y cambio de clave obligatorio |
| Estado de acceso afirmado sin verificar | 221 filas afirmándolo | 0 — la bandeja lo consulta (221 · 1 con acceso · 0 desconocidos) |
| Duplicado / campos faltantes | 500 «Error interno del servidor» | 400 nombrando la causa |
| Restricciones de la tabla nueva en PROD | no existía | 5, **probadas violándolas** (CHECK→3819, FK→1452) |

**La métrica del árbol quedó en 0**: no queda ningún camino del QF que rompa con 500 ante
desincronización, ni ninguna afirmación de acceso sin consultar.

**Hotfix 2.3.1** — el QF definía su clave por el link y el registro se la volvía a pedir. Raíz:
`resetPassword` no apagaba `mustChangePassword`, y elegir la clave por link *es* cambiarla.
Corregido en las 3 capas y verificado el flujo entero en producción.

**Lo que NO cerró el release:** los 220 QF de PROD siguen sin poder entrar. El plan nunca
prometió vaciar esa cola — la hace visible y destrabable. Es trabajo operativo de Gestión.

🚨 **Pendiente operativo:** el allowlist de mail quedó **activo** en PROD (paso 7 del runbook).
Mientras siga así, ningún mail de producción sale a nadie externo.

## Deuda registrada por este plan

- [ ] **DT-1** — No hay chequeo automático de consistencia entre `pharmaceutical_director` y
  `securitydb.users`. La consulta del medidor existe pero se corre a mano. Un chequeo periódico
  (Dashboard de Control) la haría permanente.
- [ ] **DT-2** — `gestion-recetadigital-app`: **18 tests rotos** en HEAD, anteriores a este
  trabajo. Todos por `NullInjectorError: No provider for HttpClient` en el TestBed de varios
  componentes. Medido el 2026-08-24 con `git stash` sobre HEAD limpio: 18 FAILED / 23 SUCCESS.
  Mientras sigan rojos, la suite de ese proyecto no sirve como gate: un rojo nuevo se pierde
  entre los viejos.
- [ ] **DT-3** — `qf-recetalia-app`: 2 tests rotos en HEAD, misma situación que DT-2.
- [ ] **DT-4** — El schema `recetali_receta` es **latin1 / latin1_swedish_ci**, no utf8mb4
  (verificado en PRE el 2026-08-24 al crear la tabla de decisiones: MySQL rechazó la FK con
  ERROR 3780 por charset incompatible). La tabla nueva se creó en latin1 para poder declarar
  sus FK. Convertir el schema entero es una migración aparte, con su propio plan; hasta
  entonces ningún campo de texto libre de esa base soporta emojis ni caracteres fuera de
  latin1.
- [ ] **DT-5** — Las 4 piezas de front de este plan (pantalla de definir clave, pantalla de
  validación de farmacias, guard, solapa de Gestión) no tienen test unitario propio: se
  verifican por build y a mano en PRE. Los proyectos no tienen tests de componente que sirvan
  de molde, y DT-2/DT-3 dicen por qué.
- [ ] **DT-7** — **El SMTP de PRE está roto**: `535 5.7.8 Error: authentication failed` en
  `transversal-recetalia-api` (credenciales inválidas). Ningún mail sale de PRE, y es anterior
  a este trabajo: afecta también a las altas de médico y de farmacia. Bloquea D6 de las fases
  3 y 5c — no se puede ver el mail en una casilla hasta arreglarlo.
- [ ] **DT-8** — El `.98` llegó a **100 % de disco** durante este deploy (59 GB compartidos con
  DoctorSuite, DoctorConsultas, FHIR y Keycloak). `docker builder prune -af` liberó 16,6 GB,
  pero el daemon reinició durante el prune y se cayeron los 26 contenedores del host —
  levantados a mano. Sin una limpieza periódica de caché, el próximo deploy vuelve a tumbarlo.
- [ ] **DT-6** — `PasswordResetServiceImpl.requestReset` manda el mail con
  `emailDto.setFrom(user.getEmail())`, o sea el `From` es la casilla del destinatario. Es
  anterior a este trabajo y no se tocó (el camino nuevo `/request-reset-back` no manda mail).
  Un `From` que no es un dominio propio se lo come SPF/DKIM y termina en spam.

### Arreglado de paso, porque este plan lo empeoraba

- **Token de reset de 5 caracteres.** `PasswordResetTokenServiceImpl` generaba el token con
  `UUID.randomUUID().toString().substring(0, 5)`: ~1M de combinaciones, sin rate limit
  delante, adivinable a fuerza bruta dentro de su ventana. La invitación del QF lo usa con
  TTL de 7 días, que lo empeoraba dos órdenes de magnitud. Ahora son 32 bytes de
  `SecureRandom` en base64 url-safe, con test que lo fija. **Afecta también al flujo de
  recuperación de clave que ya existía**, para bien.
