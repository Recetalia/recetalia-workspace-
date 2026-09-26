# Ícono automático al agregar a pantalla de inicio (PWA icons)

Fecha: 2026-07-27
Apps: `medics-recetalia-app`, `farmacias-recetalia-app`, `qf-recetalia-app`,
`medical-provider-app`. Fuera de alcance: `gestion-recetadigital-app`.

## Problema

"Añadir a pantalla de inicio" desde un iPhone en `medicos.recetalia.com` deja un
**cuadrado blanco** en vez del ícono de Recetalia.

## Diagnóstico

Cuatro defectos encadenados. Verificado contra prod el 2026-07-27:

| Chequeo | Resultado |
|---|---|
| `GET /manifest.webmanifest` | `200` pero `text/html`, 38894 B — es el `index.html` |
| `GET /apple-touch-icon.png` | `404` |
| `apple-touch-icon` en el `<head>` | 0 ocurrencias |

1. **Causa raíz: el manifest nunca llega al build.** `angular.json` declaraba
   `assets: ["src/favicon.ico", "src/assets"]`. `src/manifest.webmanifest` no estaba
   en la lista, así que el builder no lo copiaba a `dist/`. En el contenedor, el
   `try_files $uri $uri/ /index.html` del `default.conf` respondía el `index.html`.
   El browser recibía HTML donde esperaba JSON y descartaba el manifest.

2. **Los íconos declarados no existían o mentían el tamaño.** El manifest declaraba
   `assets/images/icon/logo_medc.png` como `192x192`, pero el archivo real mide
   **214×72** (el logotipo horizontal, no un ícono). Chrome descarta íconos cuyo
   tamaño real no coincide con el declarado. `assets/icons/icon-512x512.png` no
   existía en ninguna app.

3. **No había `apple-touch-icon`.** Ni el `<link>` en el `<head>`, ni el archivo en la
   raíz. Sin apple-touch-icon y sin manifest válido, iOS Safari cae a su último
   recurso: **una captura de la página**. El login renderiza blanco → cuadrado blanco.

4. **Ruido en el `<head>`.** `<link rel="manifest">` y `<meta theme-color>` estaban
   duplicados (líneas 14-17) en medics, farmacias y qf. `medical-provider-app` no
   tenía manifest ni link.

## Arte de origen

`recetalia-site/images/favicon-recetalia.png` — 698×702 RGBA, el isotipo oficial
(el círculo con la "t" de rece**t**alia). Con `-trim` da **688×688 exacto**.
Resolución de sobra para 512. NO derivar del wordmark (222×85): queda borroso.

## Set de íconos

En `src/assets/icons/` de cada app (ya cubierto por el glob `src/assets`):

| Archivo | Tamaño | Alpha | Uso y razón |
|---|---|---|---|
| `icon-192.png` | 192×192 | sí | manifest `purpose: "any"` |
| `icon-512.png` | 512×512 | sí | manifest `purpose: "any"` |
| `icon-maskable-512.png` | 512×512 | **no**, fondo blanco | `purpose: "maskable"`. Símbolo al **80%**: Android recorta a círculo/squircle y el isotipo ya es un círculo que toca los bordes; sin safe zone se come el anillo rosa |
| `apple-touch-icon.png` | 180×180 | **no**, fondo blanco | iOS compone el alpha sobre **negro**, por eso hay que aplanar. 180 = tamaño Retina |

Comandos (ImageMagick):

```bash
magick recetalia-site/images/favicon-recetalia.png -trim +repage -background none \
  -gravity center -extent "%[fx:max(w,h)]x%[fx:max(w,h)]" base.png
magick base.png -resize 192x192 $D/icon-192.png
magick base.png -resize 512x512 $D/icon-512.png
magick base.png -resize 410x410 -background white -gravity center \
  -extent 512x512 -alpha remove -alpha off $D/icon-maskable-512.png
magick base.png -resize 164x164 -background white -gravity center \
  -extent 180x180 -alpha remove -alpha off $D/apple-touch-icon.png
```

## Cambios por app

| # | Archivo | Cambio |
|---|---|---|
| a | `angular.json` | `"src/manifest.webmanifest"` en el array `assets` del target **build** (no el de `test`) |
| b | `src/manifest.webmanifest` | `icons` reales + `purpose`; `name`/`short_name` propios. Creado en `medical-provider-app` |
| c | `src/index.html` | `apple-touch-icon` + `apple-mobile-web-app-title`; borrado el `rel="manifest"` y `theme-color` duplicados; agregado el link en `medical-provider-app` |
| d | `src/assets/icons/` | los 4 PNG |
| e | `default.conf` | MIME de `.webmanifest` |

`medical-provider-app/angular.json` **no parsea como JSON estricto** (tiene comentarios
`//`) — se edita a mano, no con script. Además usa el builder `:browser` (no
`:application`), así que su salida NO lleva subcarpeta `browser/`; su Dockerfile ya
copia desde `dist/medical-provider-app` directo, es consistente.

## MIME del manifest

El diseño inicial asumía que `nginx:alpine` resolvía `.webmanifest`. **Es falso**, y se
verificó empíricamente: nginx 1.31.3 tiene **cero** entradas de `webmanifest` en
`/etc/nginx/mime.types` y sirve el archivo como `application/octet-stream`.

Corrección en el `default.conf` de cada app:

```nginx
location = /manifest.webmanifest {
    default_type application/manifest+json;
}
```

**No usar un bloque `types { }` a nivel `server`**: en nginx no es aditivo, reemplaza el
mapa heredado entero y dejaría el CSS y el JS en `application/octet-stream`. El
`location =` exacto es quirúrgico: nginx no encuentra la extensión en el mapa y cae al
`default_type` de ese contexto.

Esto **no** afecta el síntoma de iOS (el `apple-touch-icon` es un `<link>` del `<head>`
y no depende del manifest). El MIME importa para la instalabilidad en Android/Chrome.

## Nombres

Se usa `apple-mobile-web-app-title` en lugar de cambiar `<title>`, porque el title
también controla la pestaña del browser y hoy difiere por app.

| App | `name` | `short_name` | `<title>` actual (sin tocar) |
|---|---|---|---|
| medics | Recetalia Médico | Médico | `Recetalia Médico` |
| farmacias | Recetalia Farmacia | Farmacia | `Gestión de farmacias` |
| qf | Recetalia QF | QF | `Recetalia — Químico Farmacéutico` |
| medical-provider | Recetalia Prestador | Prestador | `Prestadores` |

Mismo ícono para las 4 (consistencia de marca); las diferencia el nombre.

## Fuera de alcance

- **Sin service worker / sin `ng add @angular/pwa`.** Choca con el kill-switch de la
  PWA vieja (`deploy-recetalia/nginx/conf.d/50-prod-frontends.conf:5-11`) y con el
  `enabled:false` que ya se puso en qf por cachés viejos.
- **Sin cambiar `theme-color`.** Hoy `#1976d2` (scaffold de Angular); la marca real es
  teal `#51A9AA` / rosa `#DE798A`. Corregirlo tiñe la barra de direcciones en las 4
  apps — cambio visible, fuera de este alcance.

## Verificación (ejecutada 2026-07-27)

| Chequeo | medics | farmacias | qf | medical-provider |
|---|---|---|---|---|
| build | ✅ | ✅ | ✅ | ✅ (vía `docker build`) |
| `manifest.webmanifest` en `dist/` | ✅ | ✅ | ✅ | ✅ |
| 4 íconos en `dist/` | ✅ | ✅ | ✅ | ✅ |
| `rel="manifest"` = 1 (no 2) | ✅ | ✅ | ✅ | ✅ |
| `apple-touch-icon` | ✅ | ✅ | ✅ | ✅ |

Servido por nginx real: manifest → `application/manifest+json`, CSS → `text/css`,
JS → `application/javascript`, PNG → `image/png`. `nginx -t` OK. Las rutas
prerenderizadas (incluida `/login`) llevan los tags.

`medical-provider-app` no tiene `node_modules` y su `npm ci` falla (lockfile
desincronizado: `Missing: bootstrap@5.3.8`, preexistente) → verificado con
`docker build` para no ensuciar el lockfile.

**Falta**: probar en un iPhone real. Al reprobar hay que **borrar el acceso directo
viejo** — iOS cachea el ícono y se sigue viendo el cuadrado blanco aunque esté
arreglado.
