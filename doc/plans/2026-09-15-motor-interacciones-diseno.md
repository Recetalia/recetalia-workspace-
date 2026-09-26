# Motor de interacciones medicamentosas — diseño

Cómo queda el motor de Recetalia tras adoptar el fork de PillChecker.
Reemplaza el motor RxNorm+openFDA de
[2026-09-14-interacciones-medicamentosas-design.md](2026-09-14-interacciones-medicamentosas-design.md),
que queda como referencia histórica y como plan B (§9).

Todos los números de este documento están medidos, no estimados. La fuente de
cada uno está indicada.

---

## 1. La forma general

Dos servicios, dos responsabilidades:

```
  doctorconsultas ─┐
  doctorsuite ─────┤
  medics-app ──────┴──► recetalia-api-rest  (Java / Spring Boot)
                          │  • contrato público y autenticación
                          │  • DNMA: producto → sustancias
                          │  • mapeo sustancia → nombre canónico
                          │  • trazabilidad
                          │
                          ▼  HTTP interno, red docker
                        pillchecker-recetalia  (Python / FastAPI)
                          │  • DDInter: par → severidad estructurada
                          │  • RxNorm: nombre → RxCUI
                          │  • openFDA: respaldo textual
                          ▼
                        ddinter.db  (SQLite, horneado en la imagen)
```

**La división es deliberada.** El motor no sabe nada de Recetalia: recibe nombres
de droga y devuelve interacciones. Todo lo que es nuestro —DNMA, pacientes,
recetas, roles, auditoría— vive del lado Java. Eso mantiene al motor reemplazable
y hace que un cambio de fuente de datos no toque el contrato público.

---

## 2. Qué hay realmente en DDInter

Medido sobre los 8 CSV descargados de `ddinter2.scbdd.com` el 2026-09-15:

| | |
|---|---|
| Filas en los CSV | 222.383 |
| **Pares únicos en el `.db`** | **160.235** |
| Drogas distintas | **1.939** |
| Drogas con RxCUI | **1.869 — 96,4 %** (todas por match exacto) |
| CSV / `.db` construido | 13 MB / **23 MB** |

Los 222.383 incluyen duplicados: un par aparece en el archivo de cada categoría
ATC que le corresponde, y la PK `(drug_a_id, drug_b_id)` los colapsa a 160.235.

El `.db` se construyó localmente el 2026-09-15 desde los CSV originales
(`fetch` → `resolve-rxnorm` → `build`), **no** desde el GitHub Release de la
autora. Vive en `data/ddinter.db` y está gitignoreado: **en nuestro git no hay
ni un byte de DDInter**. Con él presente, la suite pasa a **107 tests, 1
skippeado**, e incluye el gate de regresión de severidades.

Distribución de severidad:

| Nivel | Pares | % |
|---|---|---|
| Moderate | 130.367 | 58,6 % |
| **Unknown** | **47.182** | **21,2 %** |
| Major | 33.896 | 15,2 % |
| Minor | 10.938 | 4,9 % |

**Uno de cada cinco pares no tiene severidad.** `Unknown` no es un error nuestro:
es un valor de primera clase en el dataset. El diseño tiene que tratarlo como
"hay interacción documentada, se desconoce la gravedad" — que es información
útil, distinta tanto de "grave" como de "no hay nada".

### Las categorías ATC ausentes SÍ son un problema — pero no el que parecía

DDInter 2.0 publica 8 de 14 categorías (`A, B, D, H, L, P, R, V`; faltan
`C, G, J, M, N, S`).

**Los fármacos no faltan.** Los archivos particionan por el ATC de *una* de las
dos drogas del par, así que las de categorías ausentes aparecen igual como
contraparte. Verificado contra 31 principios activos de atención primaria: **27
están presentes**, incluidos ibuprofeno (M), enalapril y losartán (C),
sertralina (N), amoxicilina (J).

**Lo que falta son los pares entre ellos.** Medido el 2026-09-15:

```
Warfarin (B)   → A:99  B:765
Enalapril (C)  → A:108 B:32 D:27 H:11 L:64 P:1 R:26 V:8
                 ...y ninguna en C, porque C no se publica
```

| Par | ¿Está? |
|---|---|
| Warfarina + Ibuprofeno | ✅ major |
| Diclofenac + Ibuprofeno | ✅ moderate — se salva por categoría `D`: ambos tienen forma tópica |
| **Enalapril + Losartán** (C+C) | ❌ |
| **Sertralina + Fluoxetina** (N+N) | ❌ |
| **Amlodipina + Atorvastatina** (C+C) | ❌ |

Quedan fuera **cardiovascular × cardiovascular** y **SNC × SNC**: dos
antihipertensivos, dos serotoninérgicos (síndrome serotoninérgico), dos fármacos
que prolongan QT. Es un hueco clínicamente serio y hay que taparlo con otra
fuente o con curación propia — no se resuelve mejorando el mapeo de nombres.

⚠️ Una versión anterior de este documento afirmaba que la ausencia de categorías
"no es un problema de cobertura". Era cierto para los fármacos y falso para los
pares. Corregido con la medición de arriba.

### Por qué son sólo 1.939 fármacos

Dos razones que se suman: DDInter no es un vademécum sino un catálogo curado de
fármacos con interacciones de relevancia clínica (RxNorm tiene ~20.000
ingredientes), y el catálogo queda anclado a los 8 archivos publicados — una
droga entra sólo si aparece en alguno.

Lo que sí es denso: **165 interacciones por fármaco en promedio**.

Los 4 ausentes son un problema de **nombre**, no de cobertura:

| Buscado | Realidad |
|---|---|
| `paracetamol` | está como `acetaminophen` |
| `aspirin` | está como `acetylsalicylic acid` |
| `dipyrone` / `metamizole` | **ausencia real** — nunca aprobado por la FDA |

La dipirona es el único hueco genuino de los probados, y es de uso corriente en
Uruguay. Va a la lista de no evaluables.

---

## 3. El problema central: nombres

El DNMA de producción tiene **1.390 sustancias**
(`db-dumps/prod-recetali_dnma-2026-06-29.sql`). Sus nombres están en
`SUSTANCIA_DSC`, **en español y con la sal incluida**: `diclofenac potásico`,
`ketorolac trometamina`, `folitropina alfa`.

⚠️ **`sustancia.DCI` no sirve.** Pese al nombre, no contiene la Denominación
Común Internacional: es un **código numérico** (`1919`, `7505`, y `0` en muchas
filas). El spec anterior afirmaba lo contrario y fue corregido.

Comparación directa de nombres DNMA ↔ DDInter, normalizando acentos y quitando
sales: **270 de 1.390 — 19,4 %**. Ése es el **piso**, no la cobertura esperada,
por dos razones:

1. La resolución real pasa por RxNorm (español → RxCUI → nombre canónico en
   inglés → DDInter), que absorbe buena parte de la divergencia.
2. Una porción grande de lo no resuelto **no son fármacos con interacciones**:
   `azufre`, `betacaroteno`, `spirulina`, `alcanfor`, `extracto de Ruibarbo`,
   `óxido nitroso`, vacunas BCG, inmunoglobulinas, factores recombinantes.
   Nunca van a estar en DDInter y no deberían contar como fallo de cobertura.

### La escala del DNMA — medida el 2026-09-16

Sobre `db-dumps/prod-recetali_dnma-2026-06-29.sql`:

| tabla | filas | qué es |
|---|---|---|
| `sustancia` | 1.390 | principio activo |
| `vmp` | 3.424 | producto virtual |
| `amp` | **6.847** | producto comercial |
| `ampp` | 10.654 | presentación |
| `laboratorio` | 409 | |

**Cinco productos comerciales por sustancia.** Que haya 1.390 sustancias para
6.847 productos es lo esperable: el ibuprofeno aparece en decenas de marcas.

⚠️ El dump de PRE (`pre-dnma-ACTUAL.sql`) trae **más** datos que el de PROD:
1.526 sustancias y 7.548 AMP. Todo lo de acá está medido contra PROD, que es lo
que está vivo. Vale entender por qué divergen.

### Cobertura por producto — el número que hay que mostrar

Un médico no elige una sustancia: elige un producto. Medido sobre los 6.847 AMP,
resolviendo sus sustancias por `amp → vmp → vmp_sustancia`:

| | AMP | % |
|---|---|---|
| **Evaluable** (todas sus sustancias mapeadas) | **4.077** | **59,5 %** |
| Ninguna mapeada | 1.396 | 20,4 % |
| Sin sustancia asociada **en el propio DNMA** | 657 | 9,6 % |
| Parcial (alguna mapeada) | 378 | 5,5 % |
| No evaluable por naturaleza | 339 | 5,0 % |

Sobre los 5.264 productos **comercializados** da prácticamente igual: 59,3 %.

**59,5 % por producto contra 52,7 % por sustancia.** Sube porque las sustancias
comunes están en más productos, que es exactamente el efecto que anticipaba
medir ponderado en vez de por catálogo.

**657 productos (9,6 %) no tienen ninguna sustancia asociada en el DNMA.** Su VMP
no tiene filas en `vmp_sustancia`. Es un hueco del dato del MSP, no nuestro, y
ningún mapeo lo arregla: esos productos son inevaluables por construcción.

### Cobertura por sustancia — medida el 2026-09-15

`resolve_dnma_substances.py` sobre las 1.390 sustancias, con limpieza de sal y
verificación por nombre:

| | n | % de 1.390 |
|---|---|---|
| Resuelven a un fármaco **de la base** | **733** | 52,7 % |
| Resuelven a RxNorm pero **DDInter no las tiene** | 208 | 15,0 % |
| No resuelven | 357 | 25,7 % |
| No evaluables por naturaleza | 92 | 6,6 % |

**Cobertura sobre los 1.298 fármacos reales: 56,5 %.**

**El hallazgo que cambia dónde poner el esfuerzo.** Limpiar la sal recuperó 114
sustancias que antes no resolvían (`diclofenac potásico` → `diclofenac`), y
llevó el total resuelto contra RxNorm a **941 — 72,5 %**. Pero de esas 114,
**sólo ~10 existen en DDInter**: el resto resolvió a un RxCUI que DDInter no
cubre (`folitropina`, `gluconato de magnesio`, `fenol`, `dexpantenol`,
`riboflavina`, `dimeticona`).

O sea: **el cuello de botella no es el matcheo de nombres, es la lista de 1.939
fármacos de DDInter.** Seguir puliendo la resolución no va a mover la aguja. El
esfuerzo rinde en sumar fuentes de interacciones, o en curar a mano los fármacos
de uso corriente en Uruguay que DDInter no trae.

La rama de match aproximado **no aceptó ni un caso**: todo lo que mejoró entró
por match exacto sobre el nombre limpio. La verificación por nombre rechazó el
resto, que es lo buscado — prefiere no mapear antes que mapear mal.

### Consecuencia de diseño

La métrica de cobertura tiene que distinguir tres cosas, no dos:

- **resuelto** — la sustancia llegó a DDInter,
- **no resoluble** — es un insumo, una vacuna o un producto sin interacciones
  documentables; no es una falla,
- **no resuelto** — debería haber matcheado y no lo hizo; **esto es lo único que
  hay que trabajar**.

Sin esa separación, el porcentaje se ve peor de lo que es y nadie sabe cuánto
esfuerzo manual queda realmente por delante.

---

## 4. Componentes

### 4.1 Resolución DNMA → sustancias (Java, existente)

`productType` + `productId` → sustancias, por la cadena ya usada en
`DnmaDatabaseServiceImpl`:

```
amp/ampp → vmp → vmp_sustancia → sustancia
```

Un producto puede tener **varias** sustancias (combinaciones). El chequeo es
sustancia × sustancia, no producto × producto.

Las consultas nuevas van con `PreparedStatement`; las existentes concatenan ids
en el `IN (...)` y quedan como están (ítem aparte en el backlog).

### 4.2 Tabla de mapeo (Java / MySQL)

```
drug_substance_mapping
  sustanciaId        varchar   PK   -- SUSTANCIA_ID del DNMA
  sustanciaDsc       varchar        -- el nombre en español, tal cual
  canonicalName      varchar        -- nombre que entiende el motor (inglés)
  rxcui              varchar  NULL
  matchMethod        enum           -- exact | approximate | manual | unresolvable | unresolved
  matchScore         int      NULL
  updatedAt          datetime
```

```
drug_substance_alias_override
  sustanciaId        varchar   PK
  canonicalName      varchar
  note               varchar        -- quién y por qué
```

El job de sync **nunca pisa un override**. `unresolvable` es el estado que marca
"no es un fármaco con interacciones" y lo saca del denominador de la métrica.

### 4.3 Job de sync (Java, `@Scheduled`)

Nocturno e idempotente, en `infrastructure/scheduler/` junto a
`ControlDashboardScheduler`. Recorre las sustancias del DNMA, resuelve las que
cambiaron, respeta overrides, y deja un reporte de `unresolved` para revisión
farmacéutica.

### 4.4 El motor (`pillchecker-recetalia`)

**`POST /interactions`** — recibe `{"drugs": ["warfarin", "ibuprofen", ...]}`,
lista de N nombres (mínimo 2), y arma los pares internamente.

Orden de resolución por par, tal como quedó en el fork:

1. **RxNorm** — resuelve nombre → RxCUI. Sólo normalización; RxNav retiró su
   API de interacciones y no se usa como fuente.
2. **DDInter por RxCUI** — vía la tabla `rxnorm_to_ddinter` del SQLite. Es el
   camino bueno: severidad estructurada.
3. **DDInter por nombre** — fallback FTS5 sobre el string crudo.
4. **openFDA** — baja el prospecto de A y busca el nombre de B en el campo
   `drug_interactions`. Evidencia textual, no estructurada.
5. Nada de lo anterior → bucket `unknown`.

### 4.5 Severidad

Dos regímenes, y la respuesta dice cuál se usó (`source`):

- **`source = "ddinter"`** → severidad estructurada del dataset, tal cual:
  `major | moderate | minor | unknown`. Sin interpretación nuestra.
- **`source = "openfda"`** → clasificación sobre texto libre, con el modelo
  zero-shot DeBERTa. **Marcada siempre como menos confiable.**

⚠️ **Defecto heredado a corregir:** el clasificador devuelve `major` por defecto
ante baja confianza, ante excepción y en el fallback por regex. Eso infla la
severidad de toda la rama openFDA. Hay que cambiarlo a `unknown` con
`uncertain: true` — el aviso sigue apareciendo, pero no disfrazado de grave.

### 4.6 Trazabilidad (Java)

- **`drug_interaction_check`** — log append-only por chequeo: quién (claim `mail`
  del JWT), cuándo, productos, severidad máxima, conteos.
- **`prescription.interactionCheckId`** + **`interactionAcknowledged`** —
  persistidos al emitir con una advertencia a la vista. Responden "¿esta receta
  se emitió sabiendo?".

---

## 5. Contrato público

**`POST /api/drug-interactions/check`** en `recetalia-api-rest`.

```json
{ "productos": [ { "productType": "AMP", "productId": "100421000179106" },
                 { "productType": "VMP", "productId": "678" } ] }
```

`productType` + `productId`, que es lo que la receta realmente guarda. No existe
`codigoDnma`: el DNMA no tiene SNOMED CT a nivel sustancia ni producto.

```json
{
  "hallazgos": [
    { "par": [ {...}, {...} ],
      "sustancias": ["warfarina", "ibuprofeno"],
      "severidad": "major",
      "confiable": true,
      "fuente": "DDInter 2.0",
      "evidencia": null,
      "fechaEvidencia": "2026-09-15" } ],
  "sinHallazgos": [
    { "par": [ {...}, {...} ], "motivo": "par no presente en DDInter" } ],
  "noEvaluables": [
    { "productType": "AMP", "productId": "999",
      "sustancia": "dipirona",
      "motivo": "sustancia sin equivalente en la base de interacciones" } ],
  "disclaimer": "..."
}
```

Tres listas, no dos. **`sinHallazgos` es la que importa**: que un par no esté en
DDInter no significa que sea seguro. La UI tiene que decir "no se encontró
interacción documentada", nunca "es seguro".

**`confiable`** distingue el hallazgo de DDInter (estructurado) del de openFDA
(inferido de texto). Sin ese campo, el médico no puede saber cuánto pesa el aviso.

**Auth:** `requestMatchers("/api/drug-interactions/**")` en
`SecurityConfiguration`, para el rol de médico y `ROLE_MEDICAL_PROVIDER_API`.
Es la única vía: el proyecto no tiene `@EnableMethodSecurity`. Ojo al doble
prefijo `ROLE_ROLE_`.

**Disparo:** al agregar cada medicamento, no al emitir. En
`prescription-add.component.ts`, contra el array `prescriptionsRequest`.

---

## 6. Qué le hicimos al fork

Rama `feat/poda-interacciones`, commit `9bb029b`. **39 archivos, −4.785 líneas.**
104 tests pasan, 4 skippeados (el gate de regresión necesita el `.db`).

| Se fue | Por qué |
|---|---|
| `POST /analyze` y su cadena (NER, OCR, parser de dosis) | el texto de la receta lo parsea Recetalia |
| modelo NER OpenMed (108M) | sólo servía a `/analyze` |
| benchmark tier1 y stage `benchmark-runner` | medía NER, no interacciones |
| `hf-sync` | publicaba el árbol a un HF Space de la autora **en cada push a main** |

De `eval/` se conservó lo que mide interacciones: `coverage_audit`, los casos
semilla de DDInter y `metrics/interactions`.

**`torch` y `transformers` pasaron al extra opcional `ml`**, con el import de
`transformers` movido dentro de `load_model()`. Razón medida: PyTorch no publica
wheels de macOS x86_64, así que en el set base la suite **no instala en un Mac
Intel**. El Dockerfile instala el extra con `uv sync --extra ml`.

---

## 7. Despliegue

Los workflows heredados apuntan a Cloud Run, Workload Identity Federation y un
Artifact Registry de un proyecto GCP que no es nuestro. Hay que reescribirlos
contra `deploy-recetalia`: docker compose en el `.98` (PRE) y el `.217` (PROD),
mismo patrón que el resto de los servicios.

El motor **no se expone a internet**. Sólo lo alcanza `recetalia-api-rest` por la
red docker interna, igual que `transversal-recetalia-api`.

### Pendientes de infraestructura

1. **El `.db` no existe todavía.** El repo lo baja de un GitHub Release de la
   autora. Construirlo nosotros implica publicar nuestro propio artefacto — que
   es justamente el acto que la cláusula NonCommercial gobierna (§8).
2. **Rate limit de 10/min por IP.** Detrás de un backend Spring todas las
   requests llegan con la misma IP: se tumba con dos médicos simultáneos. Hay que
   subirlo o sacarlo.
3. **La API key falla abierta**: si `API_KEY` no está seteada, el middleware
   deja pasar todo. Hay que hacerla obligatoria en producción.
4. **No hay HEALTHCHECK** en el Dockerfile ni en los compose.
5. **Caché en memoria del proceso** — inútil con réplicas.
6. La imagen pesa varios GB por `torch` + DeBERTa. Es el costo de conservar el
   clasificador zero-shot.

---

## 8. Licencia — el riesgo que domina

El repo declara, en su propio código y en el payload de **cada respuesta**, que
DDInter 2.0 es **CC BY-NC-SA 4.0**:

```python
version="2.0", license="CC BY-NC-SA 4.0",
attribution_url="https://ddinter2.scbdd.com/"
```

`NonCommercial` impide la explotación comercial; `ShareAlike` contamina las obras
derivadas del dataset. Hornear el `.db` en la imagen de un producto pago cae de
lleno adentro.

Dos matices que juegan a favor:

- El **código** del fork es **MIT**. El motor es nuestro desde el minuto cero; lo
  que hay que negociar es únicamente el permiso sobre los datos.
- La autora del repo dejó escrito `# Verify citation before first release` — ni
  ella verificó la licencia contra la fuente. **Conviene confirmarla en
  `ddinter2.scbdd.com` antes de abrir la negociación**, no vaya a ser que se esté
  discutiendo sobre una licencia mal citada.

Decisión tomada: se desarrolla en paralelo a la negociación. No bloquea el
desarrollo; **sí bloquea producción con datos reales de pacientes**.

---

## 9. Plan B

Si la licencia no sale, el trabajo no se pierde. La fuente de datos está detrás
de una interfaz y el fork ya trae el cliente de openFDA, que es **dominio
público**. El diseño de
[2026-09-14](2026-09-14-interacciones-medicamentosas-design.md) describe ese
camino completo: precálculo de los textos de `drug_interactions` por sustancia,
matcheo por sinónimos y clasificación sobre la oración que matcheó.

Es un motor peor —sin severidad estructurada, con más falsos negativos— pero es
lanzable sin pedirle permiso a nadie. Mantener esa rama viva es lo que evita que
una negociación fuera de nuestro control sea un punto único de falla.

---

## 10. Pruebas

- `InteractionCheckerService` (Java) con mock del cliente del motor: par con
  hallazgo, par sin hallazgo, sustancia sin mapeo, producto multi-sustancia.
- Degradación: motor caído, timeout, 500 → el par sale como no evaluable, nunca
  un 500 hacia el médico y nunca se bloquea la receta.
- Job de sync: idempotencia; no pisar overrides manuales.
- Gate de regresión de DDInter (ya existe en el fork): severidades contra los
  casos semilla curados.
- Cobertura: los tres estados de §3, no un porcentaje plano.

---

## 11. Decisiones abiertas

1. **Construir el `.db` nosotros o usar el release de la autora.** Depende de §8.
2. **Quién revisa los `unresolved`** — hace falta criterio farmacéutico (¿el D.T.?).
3. **Qué hacer con los 47.182 pares `Unknown`** de DDInter: ¿se muestran como
   "interacción documentada, gravedad desconocida", o se callan? Son el 21 % del
   dataset, así que la decisión es visible.
4. **Nombre del servicio** en el compose y la red interna.
