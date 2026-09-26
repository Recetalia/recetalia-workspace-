# Spec: Tope de cajas al dispensar según posología × presentación — 2026-06-12

## Regla de negocio

Al dispensar una receta, la cantidad de cajas no puede superar las necesarias para
cubrir la posología prescripta, según las unidades por caja de la presentación
comercial elegida.

Ejemplo: "1 comprimido cada 8 horas durante 8 días" = 24 comprimidos. Presentación
de 20 comprimidos → máximo **2 cajas** (40 comprimidos).

Aplica a **todas** las recetas (blancas, verdes, naranjas y crónicas) — la regla no
distingue `condvtaId`. En crónicas el tope es **por mes**: la cantidad que cubre un
mes de posología (la dispensación de meses siguientes repite el mismo tope).

## Fórmula (misma semántica en frontend y backend)

```
horasTratamiento   = esCrónica ? 30 × 24 : duration × 24      // duration en días
tomas              = ceil(horasTratamiento / frecuency)        // frecuency siempre en horas
unidadesNecesarias = tomas × dose                              // dose admite pasos de 0.5
maxCajas           = ceil(unidadesNecesarias / unidadesPorCaja)
```

- `unidadesPorCaja` = `vmpp.CANTIDAD` del vademécum DNMA (dato estructurado; el
  AMPP referencia su `vmppId`). No se parsea la descripción.
- Datos de posología: campos estructurados de la prescripción (`dose`, `frecuency`,
  `duration`, `isCronic`). En el alta de recetas (app médicos) la frecuencia siempre
  es horas y la duración es días (aguda) o meses (crónica).
- Mes crónico = **30 días fijos**.

### Fallback (decisión tomada)

Si el tope **no es computable** — `dose`/`frecuency`/`duration` nulos o ≤ 0,
`CANTIDAD` ausente/no numérica/≤ 0 — **no se topea**: el flujo se comporta como hoy
(cantidad libre). No se bloquean dispensaciones legítimas por datos sucios del
vademécum.

## Alcance (decisión tomada): frontend + backend

El tope se aplica en la UI de farmacias (clamp automático) **y** el API rechaza
dispensaciones que lo superen (defensa real ante llamadas directas).

## Cambios por proyecto

### 1. transversal-recetalia-api

- `AmppRepository.findByAmpId` (`infrastructure/driven-adapters/dnma-db/.../repository/AmppRepository.java`):
  agregar `LEFT JOIN vmpp ON vmpp.VMPP_Id = a.VMPP_Id` y seleccionar
  `vmpp.CANTIDAD`.
- Entidad `Ampp` (dnma-db): campo `@Column("CANTIDAD") private String cantidad`.
- `AmppDnmaDto` (domain/model): campo `cantidad`. El mapper MapStruct lo toma por
  nombre.

### 2. recetalia-api-rest

- `AmppDto` (`infrastructure/adapter/transversal/dto/AmppDto.java`): campo
  `cantidad` — Jackson lo mapea desde la respuesta del transversal y viaja al
  frontend sin más cambios.
- Nueva clase `DispensationCapCalculator` (función pura: posología + unidadesPorCaja
  → `Optional<Integer> maxCajas`; vacío si no computable). Con tests unitarios,
  incluyendo el ejemplo de control (24 unidades / caja de 20 → 2).
- `DnmaDatabaseService`: método para obtener `CANTIDAD` por AMPP id
  (`SELECT vmpp.CANTIDAD FROM ampp JOIN vmpp ... WHERE ampp.AMPP_Id = ?`), usando el
  datasource DNMA pooled existente.
- `DispensationServiceImpl.create()`: si el tope es computable y
  `request.qty > maxCajas` → **400** con mensaje
  `"La cantidad supera el máximo permitido por la posología: máximo N cajas"`.
  Si no es computable → no valida.

### 3. farmacias-recetalia-app

- Interfaz `Ampp` y `AmppResponse`: campo `cantidad`.
- `prescription-search.component`:
  - Al seleccionar presentación (normal o sustituto) se calcula `maxCajas` con la
    posología del grupo y la `cantidad` del AMPP elegido.
  - Input Cantidad: clamp automático al máximo (escribir 4 con max 2 vuelve a 2;
    mínimo 1 se mantiene). Sin diálogo de error ni bloqueo del botón Dispensar.
  - Leyenda bajo el input cuando hay tope:
    `"Máximo N cajas (M unidades según posología)"`.
  - El flujo de sustituto usa el max de su propia presentación.
  - Sin datos → sin tope ni leyenda (comportamiento actual).

## Branches

`fix/ajustes-farmacias-2026-06` desde `2.x.y` en los tres repos (ya creada en
farmacias-recetalia-app; crear en recetalia-api-rest y transversal-recetalia-api al
implementar).

## Testing

- **Backend**: tests unitarios de `DispensationCapCalculator` (aguda, crónica,
  redondeos con frecuencias no divisoras, dose fraccionada 0.5, fallbacks por dato
  faltante) y test del rechazo 400 en el servicio de dispensación.
- **Frontend**: build OK + verificación manual en PRE con una receta real (aguda y
  crónica), incluyendo el caso del screenshot (clonazepam, 4 → clamp a 2).
- **Contrato**: verificar con curl que `/api/ampp/search/amp` devuelve `cantidad`.
