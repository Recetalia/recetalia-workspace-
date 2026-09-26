# Guion de pruebas — QF: acceso por invitación y validación de farmacias (PRE)

Ambiente: **PRE**. Desplegado el 2026-08-24. Nada de esto está en producción.

## Leer antes de empezar

**El envío de mails de PRE está roto** (credenciales SMTP inválidas, `535 authentication
failed`). Es un problema anterior a este trabajo y afecta a *todos* los mails del ambiente,
también a las altas de médico y farmacia. Consecuencia para el tester:

> **No esperes recibir ningún mail.** El link que normalmente llegaría por correo está más
> abajo, ya generado. Si un caso dice "se le manda un mail", lo que se verifica es que la
> pantalla no falle y que el botón haga lo suyo — no la llegada.

## Accesos

| Qué | Dónde | Usuario |
|---|---|---|
| Gestión | https://gestionpre.recetalia.com | `gestion@recetalia.com` / `1wtg_p4ss` |
| App del Químico | https://qfpre.recetalia.com | se define en el caso 5 |

Pantalla de Gestión bajo prueba: menú **Químicos Farmacéuticos**, solapa **Habilitados**.

---

## 1 · El error reportado: reasignar clave (lo más importante)

Es el bug que originó todo. Antes mostraba **"Error interno del servidor"** en rojo dentro del
modal.

1. Gestión → Químicos Farmacéuticos → solapa **Habilitados**.
2. Buscar un químico cuya columna **Acceso** diga **No** (hay 218).
3. Botón **Reasignar clave** → escribir una clave (mínimo 8) → **Guardar clave**.

**Esperado:** el modal cierra y aparece en verde *"Clave reasignada al químico …"*.
**Y además:** su columna **Acceso** pasa de **No** a **Sí**. Ese es el punto — antes el
químico figuraba habilitado y no podía entrar con nada.

❌ Si vuelve a aparecer "Error interno del servidor", el caso falla.

## 2 · Columna Acceso

En la solapa **Habilitados**, la columna **Acceso** muestra:

- **Sí** (verde) — tiene usuario, puede entrar.
- **No** (rojo) — figura habilitado pero **no puede entrar**. Al pasar el mouse explica por qué.
- **—** (gris) — no se pudo consultar. No debería aparecer; si aparece siempre, avisar.

**Esperado hoy:** 224 habilitados, ~6 en **Sí**, ~218 en **No**. Es correcto: el padrón se
cargó por base de datos y esos químicos nunca tuvieron usuario.

Es ordenable: clic en el encabezado **Acceso** agrupa los que no pueden entrar.

## 3 · Reenviar invitación

Botón nuevo en cada fila de **Habilitados**.

1. Buscar un químico **sin correo** (columna Email en "—"). El botón tiene que estar
   **deshabilitado**, y al pasar el mouse decir que no hay a dónde mandarlo.
2. Buscar uno **con correo** (p. ej. CJP `999999`). El botón está habilitado.
3. Clic → muestra "Enviando…" y termina en verde: *"Invitación reenviada al químico … El link
   vence en 7 días."*

**Esperado:** no da error. (El mail no va a llegar: ver el aviso del principio.)

## 4 · Cargar el correo dispara la invitación sola

1. Elegir un químico con **Acceso = No** y **sin correo**.
2. **Editar contacto** → cargar un email → **Guardar**.

**Esperado:** guarda sin error y el email aparece en la tabla.
Por detrás se le generó su invitación. Corregirle el correo a alguien que **ya entró alguna
vez** NO le manda nada — para eso está el botón del caso 3.

## 5 · Definir la clave desde el link (app del Químico)

Este es el link que llegaría por mail. Ya está generado, **vence el 2026-09-01**:

```
https://qfpre.recetalia.com/definir-clave?code=geCtotmaIdrJar2T5W0zNRVWt2lg_Nl8QgV9qFwlETU
```

Es del químico de prueba **999999 — "Químico De Prueba"**.

1. Abrirlo **en una ventana de incógnito** (tiene que funcionar sin estar logueado).
2. Aparece "Definí tu clave". Escribir una clave (mínimo 6) dos veces → **Definir clave y entrar**.

**Esperado:** entra solo, sin pedirle usuario. El químico nunca vio su usuario —es
`999999@qf.recetalia.com`, derivado de su matrícula—, así que si le pidiera loguearse quedaría
trabado.

**Anotá la clave que pongas**: la vas a necesitar para el caso 8.

**Caso negativo:** abrir `https://qfpre.recetalia.com/definir-clave?code=inventado` → tiene que
decir que el link no es válido o venció, sin romperse.

## 6 · Completar el registro

Después del caso 5 lleva solo a la pantalla de registro (verificar datos + Nº de talonario).
Completarla. Es el flujo que ya existía; se prueba que el link no lo haya roto.

## 7 · Validar las farmacias (lo nuevo)

Al terminar el registro tiene que aparecer **"Confirmá tus farmacias"** y **no debe poder
saltearla**.

El químico 999999 tiene 3: **ARIES**, **MINAS** y **Test**.

1. Verificar que el botón de abajo dice **"Te faltan responder 3"** y está deshabilitado.
2. Marcar **Es mía** en ARIES y en MINAS.
3. Marcar **No es mía** en **Test**.
4. Aparece el aviso de que se le va a informar a Recetalia.
5. **Confirmar** → entra a la app normalmente.

**Caso negativo:** con alguna sin responder, el botón sigue deshabilitado. Es un control legal:
no se puede confirmar a medias.

## 8 · La farmacia rechazada aparece en Gestión

1. Volver a Gestión → Químicos Farmacéuticos → solapa **Farmacias sin químico**.

**Esperado:** aparece **Test**, con el CJP declarado (`999999`) y el responsable que declara.
La farmacia **sigue operando normalmente** — es una lista para llamar, no un bloqueo.

## 9 · No vuelve a encerrarlo

1. Cerrar sesión en la app del Químico y volver a entrar con `999999@qf.recetalia.com` y la
   clave del caso 5.

**Esperado:** entra directo a la app. **No** vuelve a mostrar la pantalla de farmacias. Sólo
bloquea la primera vez; después de que se pronunció, una farmacia nueva aparece pendiente pero
no le traba la aplicación.

---

## Qué NO se puede probar todavía

| Caso | Por qué |
|---|---|
| Que el mail de invitación llegue a una casilla | SMTP de PRE con credenciales rotas |
| Que el aviso de rechazo llegue a hello@recetalia.com | ídem |
| Cualquier cosa en producción | no se desplegó nada a PROD |

Que el mail *se arma y sale hacia el servidor de correo* sí está verificado por otro lado (log
del servidor). Lo que falta es la última milla.

## Cómo queda el ambiente después de probar

El caso 7 **corta el vínculo** entre la farmacia rechazada y su químico. Para volver atrás,
anotar qué farmacia se rechazó y avisarlo — se revierte por base de datos.

Las 3 farmacias del químico 999999 (por si hay que restaurarlas):

| Farmacia | id |
|---|---|
| ARIES | `00d5ddc0-5d3d-4ffa-9473-405c4776d550` |
| MINAS | `02498a80-5aaf-479b-987b-b030f0584650` |
| Test | `e9e4ed5e-fc32-4168-9afb-660a09885498` |

## Dónde reportar

Los defectos van contra el plan
`doc/plans/2026-08-24-qf-acceso-y-validacion-farmacias-plan.md`, que ya tiene 8 ítems de deuda
conocidos (DT-1 a DT-8) — conviene revisarlos antes de reportar algo como nuevo.
