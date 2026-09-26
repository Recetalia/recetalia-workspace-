# Rediseño del listado público de farmacias habilitadas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reescribir `farmacias-habilitadas.php` del sitio público con el layout B (departamentos a la izquierda, lista a la derecha, selector en celular, búsqueda nacional), renderizado en PHP, y desplegarlo en PRE (`.98`, donde el sitio se monta por primera vez) y en PROD (`.217`).

**Architecture:** La página consulta la base igual que hoy y renderiza todo el HTML en el servidor; un único script en el navegador muestra u oculta filas según departamento y búsqueda. Las funciones puras (agrupar, normalizar, teléfono) viven en `inc/farmacias-habilitadas.php` y se prueban con un script PHP sin framework. Header y footer pasan a los `include_once` del sitio.

**Tech Stack:** PHP 7.4 (imagen `php:7.4-apache`, mysqli), Bootstrap 4.0.0-beta.2, `styles.css` del sitio (Poppins, `#2EA1B1`, `#F4F6F8`, `#212832`). Sin dependencias nuevas.

Spec: [2026-09-04-farmacias-habilitadas-rediseno-design.md](2026-09-04-farmacias-habilitadas-rediseno-design.md).

---

## Hallazgos previos al plan (medidos 2026-09-04)

- **El sitio sólo corre en el `.217`.** En el `.98` no hay `/opt/recetalia/recetalia-site`, ni contenedor, ni `SITE_DB_*` en su `.env` (sí quedó el vhost `40-recetalia-site.conf` por el rsync del compose). El `.98` está al 83 % de disco. Pablo pidió igual PRE y PROD → **Task 3 monta el sitio en el `.98`**. Relevado: es viable sin tocar nginx (el vhost ya proxea `8443 default_server` al contenedor), la MySQL de PRE tiene `have_ssl=YES` (la página fuerza `MYSQLI_CLIENT_SSL`) y `recetali_receta` con 302 activas / 19 departamentos.
- El `farmacias-habilitadas.php` del `.217` es idéntico al del repo (md5 `e4677df2…`).
- PHP local en la Mac es **8.5**; PROD es **7.4**. Las pruebas corren en los dos: local por rapidez y en `php:7.4-cli` por compatibilidad. Código sin `match`, `str_contains`, named args ni `?->`.
- `docker` local funciona (server 29.2.1, x86_64).
- `.dockerignore` existe; hay que sumarle `tests`.
- `fetch_all` de mysqli requiere mysqlnd: la imagen oficial `php:7.4` lo trae.

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `recetalia-site/inc/farmacias-habilitadas.php` | Constante con el SQL y funciones puras: `fh_normalizar`, `fh_telefono`, `fh_agrupar`, `fh_region_inicial`, `fh_plural`. Sin DB ni salida. |
| `recetalia-site/tests/farmacias-habilitadas.test.php` | Pruebas de las funciones puras. `php tests/...` sale con 1 si falla. |
| `recetalia-site/farmacias-habilitadas.php` | Página: conexión, consulta, render HTML, estilos propios, script de filtrado. |
| `recetalia-site/.dockerignore` | Sumar `tests`. |

Todo bajo `/Users/pablo/iwtg/recetalia-workspace/recetalia-site`. Rama `feat/farmacias-habilitadas-rediseno` desde `main`.

---

### Task 1: Rama y funciones puras (TDD)

**Files:**
- Create: `recetalia-site/inc/farmacias-habilitadas.php`
- Create: `recetalia-site/tests/farmacias-habilitadas.test.php`
- Modify: `recetalia-site/.dockerignore`

- [x] **Step 1: Crear la rama**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-site
git checkout main && git pull --ff-only
git checkout -b feat/farmacias-habilitadas-rediseno
```

- [x] **Step 2: Escribir las pruebas (fallan porque el include no existe)**

`recetalia-site/tests/farmacias-habilitadas.test.php`:

```php
<?php
// Pruebas de las funciones puras de farmacias-habilitadas. Sin framework:
//   php tests/farmacias-habilitadas.test.php
// Sale con 1 si algo falla. Correr también en php:7.4-cli (ver plan).
require_once __DIR__ . '/../inc/farmacias-habilitadas.php';

$fallos = 0;
function ok($cond, $msg) {
    global $fallos;
    if ($cond) { echo "  ok    $msg\n"; } else { $fallos++; echo "  FALLO $msg\n"; }
}

echo "fh_normalizar\n";
ok(fh_normalizar('Farmacia Río  Negro') === 'farmacia rio negro', 'minúsculas, sin tildes, espacios colapsados');
ok(fh_normalizar('Ñandú Ünico') === 'nandu unico', 'ñ y diéresis');
ok(fh_normalizar(null) === '', 'null → vacío');

echo "fh_telefono\n";
ok(fh_telefono('{"national":"2924 1234","international":"+59829241234"}') === array('national' => '2924 1234', 'international' => '+59829241234'), 'json completo');
ok(fh_telefono('{"national":"2924 1234"}') === array('national' => '2924 1234', 'international' => '2924 1234'), 'sin international usa national');
ok(fh_telefono(null) === null, 'null');
ok(fh_telefono('{"number":null}') === null, 'sin national');
ok(fh_telefono('no es json') === null, 'basura');

echo "fh_agrupar\n";
$filas = array(
    array('id' => '3', 'name' => 'Farmacia Rivera', 'addressStreet' => 'Sarandí', 'addressNumber' => '100', 'phone' => null, 'regionName' => 'Rivera', 'localityName' => 'Rivera'),
    array('id' => '1', 'name' => 'Farmacia Aguada', 'addressStreet' => ' Av. Gral. Rondeau ', 'addressNumber' => '1795', 'phone' => '{"national":"2924 1234","international":"+59829241234"}', 'regionName' => 'Montevideo', 'localityName' => 'Montevideo'),
    array('id' => '2', 'name' => 'Farmacia Fray Bentos', 'addressStreet' => '18 de Julio', 'addressNumber' => '', 'phone' => null, 'regionName' => 'Río Negro', 'localityName' => 'Fray Bentos'),
);
$d = fh_agrupar($filas);
ok($d['total'] === 3, 'total');
ok(array_keys($d['regiones']) === array('Montevideo', 'Río Negro', 'Rivera'), 'regiones ordenadas sin tildes (Río Negro antes que Rivera)');
ok($d['regiones']['Montevideo']['cantidad'] === 1, 'cantidad por región');
$f = $d['regiones']['Montevideo']['farmacias'][0];
ok($f['id'] === 1, 'id entero');
ok($f['direccion'] === 'Av. Gral. Rondeau 1795', 'dirección recortada');
ok($f['busqueda'] === 'farmacia aguada montevideo av. gral. rondeau 1795', 'texto de búsqueda');
ok($f['telefono']['international'] === '+59829241234', 'teléfono');
ok($d['regiones']['Río Negro']['farmacias'][0]['direccion'] === '18 de Julio', 'sin número no deja espacio colgando');
ok($d['regiones']['Rivera']['farmacias'][0]['telefono'] === null, 'sin teléfono');
ok(fh_agrupar(array()) === array('total' => 0, 'regiones' => array()), 'sin filas');

echo "fh_region_inicial\n";
ok(fh_region_inicial($d['regiones']) === 'Montevideo', 'Montevideo si existe');
ok(fh_region_inicial(array('Salto' => array())) === 'Salto', 'si no, la primera');
ok(fh_region_inicial(array()) === '', 'vacío');

echo "fh_plural\n";
ok(fh_plural(1, 'farmacia', 'farmacias') === '1 farmacia', 'singular');
ok(fh_plural(151, 'farmacia', 'farmacias') === '151 farmacias', 'plural');

echo $fallos ? "\n$fallos FALLOS\n" : "\nTodo OK\n";
exit($fallos ? 1 : 0);
```

- [x] **Step 3: Correr y ver que falla**

```bash
php tests/farmacias-habilitadas.test.php
```
Esperado: `Failed opening required '.../inc/farmacias-habilitadas.php'`, exit ≠ 0.

- [x] **Step 4: Escribir el include**

`recetalia-site/inc/farmacias-habilitadas.php`:

```php
<?php
// Funciones puras de farmacias-habilitadas.php. Sin DB ni salida, para poder
// probarlas con tests/farmacias-habilitadas.test.php. Compatibles con PHP 7.4.

const FH_SQL = "
    SELECT pharmacy.id, pharmacy.name, pharmacy.addressStreet, pharmacy.addressNumber,
           pharmacy.phone, regions.name AS regionName, localities.name AS localityName
    FROM pharmacy
    JOIN localities ON localities.id = pharmacy.addressLocalityId
    JOIN regions ON regions.id = localities.region_id
    WHERE pharmacy.status = 'ACTIVE'
    ORDER BY pharmacy.name ASC";

// Minúsculas, sin tildes, espacios colapsados. Misma regla que el normalizar() del
// script de la página: lo que se compara tiene que salir igual en PHP y en JS.
function fh_normalizar($texto) {
    $texto = mb_strtolower((string)$texto, 'UTF-8');
    $texto = strtr($texto, array(
        'á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u', 'ü' => 'u', 'ñ' => 'n',
        'à' => 'a', 'è' => 'e', 'ì' => 'i', 'ò' => 'o', 'ù' => 'u',
    ));
    return trim(preg_replace('/\s+/', ' ', $texto));
}

// Columna `phone` = JSON {"national": "...", "international": "..."} o basura/NULL.
function fh_telefono($phoneJson) {
    $tel = json_decode((string)$phoneJson, true);
    if (!is_array($tel) || empty($tel['national'])) {
        return null;
    }
    $national = (string)$tel['national'];
    $international = !empty($tel['international']) ? (string)$tel['international'] : $national;
    return array('national' => $national, 'international' => $international);
}

// Filas del SQL → ['total' => N, 'regiones' => [nombre => ['nombre', 'cantidad', 'farmacias' => [...]]]]
// Regiones ordenadas alfabéticamente sin tildes; farmacias en el orden del SQL (por nombre).
function fh_agrupar(array $filas) {
    $regiones = array();
    foreach ($filas as $fila) {
        $region = trim((string)$fila['regionName']);
        $direccion = trim(trim((string)$fila['addressStreet']) . ' ' . trim((string)$fila['addressNumber']));
        $localidad = trim((string)$fila['localityName']);
        $farmacia = array(
            'id' => (int)$fila['id'],
            'nombre' => trim((string)$fila['name']),
            'direccion' => $direccion,
            'localidad' => $localidad,
            'telefono' => fh_telefono($fila['phone']),
        );
        $farmacia['busqueda'] = fh_normalizar($farmacia['nombre'] . ' ' . $localidad . ' ' . $direccion);
        if (!isset($regiones[$region])) {
            $regiones[$region] = array('nombre' => $region, 'cantidad' => 0, 'farmacias' => array());
        }
        $regiones[$region]['farmacias'][] = $farmacia;
        $regiones[$region]['cantidad']++;
    }
    uksort($regiones, function ($a, $b) {
        return strcmp(fh_normalizar($a), fh_normalizar($b));
    });
    return array('total' => count($filas), 'regiones' => $regiones);
}

// Departamento seleccionado al entrar: Montevideo si existe, si no el primero.
function fh_region_inicial(array $regiones) {
    if (isset($regiones['Montevideo'])) {
        return 'Montevideo';
    }
    $claves = array_keys($regiones);
    return $claves ? (string)$claves[0] : '';
}

function fh_plural($n, $singular, $plural) {
    return $n . ' ' . ($n === 1 ? $singular : $plural);
}
```

- [x] **Step 5: Correr las pruebas en local y en 7.4**

```bash
php tests/farmacias-habilitadas.test.php
docker run --rm -v "$PWD":/app -w /app php:7.4-cli php tests/farmacias-habilitadas.test.php
```
Esperado en ambos: todas las líneas `ok`, última línea `Todo OK`, exit 0. Si `mb_strtolower` faltara en 7.4-cli (no debería: mbstring viene en la imagen oficial), aparece `Call to undefined function` y hay que revisar la imagen, no el código.

- [x] **Step 6: Excluir tests de la imagen**

Agregar al final de `recetalia-site/.dockerignore`:

```
tests
```

- [x] **Step 7: Commit**

```bash
git add inc/farmacias-habilitadas.php tests/farmacias-habilitadas.test.php .dockerignore
git commit -m "feat(farmacias): funciones puras del listado de habilitadas, con pruebas"
```

---

### Task 2: Reescribir la página

**Files:**
- Modify: `recetalia-site/farmacias-habilitadas.php` (reemplazo completo de las 485 líneas)

- [x] **Step 1: Guardar el HTML actual como referencia**

```bash
curl -s https://recetalia.com/farmacias-habilitadas.php -o /tmp/fh-antes.html
grep -c 'fh-item' /tmp/fh-antes.html
grep -o '"id":"[0-9a-f-]*"' /tmp/fh-antes.html | sort -u | wc -l
```
Esperado: `0` (marcador nuevo ausente) y `298` (farmacias en el JSON viejo; es el conteo de referencia de PROD hoy).

- [x] **Step 2: Escribir la página nueva**

Reemplazar `recetalia-site/farmacias-habilitadas.php` entero por:

```php
<?php
// Listado público de farmacias habilitadas. Renderizado en el servidor; el script
// de abajo sólo muestra u oculta filas. Spec: doc/plans/2026-09-04-farmacias-habilitadas-rediseno-design.md
require_once __DIR__ . '/inc/farmacias-habilitadas.php';

// Credenciales read-only (SELECT sobre pharmacy/localities/regions), por env del
// contenedor (docker-compose.yml → recetalia-site). Requiere SSL.
$fhError = false;
$fhDatos = array('total' => 0, 'regiones' => array());

mysqli_report(MYSQLI_REPORT_OFF);
$mysqli = mysqli_init();
$mysqli->ssl_set(NULL, NULL, NULL, NULL, NULL);
$conectado = @$mysqli->real_connect(
    getenv('SITE_DB_HOST'),
    getenv('SITE_DB_USER'),
    getenv('SITE_DB_PASS'),
    getenv('SITE_DB_NAME') ?: 'recetali_receta',
    (int)(getenv('SITE_DB_PORT') ?: 25060),
    NULL,
    MYSQLI_CLIENT_SSL | MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT
);
if (!$conectado) {
    error_log('farmacias-habilitadas: no se pudo conectar a la DB: ' . mysqli_connect_error());
    $fhError = true;
} else {
    $mysqli->set_charset('utf8mb4');
    $res = $mysqli->query(FH_SQL);
    if ($res === false) {
        error_log('farmacias-habilitadas: consulta fallida: ' . $mysqli->error);
        $fhError = true;
    } else {
        $fhDatos = fh_agrupar($res->fetch_all(MYSQLI_ASSOC));
    }
    $mysqli->close();
}

$fhRegiones = $fhDatos['regiones'];
$fhTotal = $fhDatos['total'];
$fhInicial = fh_region_inicial($fhRegiones);
$fhCantidadInicial = $fhInicial !== '' ? $fhRegiones[$fhInicial]['cantidad'] : 0;

function fh_e($s) {
    return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8');
}
?>
<!DOCTYPE HTML>
<html lang="es">

<head>
    <base href="https://recetalia.com/">
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no" />
    <meta name="description" content="Farmacias habilitadas para dispensar recetas digitales de Recetalia en todo el Uruguay." />
    <meta name="author" content="Recetalia" />
    <title>Recetalia - Farmacias habilitadas</title>
    <link rel="shortcut icon" href="images/favicon-recetalia.png" type="image/x-icon">
    <link rel="icon" href="images/favicon-recetalia.png" type="image/x-icon">
    <link rel="stylesheet" href="css/bootstrap.min.css" />
    <link rel="stylesheet" href="css/font-awesome.min.css" />
    <link rel="stylesheet" href="css/slimmenu.min.css" />
    <link rel="stylesheet" href="css/animate.min.css" />
    <link rel="stylesheet" href="styles.css" />
    <link rel="stylesheet" href="css/responsive.css" />
    <link href="https://fonts.googleapis.com/css?family=Poppins:400,500,700" rel="stylesheet">

    <style>
        /* Estilos propios del listado. Sólo colores que ya usa styles.css. */
        .fh-buscar { max-width: 560px; margin: 0 auto 40px; position: relative; }
        .fh-buscar .form-control { height: 48px; padding-left: 44px; font-size: 15px; }
        .fh-buscar .fa { position: absolute; left: 16px; top: 16px; color: #a6a6a6; }

        .fh-departamentos { list-style: none; padding: 0; margin: 0; background: #fff;
            box-shadow: -1px 0px 30px 0px rgba(0, 0, 0, 0.05); }
        .fh-dep { display: flex; justify-content: space-between; align-items: center; width: 100%;
            padding: 11px 18px; border: 0; border-left: 3px solid transparent; background: none;
            text-align: left; font-family: inherit; font-size: 14px; color: #212832; cursor: pointer; }
        .fh-dep:hover { border-left-color: #dbdbdb; background: #F4F6F8; }
        .fh-dep.activo { border-left-color: #2EA1B1; color: #2EA1B1; font-weight: 500; background: #F4F6F8; }
        .fh-dep .fh-cantidad { font-size: 12px; color: #7d7d7d; }
        .fh-dep.activo .fh-cantidad { color: #2EA1B1; }
        .fh-select { margin-bottom: 20px; height: 48px; }

        .fh-contador { font-size: 14px; color: #7d7d7d; margin: 0 0 12px; }
        .fh-lista { list-style: none; padding: 0; margin: 0; background: #fff;
            box-shadow: -1px 0px 30px 0px rgba(0, 0, 0, 0.05); }
        .fh-item { display: flex; justify-content: space-between; align-items: center; gap: 16px;
            padding: 14px 20px; border-bottom: 1px solid #e5e5e5; }
        .fh-item:last-child { border-bottom: 0; }
        .fh-item h6 { font-size: 15px; font-weight: 500; margin: 0 0 2px; color: #212832; }
        .fh-item p { font-size: 13px; line-height: 20px; margin: 0; color: #7d7d7d; }
        .fh-item .fh-tel { white-space: nowrap; font-size: 14px; color: #2EA1B1; }
        .fh-item .fh-tel .fa { margin-right: 6px; }
        .fh-etiqueta { display: none; margin-left: 8px; padding: 1px 10px; border-radius: 12px;
            background: #F4F6F8; color: #2EA1B1; font-size: 12px; }
        .fh-lista.fh-buscando .fh-etiqueta { display: inline-block; }
        .fh-vacio, .fh-error { background: #fff; padding: 30px 20px; text-align: center; color: #7d7d7d; }
        [hidden] { display: none !important; }

        @media (max-width: 767px) {
            .fh-item { flex-direction: column; align-items: flex-start; gap: 4px; padding: 12px 16px; }
            .fh-buscar { margin-bottom: 24px; }
        }
    </style>
</head>

<body>
    <?php include_once("header.php"); ?>

    <section class="services-section padding-60-0 bg-color3 section-spacing">
        <div class="container">
            <div class="row">
                <div class="col-md-12">
                    <div class="section-title margin-bottom-60 text-center">
                        <h4>Farmacias habilitadas</h4>
                        <?php if (!$fhError): ?>
                        <p><?php echo fh_plural($fhTotal, 'farmacia habilitada', 'farmacias habilitadas'); ?> en todo el país</p>
                        <?php endif; ?>
                    </div>
                </div>
            </div>

            <?php if ($fhError): ?>
            <div class="row">
                <div class="col-md-8 col-lg-6 mx-auto">
                    <p class="fh-error">No pudimos cargar el listado en este momento. Volvé a intentarlo en unos minutos.</p>
                </div>
            </div>
            <?php else: ?>
            <div class="fh-buscar">
                <i class="fa fa-search" aria-hidden="true"></i>
                <input type="search" id="fh-buscar" class="form-control" autocomplete="off"
                       placeholder="Buscar por nombre, localidad o dirección" aria-label="Buscar farmacia">
            </div>

            <div class="row">
                <aside class="col-md-4 col-lg-3">
                    <select id="fh-select" class="form-control fh-select d-md-none" aria-label="Departamento">
                        <?php foreach ($fhRegiones as $r): ?>
                        <option value="<?php echo fh_e($r['nombre']); ?>"<?php echo $r['nombre'] === $fhInicial ? ' selected' : ''; ?>><?php echo fh_e($r['nombre']); ?> (<?php echo $r['cantidad']; ?>)</option>
                        <?php endforeach; ?>
                    </select>
                    <ul class="fh-departamentos d-none d-md-block">
                        <?php foreach ($fhRegiones as $r): ?>
                        <li><button type="button" class="fh-dep<?php echo $r['nombre'] === $fhInicial ? ' activo' : ''; ?>" data-region="<?php echo fh_e($r['nombre']); ?>"><?php echo fh_e($r['nombre']); ?> <span class="fh-cantidad"><?php echo $r['cantidad']; ?></span></button></li>
                        <?php endforeach; ?>
                    </ul>
                </aside>

                <div class="col-md-8 col-lg-9">
                    <p id="fh-contador" class="fh-contador" aria-live="polite"><?php echo fh_plural($fhCantidadInicial, 'farmacia', 'farmacias'); ?> en <?php echo fh_e($fhInicial); ?></p>
                    <ul id="fh-lista" class="fh-lista">
                        <?php foreach ($fhRegiones as $r): foreach ($r['farmacias'] as $f): ?>
                        <li class="fh-item" data-region="<?php echo fh_e($r['nombre']); ?>" data-search="<?php echo fh_e($f['busqueda']); ?>"<?php echo $r['nombre'] === $fhInicial ? '' : ' hidden'; ?>>
                            <div>
                                <h6><?php echo fh_e($f['nombre']); ?></h6>
                                <p><?php echo fh_e($f['direccion']); ?><?php if ($f['localidad'] !== ''): ?> · <?php echo fh_e($f['localidad']); ?><?php endif; ?><span class="fh-etiqueta"><?php echo fh_e($r['nombre']); ?></span></p>
                            </div>
                            <?php if ($f['telefono']): ?>
                            <a class="fh-tel" href="tel:<?php echo fh_e($f['telefono']['international']); ?>"><i class="fa fa-phone" aria-hidden="true"></i><?php echo fh_e($f['telefono']['national']); ?></a>
                            <?php endif; ?>
                        </li>
                        <?php endforeach; endforeach; ?>
                    </ul>
                    <p id="fh-vacio" class="fh-vacio" hidden>No encontramos farmacias con ese nombre.</p>
                </div>
            </div>
            <?php endif; ?>
        </div>
    </section>

    <?php include_once("footer.php"); ?>

    <script src="js/jquery-3.2.1.min.js"></script>
    <script src="js/popper.min.js"></script>
    <script src="js/bootstrap.min.js"></script>
    <script src="js/jquery.slimmenu.min.js"></script>
    <script src="js/wow.min.js"></script>
    <script src="js/custom.js"></script>

    <?php if (!$fhError): ?>
    <script>
    (function () {
        var input = document.getElementById('fh-buscar');
        var select = document.getElementById('fh-select');
        var lista = document.getElementById('fh-lista');
        var contador = document.getElementById('fh-contador');
        var vacio = document.getElementById('fh-vacio');
        var deps = document.querySelectorAll('.fh-dep');
        var items = lista.querySelectorAll('.fh-item');
        var region = select.value;

        // Misma regla que fh_normalizar() en PHP: minúsculas, sin tildes, espacios colapsados.
        function normalizar(s) {
            return s.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/\s+/g, ' ').trim();
        }
        function plural(n, singular, pluralTxt) {
            return n + ' ' + (n === 1 ? singular : pluralTxt);
        }

        function aplicar() {
            var q = normalizar(input.value);
            var buscando = q !== '';
            var visibles = 0;
            lista.classList.toggle('fh-buscando', buscando);
            for (var i = 0; i < items.length; i++) {
                var it = items[i];
                var ok = buscando
                    ? it.getAttribute('data-search').indexOf(q) !== -1
                    : it.getAttribute('data-region') === region;
                it.hidden = !ok;
                if (ok) visibles++;
            }
            for (var j = 0; j < deps.length; j++) {
                deps[j].classList.toggle('activo', !buscando && deps[j].getAttribute('data-region') === region);
            }
            contador.textContent = buscando
                ? plural(visibles, 'farmacia encontrada', 'farmacias encontradas')
                : plural(visibles, 'farmacia', 'farmacias') + ' en ' + region;
            vacio.hidden = visibles > 0;
        }

        function elegir(r) {
            region = r;
            select.value = r;
            input.value = '';
            aplicar();
        }

        input.addEventListener('input', aplicar);
        select.addEventListener('change', function () { elegir(select.value); });
        for (var k = 0; k < deps.length; k++) {
            deps[k].addEventListener('click', function () { elegir(this.getAttribute('data-region')); });
        }
    })();
    </script>
    <?php endif; ?>

    <script src="https://videoconsulta.iwtg.com/video-chat.umd.min.js"></script>
    <link rel="stylesheet" href="https://videoconsulta.iwtg.com/video-chat.css">
    <video-chat bottom right text-color="#ffffff" primary-color="#13a0b2" public-key="QXfeToaWrocXmZosEiwJlXcoy"></video-chat>
</body>

</html>
```

Notas para quien implementa:
- Se sacaron `owl.carousel`, `modal-video`, `isotope`, `jquery-ui` y reCAPTCHA: la página no los usa. `slimmenu`, `wow` y `custom.js` sí, porque el header los necesita.
- `[hidden] { display: none !important }` está porque Bootstrap 4 beta y `display:flex` del `.fh-item` pisarían el atributo `hidden`.
- El widget `video-chat` se mantiene como está en el resto del sitio.

- [x] **Step 3: Chequeo de sintaxis en 7.4 y en local**

```bash
php -l farmacias-habilitadas.php
docker run --rm -v "$PWD":/app -w /app php:7.4-cli php -l farmacias-habilitadas.php
```
Esperado: `No syntax errors detected` en ambos.

- [x] **Step 4: Probar el camino de error (sin base)**

```bash
php -S 127.0.0.1:8088 -t . >/tmp/fh-php.log 2>&1 &
sleep 1
curl -s -o /tmp/fh-error.html -w '%{http_code}\n' http://127.0.0.1:8088/farmacias-habilitadas.php
grep -c 'No pudimos cargar el listado' /tmp/fh-error.html
grep -ci 'fatal\|warning' /tmp/fh-error.html
grep -c 'class="themeix-header"' /tmp/fh-error.html
kill %1
```
Esperado: `200`, `1`, `0`, `1` (la página entera con header se renderiza aunque la base no responda). Sin env `SITE_DB_HOST`, `real_connect` falla y entra por `$fhError`.

- [x] **Step 5: Commit**

```bash
git add farmacias-habilitadas.php
git commit -m "feat(farmacias): rediseño del listado de habilitadas con render en servidor

Departamentos a la izquierda con conteo, lista compacta a la derecha,
selector en celular, búsqueda nacional por nombre/localidad/dirección.
Usa header.php/footer.php en vez de la copia inline y saca el reCAPTCHA
que la página cargaba sin usar. Si la base no responde muestra un aviso
en vez de un Fatal error."
```

---

### Task 3: Deploy a PRE (`.98`) — montar el sitio y verificar

**Files:** ninguno en el repo. Cambios en el server `138.197.150.98`: fuente en `/opt/recetalia/recetalia-site`, 5 líneas `SITE_DB_*` nuevas en `/opt/recetalia/deploy-recetalia/.env`, contenedor `recetalia-site` nuevo.

Relevado 2026-09-04 en el `.98` (todo verificado por SSH):
- `nginx/conf.d/40-recetalia-site.conf` ya está y proxea `listen 8443 ssl default_server` → `recetalia-site:80` (con `set $backend`, por eso nginx arranca aunque el contenedor no exista). Hoy `https://127.0.0.1:8443/farmacias-habilitadas.php` da **502**. **No se toca nginx.**
- MySQL `recetalia-mysql` (`mysql:8.0`), alias de red `mysql`, puerto interno 3306, `have_ssl = YES`, schema `recetali_receta`. Usuario `recetalia_dev` (el de las APIs; su password está en el `.env` del `.98`).
- Farmacias activas con localidad y región en PRE: **302**, departamentos: **19** (SQL de abajo).
- Disco: 47 G usados de 59 G (83 %). La imagen `php:7.4-apache` pesa ~450 MB.
- El `.env` tiene `COMPOSE_FILE=docker-compose.yml:docker-compose.dev98.yml`, `IMAGE_TAG=dev`; el servicio `recetalia-site` del compose base buildea desde `../recetalia-site` y está en `recetalia-net`, la misma red que `recetalia-mysql`.

- [x] **Step 1: Marcador "antes" y espacio**

```bash
ssh root@138.197.150.98 'df -h / | tail -1; curl -sk -o /dev/null -w "%{http_code}\n" https://127.0.0.1:8443/farmacias-habilitadas.php; ls -d /opt/recetalia/recetalia-site 2>&1'
```
Esperado: uso < 90 %, `502`, `No such file or directory`. Si el disco está ≥ 90 %, frenar: correr `docker builder prune -f` y volver a medir antes de seguir (memoria `deploy-98-gotchas-medidos`).

- [x] **Step 2: Sincronizar la fuente del sitio**

```bash
cd /Users/pablo/iwtg/recetalia-workspace
rsync -az --exclude .git --exclude tests recetalia-site/ root@138.197.150.98:/opt/recetalia/recetalia-site/
ssh root@138.197.150.98 'md5sum /opt/recetalia/recetalia-site/farmacias-habilitadas.php /opt/recetalia/recetalia-site/inc/farmacias-habilitadas.php'
md5 -q recetalia-site/farmacias-habilitadas.php; md5 -q recetalia-site/inc/farmacias-habilitadas.php
```
Esperado: los md5 coinciden. Sin `--delete`: el directorio es nuevo.

- [x] **Step 3: Credenciales del sitio en el `.env` del `.98`**

Averiguar el nombre de la variable con la password de `recetalia_dev` (no imprimir su valor):

```bash
ssh root@138.197.150.98 'cd /opt/recetalia/deploy-recetalia && cp .env .env.bak-preSITE-20260904 && grep -n "PASS" .env | cut -d= -f1'
```
Esperado: aparece una variable tipo `DEV_DB_PASSWORD` o `RECETALIA_DB_PASSWORD` (línea ~20/30). Con ese nombre (`<VAR_PASS>`), agregar al final del `.env`:

```bash
ssh root@138.197.150.98 'cd /opt/recetalia/deploy-recetalia && grep -q "^SITE_DB_HOST" .env || printf "\n# Sitio institucional (farmacias-habilitadas.php) contra la MySQL de PRE\nSITE_DB_HOST=mysql\nSITE_DB_PORT=3306\nSITE_DB_USER=recetalia_dev\nSITE_DB_PASS=\${<VAR_PASS>}\nSITE_DB_NAME=recetali_receta\n" >> .env; grep -c "^SITE_DB_" .env; docker compose config 2>/dev/null | grep -A1 "SITE_DB_HOST" | head -2'
```
Esperado: `5` y `SITE_DB_HOST: mysql` en el config resuelto. Si `docker compose config` muestra `SITE_DB_PASS: ""`, la interpolación `${...}` no resolvió: reemplazar por el valor literal, que ya vive en ese mismo archivo.

- [x] **Step 4: Build y up sólo del sitio**

```bash
ssh root@138.197.150.98 'cd /opt/recetalia/deploy-recetalia && docker compose build recetalia-site 2>&1 | tail -3 && docker compose up -d --no-deps recetalia-site && sleep 3 && docker ps --format "{{.Names}} {{.Image}} {{.Status}}" | grep site && df -h / | tail -1'
```
Esperado: build OK, `recetalia-site …recetalia-site:dev Up X seconds`, disco < 90 %. Ningún otro contenedor se recrea.

- [x] **Step 5: Verificar en PRE**

```bash
curl -sk -o /tmp/fh-pre.html -w '%{http_code}\n' https://138.197.150.98:8443/farmacias-habilitadas.php
grep -c 'class="fh-item"' /tmp/fh-pre.html
grep -c '<option value=' /tmp/fh-pre.html
grep -ci 'fatal\|warning\|No pudimos cargar' /tmp/fh-pre.html
grep -c 'class="themeix-header"' /tmp/fh-pre.html
ssh root@138.197.150.98 'docker logs --since 5m recetalia-site 2>&1 | grep -i "farmacias-habilitadas\|error" | tail -5; docker exec recetalia-mysql sh -c "mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -N recetali_receta -e \"SELECT COUNT(*) FROM pharmacy p JOIN localities l ON l.id=p.addressLocalityId JOIN regions r ON r.id=l.region_id WHERE p.status=\\\"ACTIVE\\\"; SELECT COUNT(DISTINCT r.id) FROM pharmacy p JOIN localities l ON l.id=p.addressLocalityId JOIN regions r ON r.id=l.region_id WHERE p.status=\\\"ACTIVE\\\";\"" 2>/dev/null'
```
Esperado: `200`; filas `fh-item` = primer COUNT (302 al relevar); `<option` = segundo COUNT (19). (`grep 'class="fh-dep'` da 20 porque también matchea `fh-departamentos`.); 0 fatales; 1 header; sin errores en el log. Si sale `No pudimos cargar`, mirar `docker logs recetalia-site`: el mensaje de `error_log` dice si falló la conexión (credenciales/SSL) o la consulta.

- [x] **Step 6: Capturas de PRE en escritorio y celular**

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --ignore-certificate-errors --window-size=1366,1400 --screenshot=/tmp/fh-pre-desktop.png https://138.197.150.98:8443/farmacias-habilitadas.php 2>/dev/null
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --ignore-certificate-errors --window-size=390,1600 --screenshot=/tmp/fh-pre-mobile.png https://138.197.150.98:8443/farmacias-habilitadas.php 2>/dev/null
ls -la /tmp/fh-pre-*.png
```
Esperado: dos PNG mayores a 50 KB. Mirar las dos capturas (Read) y confirmar: columna de departamentos con Montevideo activo y la lista al lado en escritorio; selector arriba y filas apiladas en celular; sin texto cortado ni estilos rotos.

- [ ] **Step 7: Probar la interacción en PRE**

Pablo abre `https://138.197.150.98:8443/farmacias-habilitadas.php` (cert propio: aceptar la advertencia) y verifica a ojo:
1. Montevideo activo al entrar, contador "N farmacias en Montevideo".
2. Click en Canelones: cambia la lista y el contador; la búsqueda queda vacía.
3. Escribir "rio": aparecen farmacias de varios departamentos con su etiqueta; ningún departamento marcado.
4. Escribir "zzzz": "No encontramos farmacias con ese nombre."
5. Borrar el texto: vuelve al último departamento elegido.
6. Ancho de celular: aparece el selector; cambiarlo actualiza la lista; el teléfono queda debajo.
7. El teléfono es un enlace `tel:`.

Si algo no cierra: corregir en el repo, commit `fix(farmacias): ...`, repetir Steps 2, 4 y 5.

**CHECKPOINT: Pablo mira PRE y da el OK para PROD.** No seguir sin ese OK.

---


### Task 4: Deploy a PROD (`.217`)

**Files:** ninguno en el repo. Cambios en el server `159.203.26.217`.

- [x] **Step 1: Marcadores "antes" y rollback**

```bash
curl -s https://recetalia.com/farmacias-habilitadas.php | grep -c 'class="fh-item"'
ssh root@159.203.26.217 'docker tag registrypre.recetadigital.uy/recetalia/recetalia-site:latest registrypre.recetadigital.uy/recetalia/recetalia-site:rollback-2026-09-04 && docker images | grep recetalia-site'
```
Esperado: `0` (marcador nuevo ausente en PROD) y la imagen `rollback-2026-09-04` listada.

- [x] **Step 2: Sincronizar la fuente del sitio (dry-run primero)**

El `deploy.sh` sólo sincroniza `deploy-recetalia/`; la fuente del sitio va aparte a `/opt/recetalia/recetalia-site`. Ese directorio no tiene `htpasswd` ni `.env`: el riesgo del `--delete` de la memoria `deploy-98-gotchas-medidos` no aplica, pero igual se mira el dry-run.

```bash
cd /Users/pablo/iwtg/recetalia-workspace
rsync -az --delete --dry-run --itemize-changes --exclude .git --exclude tests recetalia-site/ root@159.203.26.217:/opt/recetalia/recetalia-site/ | grep -v '^\.d' | head -30
```
Esperado: aparecen `farmacias-habilitadas.php`, `inc/farmacias-habilitadas.php`, `.dockerignore` y nada con `*deleting` que no sea esperado. Si borra algo inesperado, frenar y mirar.

```bash
rsync -az --delete --exclude .git --exclude tests recetalia-site/ root@159.203.26.217:/opt/recetalia/recetalia-site/
ssh root@159.203.26.217 'md5sum /opt/recetalia/recetalia-site/farmacias-habilitadas.php'
md5 -q recetalia-site/farmacias-habilitadas.php
```
Esperado: los dos md5 iguales.

- [x] **Step 3: Rebuild y recreate sólo del sitio**

```bash
ssh root@159.203.26.217 'df -h / | tail -1; cd /opt/recetalia/deploy-recetalia && docker compose build recetalia-site 2>&1 | tail -5 && docker compose up -d --no-deps recetalia-site && docker ps --format "{{.Names}} {{.Status}}" | grep site'
```
Esperado: build termina sin error, `recetalia-site Up X seconds`. Ningún otro contenedor se recrea (`--no-deps`).

- [x] **Step 4: Verificar en PROD**

```bash
curl -s -o /tmp/fh-prod.html -w '%{http_code}\n' https://recetalia.com/farmacias-habilitadas.php
grep -c 'class="fh-item"' /tmp/fh-prod.html
grep -c '<option value=' /tmp/fh-prod.html
grep -ci 'fatal\|warning\|No pudimos cargar' /tmp/fh-prod.html
grep -c 'class="themeix-header"' /tmp/fh-prod.html
curl -s -o /dev/null -w '%{http_code}\n' https://recetalia.com/
ssh root@159.203.26.217 'docker logs --since 5m recetalia-site 2>&1 | grep -i "farmacias-habilitadas\|error" | tail -5'
```
Esperado: `200`; filas = las medidas en Task 3 (298 si la base no cambió); 19 departamentos; 0 fatales; 1 header; home `200`; sin líneas de error en el log del contenedor.

- [x] **Step 5: Capturas de PROD**

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --window-size=1366,1400 --screenshot=/tmp/fh-prod-desktop.png https://recetalia.com/farmacias-habilitadas.php 2>/dev/null
ls -la /tmp/fh-prod-desktop.png
```
Cloudflare cachea HTML sólo si hay page rule; si la captura muestra la versión vieja, purgar caché del path en Cloudflare y repetir el curl.

**Rollback** si algo falla:
```bash
ssh root@159.203.26.217 'cd /opt/recetalia/deploy-recetalia && docker tag registrypre.recetadigital.uy/recetalia/recetalia-site:rollback-2026-09-04 registrypre.recetadigital.uy/recetalia/recetalia-site:latest && docker compose up -d --no-deps recetalia-site'
```

---

### Task 5: Cierre

- [ ] **Step 1: Registrar lo medido en este plan**

Completar la sección "Medido" de abajo con los conteos reales de Task 3 y Task 4 y la fecha.

- [ ] **Step 2: Merge sólo con OK explícito de Pablo**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-site
git checkout main && git merge --no-ff feat/farmacias-habilitadas-rediseno -m "Merge feat/farmacias-habilitadas-rediseno — rediseño del listado de farmacias habilitadas"
git push origin main feat/farmacias-habilitadas-rediseno
```
El repo del sitio no sigue el numerado 2.x.y de las apps (último tag `2.1.3`); no se tagea salvo que Pablo lo pida.

- [ ] **Step 3: Backlog**

Agregar a `BACKLOG.md` (DESPUÉS, `[decisión · plataforma · M]`): "El sitio institucional no tiene PRE: sólo corre en el `.217`. Montarlo en el `.98` necesita `SITE_DB_*` contra la MySQL local sin SSL (la página fuerza `MYSQLI_CLIENT_SSL`) y disco (83 % usado)". Guardar el work status.

---

## Medido

| Qué | Dónde | Valor | Fecha |
|---|---|---|---|
| Farmacias activas (JSON de la página vieja) | PROD | 298 | 2026-09-04 |
| Departamentos | PROD | 19 | 2026-09-04 |
| Farmacias activas / departamentos / Montevideo | PRE (`.98`, MySQL local) | 302 / 19 / 153 | 2026-09-05 |
| Filas `fh-item` en PRE tras deploy (= COUNT de la DB) | PRE `https://138.197.150.98:8443` | 302, 0 fatales, 302 con teléfono | 2026-09-05 |
| HTML de la página nueva | PRE | 210.534 bytes (vieja en PROD: 103.520; la nueva lleva las 302 filas ya renderizadas) | 2026-09-05 |
| Filas `fh-item` en PROD tras deploy (= COUNT de la DB de PROD por el usuario read-only) | PROD `https://recetalia.com` | 298 / 19 deptos / Montevideo 151 · 0 fatales · home 200 · `cf-cache-status: DYNAMIC` (sin caché que purgar) | 2026-09-05 |
| Imagen de rollback en el `.217` | PROD | `recetalia-site:rollback-2026-09-04` = `5b96f18bc75a` (misma que `rollback-2.2.0`) | 2026-09-05 |

### Cambio de diseño tras el primer deploy a PROD (2026-09-05)

Pablo rechazó el layout B en PROD → acordeón clásico (todos cerrados, uno a la vez). Ver la sección
"Cambio de diseño en producción" de la spec. Commits `d02ccf2` (acordeón) y `a4b84fd` (clásico +
animación). Deployado a PRE (302/19/0 abiertas) y luego a PROD con su OK: **298 items / 19 regiones
/ 0 abiertas / 0 fatales / home 200**. La imagen de rollback sigue siendo la del layout viejo
(`rollback-2026-09-04`), no la del layout B.

### Hallazgos durante la Task 3 (2026-09-05)

- 🐛 **El `.98` corre CentOS 7 con kernel `3.10.0-514`** (Docker 26.1.4). `php:7.4-apache` (Debian bullseye, APR 1.7) exige `getrandom()` (kernel ≥ 3.17) → Apache muere en loop con `AH00141: Could not initialize random number generator` y el contenedor queda `Restarting (1)`. El `.217` (kernel 6.8) no lo sufre. **Fix:** `ARG PHP_BASE` en el `Dockerfile` del sitio (commit `ef39fcf`) + override `build.args.PHP_BASE=php:7.4-apache-buster` sólo en `docker-compose.dev98.yml` (commit `b4a80e4` en `deploy-recetalia`, rama `feat/farmacias-habilitadas-rediseno`). PROD sigue con la imagen default. Medido: con buster arranca (`Apache/2.4.38 PHP/7.4.33`) y el 8443 pasa de 502 a 200.
- ⚠️ **Íconos Font Awesome como cuadrados en PRE, no en PROD.** La página lleva `<base href="https://recetalia.com/">` (heredado; todas las páginas del sitio lo tienen), así que CSS, JS y **webfonts** se cargan desde PROD. Las fuentes cross-origin sin CORS se bloquean → cuadrados en `https://138.197.150.98:8443`. En PROD es same-origin y se ven (verificado en la home de PROD). No se toca.
- ⚠️ **Desborde horizontal a 390 px es preexistente del sitio:** la home y la página vieja de PROD también se salen por la derecha (header incluido) en la misma captura headless. Fuera de alcance; anotado en `BACKLOG.md`.
- El `.env` del `.98` quedó con backup `.env.bak-preSITE-20260904` y 5 líneas `SITE_DB_*` nuevas (`SITE_DB_PASS=${RECETALIA_DB_PASSWORD}`, interpolación verificada con `docker compose config`).
- Disco del `.98`: 83 % → 85 % tras el build (8,7 G libres). Build cache reclamable: 4,9 GB (`docker system df`).
