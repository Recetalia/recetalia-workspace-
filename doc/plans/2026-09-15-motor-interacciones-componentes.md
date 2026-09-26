# Motor de interacciones — diseño de componentes

Complementa [2026-09-15-motor-interacciones-diseno.md](2026-09-15-motor-interacciones-diseno.md),
que explica el *qué* y el *por qué*. Éste describe las piezas, sus límites y sus
contratos.

Estado al 2026-09-15: las piezas marcadas ✅ existen y están medidas; las ⏳ están
definidas y sin construir.

---

## 1. Mapa

```
┌─────────────────────────────────────────────────────────────────┐
│  recetalia-api-rest            (Java / Spring Boot 3.3)         │
│                                                                 │
│  DrugInteractionController ──► InteractionCheckService          │
│                                   │                             │
│                 ┌─────────────────┼─────────────────┐           │
│                 ▼                 ▼                 ▼           │
│        DnmaSubstance      PatientProfile      EngineClient      │
│          Resolver           Assembler         (RestTemplate)    │
│                 │                                   │           │
│                 ▼                                   │           │
│         MySQL recetali_dnma                         │           │
│         + drug_interaction_check (traza)            │           │
└─────────────────────────────────────────────────────┼───────────┘
                                                      │ HTTP, red docker
┌─────────────────────────────────────────────────────▼───────────┐
│  pillchecker-recetalia         (Python / FastAPI)               │
│                                                                 │
│   POST /interactions      POST /contraindications   GET /health │
│         │                        │                              │
│         ▼                        ▼                              │
│   InteractionChecker      ContraindicationChecker               │
│         │                        │                              │
│    ┌────┴────┬──────────┐        │                              │
│    ▼         ▼          ▼        ▼                              │
│ RxNorm   RecetaliaDb  OpenFda  RecetaliaDb                      │
│ Client     Client     Client     Client                         │
│                │                    │                           │
│                └────────┬───────────┘                           │
│                         ▼                                       │
│              recetalia_interactions.db  (SQLite, read-only)     │
└─────────────────────────────────────────────────────────────────┘
                         ▲
                         │ construida offline, nunca en runtime
┌────────────────────────┴────────────────────────────────────────┐
│  ETL (scripts/)                                                 │
│   build_ddinter_db → build_recetalia_db → fetch_medrt_…          │
│                                        → resolve_dnma_…          │
│                                        → build_condition_xref ⏳ │
└─────────────────────────────────────────────────────────────────┘
```

**La línea que importa:** el ETL escribe, el runtime lee. La base se abre
`mode=ro&immutable=1`. Ninguna request de un médico dispara una descarga, un
rebuild ni una llamada a un tercero por datos de referencia.

---

## 2. Componentes del motor (Python)

### 2.1 `RecetaliaDbClient` ⏳ — reemplaza a `ddinter_db`

Único componente que toca el SQLite. Aísla el esquema del resto.

| Operación | Devuelve |
|---|---|
| `find_drug(name)` | `drug_id` por alias normalizado (FTS5 + `drug_alias`) |
| `find_drug_by_rxcui(rxcui)` | `drug_id` |
| `interaction(a, b)` | severidad, mecanismo, manejo, procedencia |
| `alerts_for(drug_id, condition_ids)` | contraindicaciones y precauciones |
| `map_dnma(sustancia_id)` | `drug_id` y método de match |

**Regla de precedencia, y es de diseño:** ante dos filas para el mismo hecho,
gana `source='recetalia'` sobre `'ddinter'` o `'medrt'`. Lo que revisó un
farmacéutico pisa lo importado, siempre.

### 2.2 `InteractionChecker` ✅ *(heredado, a adaptar)*

Recibe N nombres, arma los pares, resuelve cada uno. Orden:

1. `RxNormClient` — nombre → RxCUI (sólo normalización)
2. `RecetaliaDbClient.interaction` por RxCUI — **camino bueno**, severidad estructurada
3. `RecetaliaDbClient` por nombre — fallback FTS5
4. `OpenFdaClient` — prospecto FDA, evidencia textual
5. sin nada → bucket `unknown`

Cada resultado lleva `source`, y eso viaja hasta el médico: un hallazgo de
DDInter y uno inferido de texto no valen lo mismo.

### 2.3 `ContraindicationChecker` ⏳ — nuevo

Recibe `drug_ids` + el perfil del paciente, devuelve alertas fármaco-paciente.

El perfil llega ya traducido a `condition_id`s. **Traducir CIE-10 → MeSH es
responsabilidad del ETL, no del runtime** — si no, cada request pagaría el costo
de un mapeo que no cambia nunca.

Estados fisiológicos (embarazo, lactancia, edad, función renal) entran como
condiciones más: `Pregnancy` ya tiene 323 fármacos asociados en MED-RT.

### 2.4 `RxNormClient` ✅ *(heredado, con un bug a corregir)*

Nombre → RxCUI. Caché en memoria, TTL 24 h.

⚠️ **`approximateTerm` está roto upstream.** Exige `score >= 80`, y RxNav
devuelve entre 3 y 14 — la rama nunca se ejecuta. Pero **bajar el umbral es
peor**: medido, `xyzzy nonsense drug` puntúa 9,4 contra 10,5 de un match
perfecto. El score no discrimina.

La corrección está en `resolve_dnma_substances.py`: el score sólo ordena
candidatos, y **la aceptación la decide comparar el nombre devuelto con el
consultado** (similitud ≥ 0,85 sobre el nombre sin sal). Mapear en silencio una
sustancia desconocida al fármaco equivocado es peor que no mapearla.

### 2.5 `OpenFdaClient` + `SeverityClassifier` ✅ *(heredados)*

Respaldo de dominio público. El clasificador es DeBERTa zero-shot, opcional
(extra `ml`), con fallback por regex.

⚠️ **A corregir:** devuelve `major` por defecto ante baja confianza, ante
excepción y en el fallback. Infla la severidad de toda la rama. Debe ser
`unknown` con `uncertain: true`.

### 2.6 Capa HTTP ✅/⏳

| Endpoint | Estado |
|---|---|
| `POST /interactions` | ✅ heredado |
| `POST /contraindications` | ⏳ nuevo |
| `GET /health`, `/health/data` | ✅ |
| ~~`POST /analyze`~~ | ✅ eliminado — el texto lo parsea Recetalia |

⚠️ **Dos defectos heredados, ambos de seguridad:** la API key **falla abierta**
si la variable no está seteada, y el rate limit es 10/min por IP — detrás de un
backend Spring todas las requests comparten IP y se tumba con dos médicos
simultáneos.

---

## 3. ETL (`scripts/`)

Corre offline. Idempotente. **Nada de esto se ejecuta en el camino de una
request.**

| Script | Estado | Qué hace | Medido |
|---|---|---|---|
| `build_ddinter_db.py` | ✅ heredado | baja CSV de DDInter, crosswalk RxNorm, arma SQLite crudo | 160.235 pares, 1.939 fármacos, 96,4 % con RxCUI |
| `build_recetalia_db.py` | ✅ nuestro | crea **nuestro** esquema y lo seedea | 1.939 fármacos, 160.235 interacciones |
| `fetch_medrt_contraindications.py` | ✅ nuestro | alertas fármaco-patología desde MED-RT vía RxClass | **6.522 alertas, 965 patologías, 1.531 fármacos, 0 fallos** |
| `resolve_dnma_substances.py` | ✅ nuestro | sustancia DNMA → fármaco, con verificación por nombre | en medición |
| `build_condition_xref.py` | ⏳ | puente CIE-10 ↔ MeSH | — |

### El puente que falta

Es el trabajo pendiente más importante, porque sin él las patologías del paciente
(CIE-10) no matchean los descriptores de MED-RT (MeSH).

Y no alcanza con una tabla de equivalencias: hace falta **ascender por el árbol
MeSH**. Sin eso, `N18.5 — ERC estadio 5` no matchea `Renal Insufficiency`, que es
el descriptor grueso que usa MED-RT.

Ruta: CIE-10 del paciente → **ICD-10-CM** (dominio público, evita el CC BY-ND de
la OMS) → CUI vía UMLS → descriptor MeSH → ascenso jerárquico.
Refuerzo: **INTERPOLAR** (CC BY 4.0) ya viene en CIE-10 para 688 fármacos.

---

## 4. Componentes en Java (`recetalia-api-rest`) ⏳

### 4.1 `DrugInteractionController`

`POST /api/drug-interactions/check`. Único punto público. Autorización por
`requestMatchers` en `SecurityConfiguration` — el proyecto no tiene
`@EnableMethodSecurity`, así que los `@PreAuthorize` no se evalúan. Roles: médico
y `ROLE_MEDICAL_PROVIDER_API`. Ojo al doble prefijo `ROLE_ROLE_`.

### 4.2 `DnmaSubstanceResolver`

`productType` + `productId` → sustancias, por `amp/ampp → vmp → vmp_sustancia →
sustancia`. Un producto puede tener varias: el chequeo es **sustancia × sustancia**.
Cacheado con Caffeine. Consultas nuevas con `PreparedStatement`.

### 4.3 `PatientProfileAssembler`

Arma el perfil. **De los nueve campos del producto de referencia, Recetalia hoy
tiene dos**: sexo, y edad derivada de `birthdate`. Peso, altura, función renal,
patologías, alergias, embarazo y semanas de amenorrea **no se capturan en ningún
lado**. Sumarlos es captura nueva en el app de médicos, no trabajo de motor.

### 4.4 `EngineClient`

`RestTemplate`, siguiendo `DnmaRestConsumerPortImp`. Timeout corto.
**Ante caída del motor, el chequeo sale "no disponible" y la receta se emite
igual.** Nunca un 500 hacia el médico, nunca un bloqueo por una falla de
infraestructura.

### 4.5 `InteractionCheckService`

Orquesta, arma la respuesta de tres listas y persiste la traza.

**`sinHallazgos` es una lista de primera clase.** Que un par no esté en la base no
significa que sea seguro. La UI debe decir "no se encontró interacción
documentada", nunca "es seguro".

### 4.6 Persistencia

- `drug_interaction_check` — log append-only: quién, cuándo, productos, severidad
  máxima, conteos.
- `prescription.interactionCheckId` + `interactionAcknowledged` — persistidos al
  emitir con una advertencia a la vista.

---

## 5. Por qué el corte está donde está

**El motor no sabe nada de Recetalia.** Recibe nombres y condiciones, devuelve
alertas. No conoce pacientes, recetas, roles ni el DNMA.

Eso compra tres cosas:

1. **La fuente de datos es reemplazable.** Si DDInter no se licencia, se cambia el
   contenido de `interaction` sin tocar una línea de Java ni el contrato público.
2. **El motor sirve a otros consumidores.** doctorconsultas y doctorsuite entran
   por el mismo endpoint sin que nadie duplique lógica.
3. **Lo regulado queda de un solo lado.** Auditoría, autenticación y datos de
   paciente viven en Java, donde ya están el JWT, la traza y las reglas de rol.

El precio es un salto HTTP interno y dos lenguajes. A cambio, la pieza con más
probabilidad de cambiar —la base de conocimiento— es la que está más aislada.
