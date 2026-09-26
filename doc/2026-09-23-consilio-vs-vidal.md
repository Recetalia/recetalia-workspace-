# Consilio frente a VIDAL — comparación de capacidades

Comparación funcional, no comercial: qué chequeos hace cada uno y cómo.

Todo lo de VIDAL sale de fuentes públicas citadas. Lo que no está publicado se
dice que no está, en vez de estimarlo.

---

## Estado al 2026-09-23

De los **18 ejes de alerta** de la tabla de abajo, Consilio cubre **9**.

| | |
|---|---|
| Interacciones | **166.489** · 1.821 con mecanismo y manejo en castellano |
| Alertas fármaco-paciente | **6.522** sobre 965 condiciones |
| Criterios de prescripción en el anciano | **166** sobre 163 fármacos |
| Fármacos | **1.939**, con 2.387 formas de buscarlos |
| Anclajes CIE-10 consultables | **552** |

**Cerrado desde la comparación original:** el texto de mecanismo y manejo (era
el hueco más visible y estaba en cero), la geriatría por edad, y la carga de
patologías por CIE-10, que la interfaz no tenía.

**Lo que falta, en orden de cuánto pesa en una demo:** duplicidad terapéutica ·
dosis · reactividad cruzada en alergias · función renal por bandas ·
temporalidad · incompatibilidad fisicoquímica.

El detalle de cómo se cierra cada uno, con licencias y esfuerzo medido, está en
[2026-09-23-consilio-cerrar-los-rojos.md](2026-09-23-consilio-cerrar-los-rojos.md).

---

## Tres correcciones a lo que suponíamos

Las tres ventajas que dábamos por nuestras **no se sostienen**. La investigación
las desarmó una por una, y la fuente es su propio manual regulatorio —obligatorio
por ser producto sanitario clase IIb—, que describe pantalla por pantalla lo que
ve el médico.

Vale más saberlo ahora que en una reunión.

### 1. «Ellos buscan por nombre, nosotros expandimos por clase» — FALSO

VIDAL implementa el *Thésaurus des interactions médicamenteuses* de la ANSM
francesa, que **está estructurado por clase**. Tiene un índice de clases
terapéuticas separado del de sustancias, y cuando la interacción es de clase
lista sus moléculas, y al revés.

El ejemplo que usábamos como bandera —los IMAO— **está explícitamente en su
índice**: "IMAO irréversibles", "IMAO-A réversibles", "IMAO-B", con sus
moléculas.

**No afirmar que no trabajan por clase. Lo desarman en un minuto.**

Lo que sí es cierto, y sí es defendible: **la ANSM dejó de actualizar ese
Thésaurus.** La última versión es del 15/09/2023 y estará disponible sólo hasta
el **15/06/2027**, lo que obliga a los editores de bases a rehacer su expediente
de homologación. Su fuente de clases se está secando; la nuestra —los prospectos
de la FDA y las clases de la NLM— se actualiza sola.

### 2. «No tienen el vademécum uruguayo» — FALSO, pero con matiz

VIDAL Vademecum Consult cubre Uruguay explícitamente, y hay un índice público y
gratuito de medicamentos uruguayos en `vademecum.es/uruguay`.

**El matiz es real:** el folleto de VIDAL Integrated dibuja los países con base
local curada —Francia, Alemania, Bélgica, España, Portugal, Chile, México, EAU,
Arabia Saudita— y **Uruguay no está entre ellos**. Es plausible que Uruguay se
sirva del nivel internacional más una lista de marcas locales, no de una base
curada con el mismo nivel que Chile o México.

Eso no se afirma: **se pregunta**. *¿El mapeo contra el DNMA del MSP es real y se
actualiza, o es una lista de marcas?* Si la respuesta es la segunda, ahí está la
diferencia.

### 3. «No declaran lo que no pueden evaluar» — FALSO, y era la que más nos gustaba

Su manual lo declara, y con todas las letras:

> *"L'absence d'une IAM dans la base Vidal ne doit jamais être interprétée comme
> une preuve d'innocuité."*

Además: **avisa explícitamente cuando no pudo verificar la dosis** por datos
faltantes; cuando recibe una patología o alergia con un código que no reconoce,
**la muestra sin usar y lo dice**; y enumera sus propios huecos —sin excipientes
en bases locales, sin solventes de perfusión, sólo vía sistémica—.

**No usar este ángulo.** Declarar los límites no es nuestro diferencial: es el
estándar de la categoría, y el que tenemos que igualar.

---

## Qué chequea cada uno

| Eje de alerta | VIDAL | Consilio |
|---|---|---|
| Interacción fármaco-fármaco | ✅ 4 niveles | ✅ 4 niveles |
| **Texto de mecanismo y manejo** | ✅ | ⚠️ en 1.821 de 166.489 (1,1 %) |
| Fármaco-patología | ✅ | ✅ por código CIE-10, con ascenso jerárquico |
| Embarazo | ✅ **por semanas de amenorrea** | ✅ por semana de gestación |
| Lactancia | ✅ con duración | ✅ |
| Insuficiencia **renal** | ✅ **por aclaramiento de creatinina** | ⚠️ sí/no, sin umbral |
| Insuficiencia **hepática** | ❌ **la recibe y NO genera alertas** | ✅ |
| **Edad** (criterios de prescripción en el anciano) | ✅ | ✅ desde 2026-09-23, 172 alertas |
| Peso, sexo, superficie corporal | ✅ | ❌ |
| Alergia, con reactividad cruzada | ✅ | ⚠️ sólo el fármaco exacto |
| Duplicidad de sustancia y de clase | ✅ | ❌ |
| **Dosis** (sobre, infra, duración) | ✅ | ❌ |
| Incompatibilidad fisicoquímica, por vía | ✅ | ❌ |
| Temporalidad (fechas de inicio y fin) | ✅ grafo | ❌ asume simultáneo |
| Vigilancias clínica, biológica, radiológica | ✅ | ❌ |
| Interacción con alimentos o alcohol | ❌ **no es eje de alerta** | ❌ |
| **Nivel de evidencia / bibliografía** | ❌ | ❌ hoy; posible |
| Declaración de lo no evaluable | ✅ | ✅ |
| Procedencia por hallazgo | ❌ | ✅ |

### Severidad

VIDAL gradúa en **cinco niveles transversales** —crítica, elevada, moderada,
baja, informativa— con un mapeo fijo por eje. Para interacciones usa los cuatro
del Thésaurus de la ANSM, validados clínicamente.

La nuestra sale de la fuente cuando es estructurada, y de una clasificación
propia cuando se infiere de texto libre. En ese caso **va marcada como inferida**
— eso sí no lo hacen: su alerta no dice de dónde salió ni cuánto pesa.

---

## Lo que ellos tienen y nosotros no

**Marcado CE como producto sanitario.** VIDAL Sécurisation es **clase IIb** y
Sentinel **clase IIa**, con organismo notificado. Eso es caro y lento de igualar,
y tiene un efecto secundario que conviene conocer: **embeber un dispositivo
clase IIb arrastra al producto anfitrión al marco regulatorio europeo**.

**Proceso de materiovigilancia real.** Hay avisos de seguridad publicados por la
ANSM sobre su propio producto — junio de 2026, control posológico de metotrexato
oral. Tienen el proceso montado; nosotros no.

**Certificación HAS** y presencia en más del 95 % de los hospitales franceses.

**Profundidad de contenido**: más de 17.000 medicamentos virtuales en la base
internacional, 185 estrategias terapéuticas y 260 árboles de decisión.

---

## Lo que nosotros tenemos y ellos no

Queda poco, y conviene que sea poco y cierto.

**Insuficiencia hepática con alertas.** Su manual lo declara textualmente:
*"Insuffisance hépatique (non prise en compte dans les alertes)"*. Recibe el
dato, lo muestra en el perfil, y **no genera ninguna alerta con él**. Nosotros sí.

**Procedencia por hallazgo.** Cada alerta nuestra dice de qué fuente salió y si
la severidad es estructurada o inferida de texto libre. El médico puede pesar el
aviso; en VIDAL todas las alertas se ven iguales.

**Su fuente de clases está congelada.** El Thésaurus de la ANSM no se actualiza
desde septiembre de 2023 y caduca el 15/06/2027. La nuestra se actualiza sola.

**El dato es nuestro.** No se renueva, no se renegocia, y el criterio que carga
un farmacéutico del equipo queda incorporado para siempre.

### Y un hueco de diseño de ellos, que es discutible pero real

Su alerta de sobredosis se dispara contra *"la dosis más alta documentada, sobre
el conjunto de indicaciones conocidas"*. O sea: compara contra el máximo de
cualquier indicación, no contra la que el médico está tratando. **Es ruidoso por
diseño**, y el ruido es lo que hace que un médico deje de mirar las alertas.

No es una ventaja nuestra —no tenemos módulo de dosis— pero es un ángulo válido
si el tema sale.

---

## El hueco de información que juega a favor

**VIDAL no publica cuántas interacciones tiene.** Ni pares, ni
contraindicaciones, ni reglas. Se buscó en sus páginas comerciales, en el portal
de editores y en el folleto internacional: no está.

Nosotros sí publicamos: **164.668 interacciones**, 6.522 alertas fármaco-paciente
sobre 965 condiciones, y **59,5 % de cobertura medida** del vademécum uruguayo.

Poder poner el número sobre la mesa cuando el otro no lo pone es una ventaja
comercial en sí misma — y obliga a la conversación a ir a la pregunta correcta:
*¿cuánto de MI vademécum cubre cada uno?*

---

## Dónde se compite, entonces

No en profundidad clínica ni en regulación: ahí llevan décadas, un marcado CE y
un proceso de materiovigilancia que nosotros no tenemos.

Y tampoco en honestidad del resultado, que era nuestra apuesta: ellos ya lo
hacen.

**Queda esto, y hay que ser sobrios:**

1. **Cobertura real del vademécum uruguayo**, medida y declarada. Es la única
   pregunta donde su respuesta no es un número. Uruguay no figura entre sus
   países con base local curada.
2. **Insuficiencia hepática**, que ellos declaran que no alerta.
3. **Actualidad de la fuente de clases**, mientras la de ellos caduca en 2027.
4. **Procedencia por hallazgo**, que permite pesar el aviso.

Y uno que no es capacidad sino modelo: el dato propio no vence.

**Lo que NO hay que decir**, porque es falso y se desarma en un minuto: que
buscan por nombre, que no tienen vademécum uruguayo, que no están en español, o
que no declaran sus límites.

---

## Lo que hay que cerrar antes de competirles de verdad

En orden de cuánto pesa en una demo:

1. ~~**Texto de mecanismo y manejo.**~~ **Cerrado el 2026-09-23.** Cruzadas las
   2.426 reglas de la AEMPS por ATC: **1.834 interacciones con mecanismo y manejo
   en castellano**, de las cuales 1.093 son pares que antes no teníamos.
   Cubre el 1,1 % del total, así que el hueco pasó de "no hay nada" a "hay para
   lo curado por un regulador". Sigue faltando texto para el resto.
2. **Dosis.** No hay fuente abierta en ninguna jurisdicción. Es un "no" estructural.
3. **Duplicidad terapéutica.** La base de la AEMPS trae 1.593 pares y no las
   usamos todavía. ⚠️ No alcanza con coincidencia por ATC — ver
   [doc/2026-09-23-consilio-cerrar-los-rojos.md](2026-09-23-consilio-cerrar-los-rojos.md).
4. **Pediatría.** ~~Geriatría~~ cerrada el 2026-09-23: 172 criterios de
   prescripción en el anciano, de los cuales 164 salen marcados como
   condicionados porque dependen de algo que la receta no trae. Falta pediatría,
   y la única puerta abierta es pedirle el XML a la oficina federal suiza.
   STOPP/START v3 y EU(7)-PIM siguen identificados y sin cargar: sumarían
   cobertura geriátrica sobre las 107 reglas de la AEMPS que no resolvieron.
5. **Reactividad cruzada en alergias.** Hoy matcheamos el fármaco exacto; falta
   la clase.
