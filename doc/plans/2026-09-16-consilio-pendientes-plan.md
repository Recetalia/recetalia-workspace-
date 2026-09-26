# Consilio — plan de los dos pendientes

Cierra los dos huecos que hoy impiden vender el producto completo:

- **(a)** la cobertura del vademécum, medida hoy en 56,5 %,
- **(b)** las 6.522 alertas fármaco-paciente, cargadas pero inalcanzables.

---

## (a) Cobertura — el número que medimos no es el que importa

### El replanteo

Decíamos "56,5 % de cobertura". Ese número cuenta **sustancias del catálogo**:
733 de 1.298 fármacos reales del DNMA. Trata igual a la dipirona —que se receta
todos los días en Uruguay— que a un antineoplásico que aparece una vez al año.

**Primer paso ya hecho (2026-09-16): cobertura por producto = 59,5 %.** Un médico
no elige una sustancia, elige uno de los 6.847 AMP del DNMA, y 4.077 de ellos
tienen todas sus sustancias mapeadas. Sube respecto del 52,7 % por sustancia
porque las comunes están en más productos. Falta el paso que de verdad importa:
ponderar por prescripción real.

**La métrica que importa es la cobertura ponderada por prescripción real:** de
las recetas que Recetalia emitió, ¿qué porcentaje de los productos resuelve?

Puede ser mucho más alta que 56,5 %, porque la prescripción se concentra en
pocas moléculas. O puede ser más baja, si los huecos caen justo en lo más
recetado. **No lo sabemos, y es barato averiguarlo**: los datos están en
`prescription`.

Y cambia qué hacer después. Curar a mano 1.298 sustancias es inviable; curar las
50 que explican el 80 % de las recetas es una tarde de un farmacéutico.

### Pasos

1. **Medir la cobertura ponderada por prescripción.** Query sobre `prescription` agrupando por
   `productType` + `productId`, resolviendo cada uno por
   `dnma_substance_map`, y sumando por volumen. Sale un número y, más
   importante, **el ranking de lo que falta ordenado por cuánto se receta**.
2. **Curar por ese ranking.** Las sustancias de arriba que hoy son `unresolved`
   o que DDInter no tiene se cargan a mano como `source='recetalia'`. El
   esquema ya lo soporta y ningún re-seed se las lleva.
3. **API key de openFDA** (gratis, `open.fda.gov/apis/authentication`). Hoy
   procesamos 716 de 1.939 fármacos por el límite de 1.000 requests diarios.
   Con key se procesan los 1.939, lo que alimenta tanto los pares directos como
   la expansión por clase.
4. **Publicar tres métricas, no una.** Por sustancia (52,7 %, la honesta para
   ingeniería: dice cuánto mapeo falta), por producto (59,5 %, la que refleja lo
   que el médico elige) y ponderada por prescripción (pendiente, la honesta para
   vender). Ninguna reemplaza a las otras.

5. **Los 657 productos sin sustancia en el DNMA son un hueco del MSP.** Su VMP no
   tiene filas en `vmp_sustancia`. No hay mapeo que los arregle y no deberían
   contarse como falla nuestra — pero sí hay que reportarlos, porque para el
   médico son igual de inevaluables.

### Lo que NO hay que hacer

**No seguir puliendo el matcheo de nombres.** Ya está medido: limpiar la sal
recuperó 114 sustancias contra RxNorm, pero **sólo ~10 existían en DDInter**. El
techo no es nuestra resolución de nombres, es la lista de 1.939 fármacos de
DDInter. Más esfuerzo ahí no mueve la aguja.

---

## (b) El puente CIE-10 ↔ MeSH

### Por qué hace falta

MED-RT codifica sus 965 patologías en **MeSH** (`D051437 Renal Insufficiency`).
El médico carga la patología del paciente en **CIE-10** (`N18.5`). Sin traducción
no se tocan, y las 6.522 alertas quedan inertes.

### Por qué no alcanza una tabla de equivalencias

MED-RT usa descriptores **gruesos**. `N18.5 — ERC estadio 5` no equivale a
`Renal Insufficiency`: es un caso particular de ella. Hace falta **ascender por
el árbol MeSH** desde el término específico hasta encontrar un descriptor que
MED-RT conozca.

Sin ese ascenso, un paciente con insuficiencia renal estadio 5 no dispara la
alerta de insuficiencia renal. Que es exactamente el paciente que más la
necesita.

### La ruta

```
CIE-10 del paciente  (N18.5)
  → ICD-10-CM                    dominio público (CMS/NCHS)
  → CUI                          vía UMLS MRCONSO
  → descriptor MeSH              (D051437 Renal Insufficiency)
  → ascenso por el árbol MeSH    hasta un descriptor que MED-RT tenga
```

**Por qué ICD-10-CM y no el CIE-10 de la OMS:** el de la OMS es **CC BY-ND**,
que permite uso comercial pero **prohíbe derivados** — y una tabla de mapeo
embebida en el producto es un derivado. ICD-10-CM es dominio público y se alinea
truncando a 3-4 caracteres. Es el único punto de exposición legal del camino (b)
y se esquiva por construcción.

**UMLS** requiere cuenta gratuita. Su licencia permite el uso comercial embebido
("as an integral part of computer applications developed by LICENSEE") pero
**prohíbe redistribuir el vocabulario**. O sea: se puede usar para construir
nuestra tabla, no se puede publicar la tabla como si fuera UMLS.

### Refuerzo: INTERPOLAR

Dataset alemán **CC BY 4.0** —comercial sin ambigüedad— que **ya viene en
CIE-10**: 688 fármacos, 2.129 contraindicaciones operacionalizadas, con ATC,
LOINC para función renal y umbrales numéricos. Y es de ficha técnica europea
(SmPC), mucho más cercana a nuestro vademécum que las etiquetas de la FDA.

Entra directo en `drug_condition_alert` con `source='interpolar'`, sin pasar por
el puente. Conviene cargarlo **antes** que construir el puente: da alertas
accionables con menos trabajo, y sirve para validar el puente cuando exista
(los casos que INTERPOLAR resuelve en CIE-10 son el banco de pruebas del
mapeo).

### Pasos

1. **INTERPOLAR primero.** Descarga, mapeo ATC→nuestros fármacos, carga. Sin
   dependencias nuevas.
2. **`build_condition_xref.py`**: ICD-10-CM → CUI → MeSH, poblando
   `condition_xref` (la tabla ya existe, vacía, esperando esto).
3. **Ascenso jerárquico** por los MeSH tree numbers. Es lo que hace que el
   puente sirva de verdad.
4. **`POST /contraindications`** y `ContraindicationChecker`, que consumen el
   perfil del paciente ya traducido a `condition_id`.
5. **Validar contra INTERPOLAR**: los casos que él resuelve en CIE-10 tienen que
   coincidir con lo que el puente produce.

### Lo que este camino NO resuelve

- **Ajuste posológico por función renal con umbrales por fármaco.** INTERPOLAR
  lo da para 688 moléculas alemanas y nada más.
- **Precauciones graduadas** (leve/moderada/grave) y **pediatría/geriatría por
  rango etario**.

Eso sigue requiriendo una base comercial. Conviene decirlo ahora y no cuando
alguien lo pida en una demo.

---

## Dependencia que atraviesa todo

De los nueve campos del perfil de paciente, **Recetalia tiene dos**: sexo y edad
derivada de `birthdate`. Peso, altura, función renal, patologías, alergias,
embarazo y semanas de amenorrea **no se capturan en ningún lado**.

El puente (b) habilita el motor, pero sin captura no hay qué consultarle. Esa
captura es trabajo en el app de médicos, no en Consilio, y conviene arrancarla
en paralelo y no después.

---

## Orden sugerido

1. **Cobertura ponderada** — un día, y reordena todo lo demás.
2. **API key de openFDA** — una hora, y sube la cobertura de los tres mecanismos.
3. **INTERPOLAR** — alertas por patología reales sin construir el puente.
4. **Captura del perfil de paciente** en el app de médicos, en paralelo.
5. **El puente CIE-10 ↔ MeSH** con ascenso jerárquico.
6. **`POST /contraindications`**.

Los tres primeros dan resultado medible antes de tocar la parte cara.
