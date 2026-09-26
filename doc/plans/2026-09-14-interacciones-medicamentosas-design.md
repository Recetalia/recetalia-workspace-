# Spec: Chequeo de interacciones medicamentosas — 2026-09-14

## 1. Objetivo

Avisar al médico, **en el momento en que agrega un medicamento**, si interactúa con
otro que el paciente va a tomar. El aviso no bloquea: informa y queda registrado.

Fuentes habilitadas, todas de uso comercial libre:

| Fuente | Rol | Licencia |
|---|---|---|
| DNMA (MSP/AGESIC) | identificar el medicamento local y su principio activo | propia |
| RxNorm (NLM) | normalizar principio activo → RxCUI + sinónimos/marcas | dominio público |
| openFDA Drug Label | texto de `drug_interactions` como evidencia | dominio público |

**Excluidos por licencia:** DDInter, DrugBank no comercial, y todo dataset
CC BY-NC-SA. Una API paga (DrugsAPI, DrugBank Clinical) es decisión de negocio
aparte, fuera de este alcance.

## 2. Ubicación: `recetalia-api-rest`

Decidido contra `transversal-recetalia-api`. Los dos tienen acceso propio a la base
`recetali_dnma` (`api-rest` por JDBC vía `DnmaDataSourceConfig`; transversal por
R2DBC), así que el acceso al dato no desempata.

Desempata que el servicio tiene que ser consumible por doctorconsultas y doctorsuite:

| | `recetalia-api-rest` | `transversal-recetalia-api` |
|---|---|---|
| Auth entrante | JWT HS512 (`SecurityConfiguration`) | ninguna |
| Expuesto por nginx | sí | no, y es deliberado (`deploy-recetalia/nginx/conf.d/20-apis.conf`) |
| Caché | Caffeine + `@EnableCaching` | ninguna |
| Cliente HTTP saliente | `RestTemplate` + patrón puerto/`Imp` | módulo `rest-consumer` declarado y vacío |
| Convención de migraciones | `doc/migrations/*.sql` + rollback | ninguna |

Ponerlo en el transversal obliga a construir auth, exposición, caché y cliente HTTP
desde cero. El transversal hoy no es un servicio compartido hacia afuera: es un
backend interno privado cuyo único cliente es `api-rest`.

## 3. Hechos del modelo de datos que corrigen el planteo inicial

Relevados sobre el código y el dump `db-dumps/prod-recetali_dnma-2026-06-29.sql`:

1. **No hay SNOMED CT a nivel sustancia ni producto.** Sólo en `ffa`, `ffe`,
   `unidad`, `via_admin` (formas, unidades, vías). El identificador de un
   medicamento recetado es el par **`productType`** (`"AMP"`/`"VMP"`) +
   **`productId`** (`AMP_Id` o `VMP_Id`), embebido en la fila de `prescription`.
2. **Una receta = un solo medicamento.** No existe `prescription_item` ni
   equivalente. El conjunto a chequear lo arma quien llama, no la receta.
3. **Un producto puede tener varias sustancias.** Por eso
   `DnmaDatabaseServiceImpl.fetchSubstancesByAmpIds` hace
   `GROUP_CONCAT(... SEPARATOR ' + ')`. El chequeo es **sustancia × sustancia**,
   no producto × producto.
4. ~~**`sustancia.DCI`** es el campo correcto para matchear contra RxNorm.~~
   **FALSO — corregido el 2026-09-15.** `DCI` no es un nombre: es un **código
   numérico** (`1919`, `7505`, y `0` en muchas filas). El único nombre utilizable
   es **`SUSTANCIA_DSC`**, y está en español con la sal incluida:
   `diclofenac potásico`, `ketorolac trometamina`, `folitropina alfa`.
   Medido sobre `db-dumps/prod-recetali_dnma-2026-06-29.sql`: 1.390 sustancias.
5. **`vmp.ATC_Id`** existe y no lo usa nadie. Código internacional público,
   disponible como ancla o fallback si RxNorm no resuelve.
6. El app de médicos **sí** tiene flujo multi-medicamento:
   `medics-recetalia-app/.../prescription-add/prescription-add.component.ts`
   acumula `prescriptionsRequest: PrescriptionRequest[]` y al emitir dispara N
   POSTs a `/prescriptions`, agrupados sólo por prefijo del campo `code`
   (`<GUID6>-A`, `-B`, …). No hay entidad "consulta".

## 4. Decisiones

| # | Decisión | Por qué |
|---|---|---|
| D1 | Vive en `recetalia-api-rest` | ver §2 |
| D2 | **Advertencia + registro**, no bloqueo | la severidad es heurística sobre texto libre; bloquear un acto médico con eso asume una responsabilidad que la fuente no respalda |
| D3 | **Endpoint sin estado**: recibe lista plana de productos | sirve igual a Recetalia y a consumidores externos, que no tienen pacientes en nuestro padrón. La regla de vigencia queda en quien llama |
| D4 | **openFDA fuera del camino de la request** | openFDA no tiene endpoint por par: devuelve labels por medicamento. Lo cacheable es el texto por sustancia. En caliente serían 2-4 llamadas HTTP a la FDA por medicamento agregado, con rate limit de 240 req/min por IP |
| D5 | **Lazy fill** ante sustancia sin texto | evita el "esperá hasta mañana" para altas nuevas del DNMA; el job nocturno pasa a refrescar, no a ser la única vía de carga |
| D6 | Disparo **al agregar cada medicamento** | el aviso llega pegado a la decisión que lo causa, no cuando la receta ya está armada |
| D7 | Severidad evaluada **sobre la oración que matcheó** | `drug_interactions` tiene varias páginas; un "contraindicated" lejano satura todo a severidad alta |
| D8 | `sinHallazgos` como lista explícita | "no hay evidencia" ≠ "no hay riesgo"; colapsarlos le da al médico una confianza que la fuente no respalda |

## 5. Arquitectura

### 5.1 Capa de precálculo (batch)

Job `@Scheduled` en `infrastructure/scheduler/` (donde ya vive
`ControlDashboardScheduler`). Nocturno, idempotente, re-corrible.

| Tabla | Contenido |
|---|---|
| `drug_substance_rxnorm` | `SUSTANCIA_ID` → `rxcui`, `matchMethod` (`exact`/`approximate`/`manual`/`unresolved`), `matchScore`, `updatedAt` |
| `drug_substance_rxnorm_alias` | overrides manuales; el job **no los pisa** |
| `drug_substance_synonym` | `rxcui` → nombres y marcas comerciales, de RxNorm |
| `drug_interaction_label` | `rxcui` → texto de `drug_interactions`, `fechaEvidencia`, fuente |

Secuencia por sustancia: `findRxcuiByString(DCI)` → si falla,
`getApproximateMatch` guardando score → si falla, `unresolved` al reporte.
Luego sinónimos por RxCUI, y label de openFDA por nombre
(`openfda.generic_name` / `openfda.substance_name` — openFDA no indexa por RxCUI).

`drug_substance_synonym` no es accesorio: los labels de la FDA nombran los
medicamentos por marca tanto como por genérico. Buscar sólo el nombre canónico
pierde una parte importante de los hallazgos.

### 5.2 Capa de chequeo (request path, sin red)

```
productos → sustancias (JDBC a DNMA)
          → rxcui (drug_substance_rxnorm)
          → por cada par (A,B): sinónimos de B dentro del texto de A, y viceversa
          → extraer la oración que matcheó
          → clasificar severidad sobre esa oración
          → respuesta
```

Caffeine queda como capa caliente sobre las tablas, no como sustituto: se vacía
en cada restart. Cachés nuevas declaradas en `CacheConfig` (el `CacheManager`
está con nombres fijos en el constructor).

### 5.3 Clientes externos

`RxNormClient` y `OpenFdaClient` como puertos en
`infrastructure/adapter/<proveedor>/`, siguiendo `DnmaRestConsumerPortImp`.
Backoff ante 429. Sin autenticación en RxNorm; API key de openFDA opcional
(gratis) si el volumen lo justifica.

## 6. Contrato

**`POST /api/drug-interactions/check`**

```json
{ "productos": [
    { "productType": "AMP", "productId": "12345" },
    { "productType": "VMP", "productId": "678" } ] }
```

```json
{
  "hallazgos": [
    { "par": [{"productType":"AMP","productId":"12345"},
              {"productType":"VMP","productId":"678"}],
      "sustancias": ["warfarina", "ibuprofeno"],
      "severidad": "high|moderate|unclassified",
      "evidencia": "<la oración que matcheó>",
      "textoCompleto": "<drug_interactions completo>",
      "fuente": "openFDA drug label",
      "fechaEvidencia": "2026-08-30" } ],
  "sinHallazgos": [
    { "par": [...], "motivo": "sin mención recíproca en los labels consultados" } ],
  "noEvaluables": [
    { "productType": "AMP", "productId": "999",
      "motivo": "sustancia sin mapeo RxCUI" } ],
  "disclaimer": "Información generada automáticamente a partir de fuentes públicas (FDA). No sustituye el criterio clínico. Verificar con el prospecto oficial ante cualquier duda."
}
```

El disclaimer va también visible en la UI, no sólo en la respuesta.

**Severidad (v1, por keywords sobre la oración):**

- `high` — "contraindicated", "should not be used", "avoid concomitant"
- `moderate` — "caution", "monitor", "may increase", "may decrease"
- `unclassified` — sin match; se devuelve el texto igual

Detrás de una interfaz `SeverityClassifier` con una sola implementación, para
reemplazarla sin tocar el motor. El texto original siempre acompaña a la
severidad calculada; nunca la reemplaza.

**Auth:** `requestMatchers("/api/drug-interactions/**")` en
`SecurityConfiguration` — única vía, porque el proyecto no tiene
`@EnableMethodSecurity` y los `@PreAuthorize` no se evalúan. Habilitado para el
rol de médico y para `ROLE_MEDICAL_PROVIDER_API` (usuario-API por prestador), que
es el mecanismo service-to-service existente y la puerta de doctorconsultas y
doctorsuite. **Gotcha:** doble prefijo real `ROLE_ROLE_…`.

## 7. Trazabilidad

Dos piezas, porque chequeo y decisión ocurren en momentos distintos:

- **`drug_interaction_check`** — log append-only por chequeo: `requestedBy`
  (claim `mail` del JWT), `checkedAt`, productos consultados, `maxSeverity`,
  cantidad de hallazgos y de no evaluables. Varias filas por consulta, ya que el
  disparo es incremental.
- **`prescription.interactionCheckId` + `prescription.interactionAcknowledged`** —
  persistidos al emitir cuando había advertencia a la vista. Responden
  "¿esta receta se emitió sabiendo?", que es la pregunta con valor defensivo.
  A diferencia de `UpsertPrescriptionRequest.substanceName`, que hoy existe en el
  request y no lo lee nadie, estos campos **se persisten**.

Migraciones: `doc/migrations/2026-09-14-drug-interactions.sql` + `-rollback.sql`,
idempotentes vía `information_schema`, tablas `snake_case`, columnas `camelCase`.

## 8. Observabilidad

- Log por chequeo (medicamentos, resultado, usuario), mismo criterio que el resto
  de SAMC/doctorhub.
- **Métrica de cobertura**: % de sustancias del DNMA con RxCUI resuelto, logueada
  por el job en cada corrida. Es el indicador que dice si el feature sirve.

## 9. Pruebas

- `InteractionCheckerService` con mocks: par con hallazgo; par sin mención
  recíproca; sustancia sin RxCUI; producto con varias sustancias.
- Clasificador: caso conocido (warfarina + AINE → al menos `moderate`) y el caso
  que prueba D7 — un "contraindicated" lejano **no** eleva la severidad.
- Job de sync: idempotencia; no pisar alias manuales.
- Lazy fill: sustancia sin texto en tabla; openFDA caído durante el lazy fill →
  el par sale como no evaluable, nunca 500.

## 10. Riesgo principal: cobertura

La cobertura real es la intersección de tres conjuntos, y los tres cortan:

1. sustancias del DNMA,
2. que mapeen a RxNorm — el DNMA está en español con INN (`paracetamol`,
   `dipirona`, `adrenalina`), RxNorm en inglés con USAN (`acetaminophen`,
   `metamizole` —ni aprobado en EE.UU.—, `epinephrine`),
3. que tengan label FDA con `drug_interactions` — varios medicamentos de uso
   corriente en Uruguay nunca pasaron por la FDA, así que no hay label posible.

Es probable que `noEvaluables` sea una lista grande en la primera corrida. Por eso
la métrica de cobertura va desde el día uno.

## 11. Arreglo puntual de paso

`DnmaDatabaseServiceImpl` arma sus `IN (...)` concatenando ids en el string SQL
(SQL injection latente). Las consultas **nuevas** de este feature van con
`PreparedStatement`. Las existentes no se tocan: es otro trabajo.

## 12. Abierto

- Definir con quién (farmacéutico / D.T.) se revisan los `unresolved` del job.
- Sumar los medicamentos vigentes del paciente al chequeo requiere un filtro por
  `expireAt` que hoy no existe: `PrescriptionRepository.findPrescriptionsByPatientIdAndMedicalProviderId`
  filtra por `status`, nunca por vencimiento.
