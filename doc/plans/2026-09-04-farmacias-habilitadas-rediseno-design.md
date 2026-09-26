# Spec: Rediseño del listado público de farmacias habilitadas — 2026-09-04

Página: `https://recetalia.com/farmacias-habilitadas.php`. Repo: `recetalia-site`
(`farmacias-habilitadas.php`, 485 líneas). Se sirve como servicio `recetalia-site` del
`docker-compose.yml` de `deploy-recetalia`, sin volúmenes: cada cambio exige rebuild.
No hay vhost `*pre` del sitio: "PRE y PROD" = deployar al `.98` y al `.217`.

## Pedido

Mejorar sustancialmente el diseño del listado, acercándolo al resto del sitio. **No cambiar
colores**, sólo cómo se muestra. El listado sigue saliendo de la base (ya lo hace: `pharmacy`
activas + `localities` + `regions`, por mysqli con SSL y env `SITE_DB_*`).

## Estado actual (medido 2026-09-04)

- 298 farmacias activas en 19 departamentos (Montevideo 151, Canelones 43, Maldonado 27).
- Render 100 % en el navegador: JSON embebido + `DOMContentLoaded` que arma el DOM por
  concatenación de strings. Sin JavaScript la página queda vacía.
- Header y footer copiados inline (líneas 226-328 y 361-464) en vez de los `include_once`
  de `header.php` / `footer.php` que usan `index.php`, `contact.php`, `terms`, `privacy`.
- Carga el script de reCAPTCHA y define `onloadCallback` sobre un `#html_element` que no
  existe en la página.
- Estilos inline (líneas 164-198): acordeón por departamento, Montevideo abierto por defecto,
  texto de 12 px.

## Decisiones (con Pablo, 2026-09-04)

| Decisión | Elegido | Alternativas descartadas |
|---|---|---|
| Layout | **B**: columna de departamentos a la izquierda con conteo, lista de farmacias a la derecha | A: acordeón con cards en grilla · C: lista única con filtro |
| Búsqueda | **En todo el país**, ignora el departamento elegido; cada resultado muestra su departamento como etiqueta | Buscar sólo dentro del departamento |
| Celular | **Selector desplegable** nativo con departamentos y conteos | Chips deslizables |
| Render | **El PHP genera el HTML completo; el JS sólo muestra u oculta** | JSON embebido + DOM por JS (actual) · endpoint JSON + fetch |

## Diseño

### Pantalla

- Sección con `section-title` como el resto del sitio: título "Farmacias habilitadas" y
  subtítulo "N farmacias en todo el país", N calculado en vivo.
- Buscador centrado arriba, sin botón: filtra mientras se escribe, por nombre, localidad y
  dirección, sin distinguir tildes ni mayúsculas.
  - Con texto: busca en todo el país. Cada fila visible muestra su departamento como etiqueta.
  - Vacío: vuelve al departamento seleccionado.
- Escritorio (≥ md): columna izquierda con los 19 departamentos ordenados alfabéticamente y su
  conteo; Montevideo seleccionado al entrar. Derecha: lista compacta, una fila por farmacia con
  nombre, "calle número · localidad", y teléfono como `tel:` clickeable.
- Celular (< md): la columna se reemplaza por un `<select>` con los mismos departamentos y
  conteos. Mismo estado compartido: elegir en uno actualiza el otro.
- Sin resultados: "No encontramos farmacias con ese nombre." en lugar de lista vacía.
- Colores, tipografía y componentes: sólo los que ya define `styles.css` (Poppins, `#2EA1B1`,
  `#F4F6F8`, `#212832`, grises). No se agregan colores.

### Código

- `farmacias-habilitadas.php` reescrito. Las funciones puras (agrupar, normalizar, teléfono)
  van a `inc/farmacias-habilitadas.php` para poder probarlas sin base, con
  `tests/farmacias-habilitadas.test.php` (PHP plano, sin framework; `tests/` fuera de la imagen).
- PHP: misma consulta. Arma `$items[region][]` y renderiza en el servidor la columna, el
  `<select>` y las filas. Cada fila lleva `data-region` y `data-search` (texto normalizado
  sin tildes, minúsculas). Escapar todo con `htmlspecialchars`.
- JS: un solo script, sin dependencias nuevas. Estado = `{region, query}`. Recalcula
  visibilidad de filas y etiquetas; actualiza el contador: "N farmacias en <departamento>"
  sin búsqueda, "N farmacias encontradas" con búsqueda (singular/plural).
- Normalización: PHP y JS quitan tildes con la misma regla. En PHP, si la extensión `intl`
  está (no viene en `php:7.4-apache` del Dockerfile), se descompone con `Normalizer` y cubre
  cualquier letra acentuada; si no, un mapa fijo de vocales acentuadas, `ü`, `ñ` y NBSP.
- Header y footer por `include_once("header.php")` / `include_once("footer.php")`. Se elimina
  el reCAPTCHA y su callback.
- Errores: si `real_connect` falla o la consulta devuelve `false`, se registra en `error_log`
  y la página muestra "No pudimos cargar el listado en este momento." con status 200 y el
  resto de la página intacta. Sin `Fatal error` en pantalla.
- Teléfono: si `phone` es nulo o no trae `national`, se omite la línea.
- Estilos propios de la página en un `<style>` al inicio, como hoy; `styles.css` no se toca.

### Deploy y verificación

- Rama de trabajo en `recetalia-site`. **No mergear sin OK explícito.**
- **Hallazgo 2026-09-04: el sitio NO corría en el `.98`** (sin carpeta, contenedor ni
  `SITE_DB_*`; sólo el vhost, llegado por el rsync del compose). Pablo pidió igual PRE y PROD,
  así que **se monta en el `.98`**: es viable sin tocar nginx porque el vhost ya proxea
  `8443 default_server` → `recetalia-site:80` (hoy 502), la MySQL de PRE tiene `have_ssl=YES`
  y `recetali_receta` con 302 farmacias activas en 19 departamentos. Se agregan 5 líneas
  `SITE_DB_*` al `.env` del `.98` (host `mysql`, user `recetalia_dev`) y se buildea el
  servicio. URL de PRE: `https://138.197.150.98:8443/farmacias-habilitadas.php` (cert propio).
  Verificar:
  - `curl` a la página: cantidad de filas `fh-item` = `COUNT(*)` de farmacias activas con
    localidad y región en la MySQL del `.98` (302 al relevar); departamentos = 19.
  - Marcador que da 0 antes y > 0 después (`class="fh-item"`).
  - Captura en escritorio y celular; OK de Pablo antes de PROD.
- Después, deploy al `.217`: rsync de la fuente a `/opt/recetalia/recetalia-site`, rebuild
  y `up -d --no-deps` del servicio `recetalia-site`, imagen de rollback tageada antes.
  Esperado: 298 filas.
- No se tocan nginx ni otros servicios.

## Fuera de alcance

- Mapa, horarios, "cómo llegar" o cualquier dato que hoy no esté en la base.
- Cambios en `styles.css` u otras páginas del sitio.
- Curar los datos de prueba en PROD (3 farmacias de prueba, ya en `BACKLOG.md`).

## Cambio de diseño en producción — 2026-09-05

Pablo vio el layout B en PROD y lo rechazó: "volvamos al acordeón, desplegando por departamento,
pero con los estilos mejorados". Y aclaró: acordeón clásico, **todos cerrados por defecto**, abrir
uno **cierra el que estaba abierto**. Reemplaza las decisiones "Layout B" y "Selector en celular"
de la tabla de arriba; el resto (búsqueda nacional, render en PHP, includes, error amable) sigue.

Diseño final, en PROD desde 2026-09-05 (`recetalia-site` commits `d02ccf2` + `a4b84fd`):
- Un bloque blanco por departamento (19, orden alfabético sin tildes): cabezal clickeable con el
  nombre, píldora con el conteo y chevron. Abierto = borde izquierdo y texto turquesa, chevron girado.
- Al entrar, todos cerrados. Click abre ese departamento (animación `max-height` al alto real) y
  cierra el abierto; click en el abierto lo cierra. `aria-expanded` acompaña.
- Búsqueda: abre los departamentos con coincidencias (varios a la vez, es una excepción al "uno
  solo"), esconde los demás, muestra "N farmacias encontradas". Al borrar, todo cerrado.
- Celular: el mismo acordeón apilado; ya no hay `<select>`.
