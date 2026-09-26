# Spec: Cantidad de cajas en Gestión (dispensaciones + detalle de farmacia) — 2026-06-17

## Contexto y hallazgo

Replica en `gestion-recetadigital-app` lo que se hizo en farmacias: mostrar la cantidad de
cajas dispensada. Hallazgos de la exploración:

- Gestión consume el MISMO endpoint `GET /api/dispensations/search` que farmacias, que ya
  devuelve `dispensationQty` (Integer, cajas) y `dispensationProductName` (nombre del AMPP,
  resuelto contra la tabla `ampp` — fix de backend ya mergeado y desplegado).
- El modelo de gestión `dispensation-search-row.ts` **ya tiene** `dispensationQty`,
  `dispensationProductName`, `dispensationSubstitute`, `dispensationProductId`.
- Gestión **ya muestra la presentación** (AMPP) en la tabla (`displayDispensationProductName`)
  y en el modal (`detail.dispensationProductName`). **Solo falta la cantidad de cajas.**
- **Gestión > Farmacias > detalle** abre la MISMA `DispensationListComponent` en un modal
  scopeado por `pharmacyId` (`openDispensations(pharmacy)`), así que un solo cambio en la
  lista/modal cubre ambas pantallas.

**No hace falta tocar backend ni modelos.** Es display + exports, solo en gestión.

## Objetivo

Mostrar la cantidad de cajas (`dispensationQty`) en la tabla y el modal de dispensaciones de
gestión, y agregarla a los exports Excel y PDF. Cubre automáticamente la pantalla de
dispensaciones y el detalle de farmacia (reusan el componente).

## Cambios (frontend, solo gestion-recetadigital-app)

### 1. Tabla de Dispensaciones (`dispensation-list.component.html`)

- Header: nueva columna `<th>Cantidad</th>` después de MEDICAMENTO.
- Body: celda `<td>{{ r.dispensationQty }} {{ r.dispensationQty === 1 ? 'caja' : 'cajas' }}</td>`
  en la misma posición.

### 2. Modal de detalle (`dispensations-info.component.html`)

- En la sección MEDICAMENTO, debajo del nombre del AMPP y antes/junto a "Sustitución":
  `Cantidad: {{ detail.dispensationQty }} {{ detail.dispensationQty === 1 ? 'caja' : 'cajas' }}`
  con `*ngIf="detail.dispensationQty != null"`. Igual que farmacias.

### 3. Export Excel (`dispensation-file.service.ts`)

- Agregar "Cantidad" al array de header, y `r.dispensationQty ?? ''` (o `0`) en el mismo
  índice del array de data, manteniendo el orden de columnas coherente con el header.

### 4. Export PDF (`dispensation-file.service.ts`)

- Agregar la cantidad de cajas en el PDF, en la posición/columna análoga al medicamento,
  siguiendo la estructura existente del PDF (tabla o detalle, según como esté armado).

## Decisiones tomadas

- Se incluye la cantidad en Excel **y** PDF (decisión del usuario).
- La presentación (AMPP) NO se toca: ya se muestra en gestión.
- Se mantiene la paridad de formato con farmacias ("N caja"/"N cajas", singular/plural).

## Fuera de alcance

- Backend / modelos (el dato ya llega y los campos ya existen).
- Buscar Prescripción (gestión no dispensa; esa pantalla es de farmacias).
- Cambios en farmacias (ya hechos).

## Testing

- Build de gestión OK.
- Verificación visual en PRE (con la imagen de gestión redeployada): columna "Cantidad" y
  línea "Cantidad: N cajas" en el modal, tanto en Gestión > Dispensaciones como en
  Gestión > Farmacias > (detalle) > Dispensaciones. Export Excel y PDF con la columna.
- Datos de prueba: dispensaciones con qty variado (DD264F-A=3, 62A4CD-C=100, 0D1D38-A=8).

## Branch

Crear `fix/ajustes-gestion-2026-06` en gestion-recetadigital-app desde `2.x.y` (o reusar el
patrón de branch de ajustes). NO mergear hasta OK de Pablo.
