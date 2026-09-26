# Runbook — pasaje a PRODUCCIÓN del trabajo de QF (release 2.3.0)

**Servidor:** `.217` (`159.203.26.217`) · **Rol de deploy:** `app` · **Fecha prevista:** 2026-08-27

Este documento es operativo: se sigue paso a paso. Cada paso trae su verificación, y los que
no se pueden deshacer están marcados.

## Decisiones tomadas (Pablo, 2026-08-27)

| Eje | Decisión |
|---|---|
| Mail en PROD | **Allowlist ON al arrancar** (`@recetalia.com`), validar contra hello@, y recién ahí apagarlo |
| Alcance | Entra también `medics-recetalia-app` |
| Integración | Merge a `2.x.y` + fast-forward de `main` + **tag `2.3.0`** |

`2.3.0` y no `2.2.2`: hay features nuevas (invitación del QF, validación de farmacias), no
sólo arreglos.

## Qué se publica — 26 commits, 7 repos

| Repo | Commits | Lo grueso |
|---|---:|---|
| `recetalia-api-rest` | 11 | invitación del QF, columna Acceso, validación de farmacias, contacto del QF, mensajes de error 500→400 |
| `gestion-recetadigital-app` | 6 | columna Acceso, editar contacto, reenviar invitación, farmacias sin químico |
| `farmacias-recetalia-app` | 4 | contacto del QF sólo si el CJPPU no existe, confirmar email, celular |
| `deploy-recetalia` | 2 | allowlist de mail, `QF_REGISTRATION_URL` |
| `security-api-recetalia` | 1 | `request-reset-back`, `users-exist-back`, **token de reset de 32 bytes** |
| `qf-recetalia-app` | 1 | definir clave por link, validar farmacias |
| `medics-recetalia-app` | 1 | un fallo de la API ya no se ve como «no tenés recetas» |

⚠️ **Arrastra trabajo del 18–20 de agosto que nunca llegó a producción**, no sólo lo de esta
semana. Todo está corriendo en PRE desde entonces.

## Precondiciones — verificadas el 2026-08-27

| Qué | Estado |
|---|---|
| Disco del `.217` | **130 GB libres** (17 % usado). Sin el riesgo que tumbó el `.98` |
| Tabla `..._pharmacy_decision` en PROD | **no existe** → hay que correr el DDL |
| `pharmacy.id` en PROD | `latin1_swedish_ci` → el DDL en latin1 es el correcto |
| MySQL de PROD | 8.0.45 ≥ 8.0.16 → el `CHECK` **sí** se aplica |
| Ramas pusheadas | las 7, sí |
| Suites | api-rest 291 ✅ · security-api 22 ✅ · fronts: sólo fallos preexistentes |

---

## Paso 1 — Red de seguridad: etiquetar las imágenes actuales

**Hacer esto ANTES de buildear.** El deploy sobrescribe el tag `:latest`; sin esto no hay a qué
volver si algo sale mal.

```bash
ssh root@159.203.26.217
for s in recetalia-api-rest security-api-recetalia gestion-recetadigital-app \
         qf-recetalia-app farmacias-recetalia-app medics-recetalia-app; do
  docker tag registrypre.recetadigital.uy/recetalia/$s:latest \
             registrypre.recetadigital.uy/recetalia/$s:pre-2.3.0
done
docker images | grep pre-2.3.0    # esperado: 6 líneas
```

**Verificación:** 6 imágenes etiquetadas. Si falta alguna, parar.

## Paso 2 — DDL en la base de PROD

Va **antes** del deploy: la tabla es nueva y aditiva, y la versión vieja de la app la ignora.

```bash
scp recetalia-api-rest/doc/migrations/2026-08-24-qf-pharmacy-decision.sql root@159.203.26.217:/tmp/
ssh root@159.203.26.217
cd /opt/recetalia/deploy-recetalia && set -a && . ./.env && set +a
H=$(echo "$RECETALIA_DB_URL" | sed -E 's#.*//([^:/]+).*#\1#')
P=$(echo "$RECETALIA_DB_URL" | sed -E 's#.*//[^:/]+:([0-9]+)/.*#\1#')
docker run --rm -v /tmp/2026-08-24-qf-pharmacy-decision.sql:/q.sql mysql:8.0 \
  sh -c "mysql -h'$H' -P'$P' -u'$RECETALIA_DB_USER' -p'$RECETALIA_DB_PASSWORD' --ssl-mode=REQUIRED < /q.sql"
```

**Verificación — declarar una restricción no es activarla. Se prueba violándola:**

```sql
-- 1) las 5 constraints
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE FROM information_schema.TABLE_CONSTRAINTS
 WHERE TABLE_SCHEMA='recetali_receta' AND TABLE_NAME='pharmaceutical_director_pharmacy_decision';
-- esperado: PRIMARY, uk_qf_pharmacy, fk_qf_decision_director, fk_qf_decision_pharmacy, ck_qf_decision_value

-- 2) el CHECK se aplica → ESPERADO: ERROR 3819
INSERT INTO pharmaceutical_director_pharmacy_decision
  (id, pharmaceuticalDirectorId, pharmacyId, decision, decidedAt)
  SELECT UUID(), d.id, p.id, 'CUALQUIER_COSA', NOW(6)
    FROM pharmaceutical_director d, pharmacy p LIMIT 1;

-- 3) la FK se aplica → ESPERADO: ERROR 1452
INSERT INTO pharmaceutical_director_pharmacy_decision
  (id, pharmaceuticalDirectorId, pharmacyId, decision, decidedAt)
  VALUES (UUID(), 'no-existe', 'tampoco', 'ACCEPTED', NOW(6));

-- 4) quedó vacía
SELECT COUNT(*) FROM pharmaceutical_director_pharmacy_decision;   -- esperado: 0
```

Si el paso 2 falla, **no seguir**: el deploy sin la tabla rompe la pantalla del QF.

## Paso 3 — Configuración del `.env` de PROD

Las 4 variables están **ausentes** hoy; el compose les da default. Se declaran explícitas para
que nadie tenga que deducirlas, y el allowlist arranca **activo** por decisión de Pablo.

```bash
ssh root@159.203.26.217
cd /opt/recetalia/deploy-recetalia
cp .env .env.bak-pre-2.3.0-$(date +%Y%m%d)
cat >> .env <<'ENV'

# ── Release 2.3.0 — QF ────────────────────────────────────────────────
# ⚠️ VENTANA CORTA Y DELIBERADA: con el allowlist activo NINGÚN mail de
# producción sale a nadie externo — tampoco las altas de médico ni de
# farmacia. Está así sólo para ver el mail de invitación del QF una vez
# (nunca se pudo probar: el SMTP de PRE está roto). APAGARLO apenas se
# valide — es el paso 7 de este runbook.
EMAIL_ALLOWLIST_ENABLED=true
EMAIL_ALLOWLIST_RECIPIENTS=@recetalia.com
QF_REGISTRATION_URL=https://qf.recetalia.com/definir-clave
QF_EMAIL_DOMAIN=qf.recetalia.com
ENV
grep -E "^EMAIL_ALLOWLIST|^QF_" .env
```

## Paso 4 — Merge y tag (⚠️ no se deshace fácil)

En los **7** repos. `medics-recetalia-app` merge desde `fix/listado-recetas-error-visible`;
los otros 6 desde `feat/qf-acceso-y-validacion-farmacias`.

⚠️ **`deploy-recetalia` NO tiene rama `main`** (verificado 2026-08-27): su bucle va aparte,
sin el fast-forward. Meterlo con los otros hace fallar el `checkout main` a mitad de camino,
con parte de los repos ya mergeados.

```bash
cd /Users/pablo/iwtg/recetalia-workspace

# Los 5 que sí tienen main
for r in recetalia-api-rest security-api-recetalia gestion-recetadigital-app \
         qf-recetalia-app farmacias-recetalia-app; do
  git -C $r checkout 2.x.y
  git -C $r merge --no-ff feat/qf-acceso-y-validacion-farmacias \
      -m "Merge feat/qf-acceso-y-validacion-farmacias — release 2.3.0 (acceso del QF por invitación, validación de farmacias y mensajes de error)"
  git -C $r checkout main && git -C $r merge --ff-only 2.x.y
  git -C $r tag -a 2.3.0 -m "release 2.3.0"
  git -C $r push origin 2.x.y main 2.3.0
done

# deploy-recetalia: sólo 2.x.y
git -C deploy-recetalia checkout 2.x.y
git -C deploy-recetalia merge --no-ff feat/qf-acceso-y-validacion-farmacias \
    -m "Merge feat/qf-acceso-y-validacion-farmacias — release 2.3.0"
git -C deploy-recetalia tag -a 2.3.0 -m "release 2.3.0"
git -C deploy-recetalia push origin 2.x.y 2.3.0

# medics, desde su propia rama
git -C medics-recetalia-app checkout 2.x.y
git -C medics-recetalia-app merge --no-ff fix/listado-recetas-error-visible \
    -m "Merge fix/listado-recetas-error-visible — release 2.3.0"
git -C medics-recetalia-app checkout main && git -C medics-recetalia-app merge --ff-only 2.x.y
git -C medics-recetalia-app tag -a 2.3.0 -m "release 2.3.0"
git -C medics-recetalia-app push origin 2.x.y main 2.3.0
```

**Verificación:** `git -C <repo> describe --tags` devuelve `2.3.0` en los 7.

**Simulado el 2026-08-27 con `git merge-tree` (dry-run, no toca el árbol): los 7 merges entran
limpios, sin conflictos**, y `main` está sincronizado con `2.x.y` en los 5 que la tienen — o sea
el `--ff-only` va a funcionar.

## Paso 5 — Deploy al `.217`

**Usar `scripts/deploy.sh`, NO `rsync` a mano.** El script excluye `registry/auth/htpasswd`,
`.env.bak*`, los dumps y los vhosts de otros productos, y hace un `--dry-run` que pide
confirmación antes de borrar. El rsync manual del infra-map no trae esos excludes y el
2026-08-24 rompió el registry del `.98`.

```bash
cd /Users/pablo/iwtg/recetalia-workspace/deploy-recetalia
DEPLOY_ROLE=app ./scripts/deploy.sh root@159.203.26.217
```

Si el script no cubre el build, buildear **serial** en el server (los frontends en paralelo
agotan la RAM):

```bash
ssh root@159.203.26.217 'cd /opt/recetalia/deploy-recetalia && \
  for s in recetalia-api-rest security-api-recetalia gestion-recetadigital-app \
           qf-recetalia-app farmacias-recetalia-app medics-recetalia-app; do
    echo "== $s =="; docker compose build $s || break
  done'
```

⚠️ **`recetalia-site` sólo existe en PROD**: no lo saques del `up`, pero tampoco lo rebuildeés
si no cambió.

```bash
ssh root@159.203.26.217 'cd /opt/recetalia/deploy-recetalia && \
  docker compose up -d recetalia-api-rest security-api-recetalia gestion-recetadigital-app \
                       qf-recetalia-app farmacias-recetalia-app medics-recetalia-app'
```

## Paso 6 — Verificación post-deploy

```bash
# 1) todo arriba
ssh root@159.203.26.217 'docker ps --format "{{.Names}}\t{{.Status}}" | grep -E "recetalia|gestion|qf-|farmacias|medic"'

# 2) el fix del 500 (el bug que originó todo) — elegir un CJP con Acceso = No
TOKEN=$(curl -s -X POST https://api.recetalia.com/security-api-recetalia/api/auth/loginBack \
  -H 'Content-Type: application/json' \
  -d '{"email":"gestion@recetalia.com","password":"<clave>","info":"455"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['answer']['token'])")

curl -s -w "\nHTTP %{http_code}\n" -X POST \
  "https://api.recetalia.com/recetalia-api-rest/api/pharmaceutical-directors/<CJP>/reassign-password" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"password":"<clave>"}'
# ESPERADO: 200. Antes de este release: 500.

# 3) la columna Acceso responde (los 221 de PROD deberían dar "No")
curl -s "https://api.recetalia.com/recetalia-api-rest/api/pharmaceutical-directors/validated" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json; r=json.load(sys.stdin)['answer']
print(len(r),'habilitados ·',sum(1 for x in r if x.get('hasLogin') is True),'con acceso')"

# 4) mensaje de email duplicado → 400, no 500
curl -s -X POST https://api.recetalia.com/recetalia-api-rest/api/pharmacies \
  -H 'Content-Type: application/json' -d '{"name":"x","email":"<email ya usado>"}'
# ESPERADO: 400 con "Faltan datos obligatorios…" o "ya está en uso"

# 5) las apps
for u in gestion farmacias medicos qf; do
  curl -s -o /dev/null -w "$u → %{http_code}\n" https://$u.recetalia.com/
done
```

## Paso 7 — Validar el mail y APAGAR el allowlist

**El paso que no se puede olvidar.** Mientras el allowlist esté activo, ningún mail de
producción llega a nadie externo.

1. En Gestión, cargarle a un QF de prueba el correo `hello@recetalia.com`.
2. Verificar que el mail llega y que **el link funciona**: tiene que apuntar a
   `https://qf.recetalia.com/definir-clave?code=…` (si apunta a `qfpre`, el `.env` quedó mal).
3. Con eso validado:

```bash
ssh root@159.203.26.217 'cd /opt/recetalia/deploy-recetalia && \
  sed -i "s/^EMAIL_ALLOWLIST_ENABLED=true/EMAIL_ALLOWLIST_ENABLED=false/" .env && \
  grep ^EMAIL_ALLOWLIST_ENABLED .env && \
  docker compose up -d recetalia-api-rest'
```

4. Confirmar que un mail normal vuelve a salir (un alta de médico de prueba).

## Rollback

| Si falla en… | Cómo se vuelve |
|---|---|
| Paso 2 (DDL) | `DROP TABLE pharmaceutical_director_pharmacy_decision;` — está vacía, no hay dato que perder |
| Paso 4 (merge/tag) | `git reset --hard <sha previo>` en `2.x.y` y `main`, `git tag -d 2.3.0` + `git push --delete origin 2.3.0` |
| Paso 5–6 (deploy) | volver a las imágenes del paso 1: `docker tag …:pre-2.3.0 …:latest` y `docker compose up -d <servicios>` |

La tabla nueva puede quedar sin molestar a la versión vieja: nadie la lee.

## Riesgos conocidos

1. **El mail de invitación nunca se vio renderizado.** Lo cubre el paso 7, que existe
   exactamente por eso.
2. **Ventana con los mails de producción frenados** entre el paso 3 y el 7. Cuanto más corta,
   mejor: no dejarla de un día para el otro.
3. **Los 221 QF de PROD siguen sin poder entrar** después del release. Esto no lo arregla: lo
   hace visible (columna Acceso) y destrabable (reasignar clave / invitación). Vaciar esa cola
   es trabajo operativo de Gestión.
4. **`farmacias.recetalia.com/register` cambia de comportamiento**: el contacto del QF ya no se
   pide cuando el CJPPU está registrado. Avisar a quien atienda altas.
5. El `.217` tiene origin-lock de Cloudflare: **no se le pega por IP**, sólo por dominio.

## Después del release

- Actualizar `doc/plans/2026-08-24-qf-acceso-y-validacion-farmacias-plan.md`: D3 y D4 de PROD.
- Actualizar la memoria `infra-map` con la versión que corre en producción (hoy dice 2.1.2).
- Los 8 ítems de deuda (DT-1…DT-8) del plan siguen abiertos.
