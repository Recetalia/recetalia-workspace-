# Spec: Mostrar cantidad de cajas y presentación dispensada — 2026-06-17

## Contexto y hallazgo

Al dispensar desde Farmacia ya se persiste TODO lo necesario en la tabla `dispensation`:
- **Cantidad de cajas** → `dispensation.qty` (Integer, NOT NULL, default 1). Valores reales
  en PRE: `DD264F-A`=3, `0D1D38-A`=8, `62A4CD-C`=100, `62A4CD-A`=40, `F09D96-A`=12.
- **Presentación dispensada** → `dispensation.productId` (AMPP id) + `productType` + `substitute`.

**No hace falta cambiar el modelo de datos ni la base.** El gap es de presentación:
- `qty` ya viaja en la respuesta de búsqueda de dispensaciones (`getDispensationQty()` →
  `dispensationQty` en el modelo del frontend) pero no se pinta en ninguna pantalla.
- El nombre del AMPP dispensado ya se resuelve y se muestra en el modal (fix previo,
  resuelto contra la tabla `ampp`).
- La pantalla de Buscar Prescripción NO tiene ningún dato de la dispensación
  (`PrescriptionResponse` no incluye nada de `dispensation`).

## Objetivo

Mostrar la cantidad de cajas (y la presentación) dispensada en tres lugares, sin tocar
el modelo de datos. Sentar la base para estadísticas futuras (ya disponible vía
`qty` + `productId` + laboratorio + fecha; fuera de alcance de este spec).

## Parte A — Cantidad de cajas en Farmacia > Dispensaciones (solo frontend)

El dato `dispensationQty` ya está en `DispensationSearchRow` (frontend) y en la respuesta.

1. **Modal de detalle** (`dispensations-info.component.html`): en la sección MEDICAMENTO,
   debajo del nombre del AMPP, agregar una línea con la cantidad de cajas:
   `Cantidad: {{ detail.dispensationQty }} {{ detail.dispensationQty === 1 ? 'caja' : 'cajas' }}`.
   Queda junto a la línea "Sustitución: SI/NO" existente.

2. **Columna en la tabla** (`dispensation-list.component.html`): nueva columna "CANTIDAD"
   (cajas) en la tabla de dispensaciones, mostrando `dispensationQty`. Ubicación: entre
   MEDICAMENTO y FECHA DISP. Mantener el estilo/orden de columnas existente.

Sin cambios de backend (el campo ya se selecciona y expone).

## Parte B — Presentación + cajas dispensadas en Farmacia > Buscar Prescripción (backend + frontend)

Cuando una prescripción del código buscado ya fue dispensada, mostrar qué se entregó.

### Backend (recetalia-api-rest)

- `PrescriptionResponse`: agregar dos campos opcionales (nullables):
  `Integer dispensedQty` y `String dispensedPresentation` (nombre del AMPP dispensado).
  Null para prescripciones no dispensadas. No rompe otros consumidores (campos nuevos
  opcionales).
- **Cambio de filtro (decisión tomada):** hoy `searchAvailablePrescriptionsByCodePrefix`
  descarta los grupos que no tienen ningún mes `AVAILABLE`/`CANCELLED`, así que una receta
  totalmente dispensada devuelve vacío. Se elimina ese filtro de grupo para que el search
  devuelva TODAS las prescripciones del código (incluidas las totalmente dispensadas), así
  se puede mostrar lo entregado. (El nombre del método/endpoint se mantiene para no romper
  el front; cambia solo la semántica.)
- `searchAvailablePrescriptionsByCodePrefix` (servicio detrás de
  `GET /api/prescriptions/search-available-Prescriptions-by-code`): para las
  prescripciones que tienen dispensación (no borrada), poblar:
  - `dispensedQty` desde `dispensation.qty`.
  - `dispensedPresentation` resolviendo `dispensation.productId` contra la tabla `ampp`
    (`AMPP_DSC`) vía `DnmaDatabaseService` — mismo patrón que el enriquecimiento de
    la búsqueda de dispensaciones (`fetchAmppDetails`). Resolución en lote para no hacer
    N consultas (juntar los productId de las dispensadas y resolver de una).
  - Si no hay dispensación, ambos quedan null.

### Frontend (farmacias-recetalia-app)

- `PrescriptionResponse` (modelo): agregar `dispensedQty?: number | null` y
  `dispensedPresentation?: string | null`.
- `prescription-search.component.html`: para una prescripción/mes **ya dispensado**,
  mostrar "Dispensado: \<dispensedPresentation\> — N cajas" **en lugar** del formulario de
  dispensar de ese ítem. Los meses aún disponibles (crónicas/paquetes) conservan el
  formulario normal. Una prescripción común single ya dispensada muestra solo el texto
  de lo dispensado (sin formulario).

## Decisiones tomadas

- Para ítems ya dispensados se **reemplaza** el formulario por el texto de lo dispensado
  (no se muestra además). Los disponibles mantienen el formulario.
- Una receta **totalmente dispensada** (single o crónica con todos los meses dispensados)
  ahora **aparece** en Buscar Prescripción mostrando lo entregado, en vez de "no hay
  prescripciones" (requiere quitar el filtro de grupo del backend).
- No se snapshotea el nombre/unidades del AMPP al dispensar (se resuelve on-read del
  vademécum). Suficiente hoy; se podría blindar a futuro si los reportes lo requieren.

## Fuera de alcance

- Exportaciones Excel/PDF de dispensaciones (no pedidas en esta iteración).
- Cambios en el modelo de datos / base (no hacen falta).
- Pantalla/feature de estadísticas (el dato queda disponible para cuando se encare).

## Testing

- **Backend:** test del enriquecimiento de `searchAvailablePrescriptionsByCodePrefix`
  (prescripción dispensada → `dispensedQty` y `dispensedPresentation` poblados; no
  dispensada → null; resolución de AMPP contra `ampp`).
- **Frontend:** build OK; verificación visual en PRE — modal muestra "Cantidad: N cajas";
  tabla muestra la columna; Buscar Prescripción de un código con prescripción dispensada
  muestra "Dispensado: … — N cajas". Casos: común single dispensada, crónica con meses
  mixtos (dispensados + disponibles).
- **Datos de prueba PRE:** dispensaciones existentes con qty variado (`DD264F-A`=3,
  `0D1D38-A`=8 sustituto, `62A4CD-C`=100).

## Branch

`fix/ajustes-farmacias-2026-06-2` (ya creada en farmacias-recetalia-app; crear la misma
en recetalia-api-rest al implementar la Parte B). NO mergear hasta OK de Pablo.
