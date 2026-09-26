# Qué probar en producción — release 2.2.0

Esto es **sólo lo que cambió** en este release. No incluye una regresión de toda la plataforma:
lo que ya funcionaba y no se tocó, no está acá.

Ojo: esto es **producción**. Los datos que cargues quedan, y las anulaciones mandan mail de verdad.

---

## 0. Antes de empezar — si no hacés esto, vas a ver bugs que no existen

Las apps son PWA y el navegador se queda con la versión vieja cacheada. **Un F5 no alcanza.**
En cada app, abrí la consola del navegador (F12) y pegá esto una vez:

```js
navigator.serviceWorker.getRegistrations().then(r => r.forEach(x => x.unregister()));
caches.keys().then(k => k.forEach(c => caches.delete(c)));
```

Después recargá. Si ves algo raro en cualquier punto de este plan, lo primero es repetir esto.

**Dónde entrar:**

- Gestión — https://gestion.recetalia.com — `gestion@recetalia.com`
- Farmacias — https://farmacias.recetalia.com — `test@test.com`
- Prestadores — https://prestadores.recetalia.com — `test-prestador-deploy@recetalia.com`
- Químico Farmacéutico — https://qf.recetalia.com — **todavía no hay usuario; se crea en el bloque 5**

Las claves te las pasa Pablo aparte.

---

## 1. Libro Negro (Farmacias) — nunca estuvo en producción

En Farmacias, en el menú lateral tiene que aparecer **Libro Negro**.

1. Abrilo. Tiene que listar las dispensaciones de recetas verdes de tu farmacia, con el estado
   de control del Director Técnico.
2. Probá los filtros por fecha y el buscador de texto.
3. **Exportá el Excel.** El archivo tiene que bajar con el nombre
   `medicamentos-controlados-AAAA-MM-DD_HH-mm-ss.xlsx`, y su contenido tiene que coincidir con
   lo que estás viendo en pantalla.
4. Fijate que exista la columna **Código**, y que ahí aparezca el código Recetalia de cada receta.

Farmacias con movimiento para mirar: PIGALLE Canadá, PIGALLE 4, PIGALLE De la Costa.

## 2. Recetas en papel (Farmacias) — funcionalidad nueva

En Farmacias tiene que existir la pantalla **Mantenimiento de recetas en papel**.

1. Cargá una receta: buscá el medicamento con el buscador (escribí de a poco, tiene que ir
   filtrando solo), elegí presentación y dispensador, y completá el **Nº de talonario**.
2. Al guardar, el **código Recetalia** de la receta creada tiene que salir en un cartel, y la
   receta tiene que aparecer en el listado de abajo sin necesidad de recargar.
3. **Anulá esa receta.** Tiene que quedar tachada en el listado, no desaparecer.
4. Verificá que la **fecha que muestra es la del papel**, la que vos cargaste — no la fecha de hoy.
5. Andá al **Libro Negro** (bloque 1): esa receta tiene que estar ahí, y en la columna **Código**
   tiene que verse el **Nº de talonario** que pusiste.
6. Exportá el Excel y confirmá que el Nº de talonario también está.

Lo importante de este bloque: una receta de papel **no debe disparar notificaciones al paciente**,
y no debe aparecer en los KPIs de actividad del dashboard.

## 3. Alta y edición de farmacia — cambió el formulario

1. En https://farmacias.recetalia.com/register/ (alta pública, sin estar logueado), completá el
   **CJP del encargado** y salí del campo. Tiene que buscar solo al Químico Farmacéutico:
   - Con un CJP que existe (`88923`, Liliana Vila) → muestra los datos y bloquea esos campos.
   - Con un CJP que no existe → te deja cargarlo a mano.
   - Con un CJP en revisión (`1` o `84805`) → avisa en rojo y **no deja continuar**.
2. **Ya no tiene que existir ningún campo de clave del Químico Farmacéutico** en el formulario.
   Si lo ves, es un bug.
3. Lo mismo en Gestión → Farmacias → editar una farmacia: el modal tampoco debe pedir esa clave.

## 4. Bandeja de Químicos (Gestión) — pantalla nueva

En Gestión → Farmacias → **Químicos**.

1. Tiene que haber **tres solapas**: pendientes de habilitación, en revisión por CJP, y
   habilitados.
2. En la solapa de habilitados tiene que haber alrededor de **200** y funcionar el filtro.
3. En la de **en revisión** tienen que aparecer **20**, y ahí tienen que estar el CJP `1`
   (Florencia Larrosa, 7 farmacias) y el `84805` (Andrea Fillippini, 7 farmacias). Son CJPs que
   figuran con más de un titular distinto: están bloqueados a propósito hasta que alguien
   corrija el dato.

## 5. Habilitar un QF y su primer ingreso — el circuito completo

Éste es el bloque más importante, porque es el único que no se pudo probar contra datos reales.

1. En la bandeja de Químicos, elegí un QF **habilitado** (probá con el CJP `88923`, Liliana Vila,
   que tiene 6 farmacias) y **asignale una clave** desde el modal.
   - Probá primero con una clave de menos de 8 caracteres: tiene que avisarte y no guardar.
2. Entrá a https://qf.recetalia.com con usuario `88923@qf.recetalia.com` y esa clave.
3. **No tiene que llevarte al listado: tiene que mandarte a la pantalla de registro**, a poner tu
   propia clave y confirmar tus datos. El texto tiene que decir que la clave te la asignó
   Recetalia (no la farmacia).
4. Completá el registro con una clave nueva. **Anotá cuál pusiste.**
5. Ahora sí tenés que ver **"Mis farmacias"** con las 6 sucursales.
6. Probá volver a entrar con la **clave vieja**: tiene que rechazarte.
7. Dentro de la app, entrá al listado de recetas verdes de una de tus farmacias y **controlá
   (firmá) una dispensación**. Después, en el Libro Negro de Farmacias, esa dispensación tiene
   que figurar como controlada, con tu nombre y tu CJP.

⚠️ Usá un nombre **sin tildes** si tenés que escribir algo: hay un problema conocido de
codificación que corrompe los acentos al guardarlos. No lo reportes, ya está anotado.

## 6. Lo que tiene que fallar

Tan importante como lo que funciona. Ninguna de estas cosas debería dejarte pasar:

1. Logueado como **farmacia**, no tenés que poder ver el dashboard general de la plataforma
   (el de Gestión). El dashboard **de tu farmacia** sí tiene que andar.
2. Un QF con el CJP **en revisión** (`1` o `84805`) no tiene que poder operar aunque le asignes
   una clave: la app tiene que avisarle y no dejarlo entrar al módulo.
3. Desde una farmacia no tenés que poder ver dispensaciones de otra farmacia.

## 7. Íconos en el celular

En las cuatro apps (Farmacias, Médicos, Prestadores, Gestión), desde el celular: "Agregar a
pantalla de inicio". El ícono tiene que ser el de la app correspondiente, y el nombre debajo del
ícono tiene que ser el de esa app — no un nombre genérico ni el ícono equivocado.

---

## Esperado — no lo reportes como bug

- **Los QF no pueden entrar hasta que Gestión les asigne una clave.** No hay ningún usuario de QF
  creado de fábrica.
- **20 Químicos figuran "en revisión" y no pueden operar.** Es correcto: son CJPs compartidos por
  personas con nombres distintos, y alguien tiene que corregir el dato. Afecta a 65 farmacias, y
  **sólo les bloquea el módulo del QF**: esas farmacias siguen dispensando normalmente.
- **Una farmacia recibe un error de permiso al pedir el dashboard general.** Es el arreglo de este
  release, no una falla.
- **Si buscás muchos CJP seguidos, en algún momento deja de responder** (más o menos a los 20 por
  minuto). Es un límite puesto a propósito; el uso normal del formulario no lo alcanza.
- **Los nombres con tildes pueden verse mal.** Problema viejo de codificación de la base, ya
  anotado, no es de este release.
- **Los acentos en algunos nombres de farmacia** (por ejemplo "PIGALLE Canadá") vienen así de la
  base desde antes.
