# Consilio

### La segunda opinión que siempre está

---

## Qué hace

Cuando un médico agrega un medicamento a una receta, Consilio le dice **en el
momento** si hay algo que debería saber.

No al guardar. No en un reporte al día siguiente. En el instante en que lo
decide, que es el único momento en que todavía puede cambiar de idea.

**Y no bloquea.** Avisa, muestra la evidencia que respalda el aviso, y deja
constancia de que se avisó. El médico decide.

---

## Qué puede hacer un médico con esto

### 1. Ver si dos medicamentos chocan entre sí

Escribe los medicamentos de la receta y Consilio cruza todas las combinaciones
posibles. Cada hallazgo viene con su gravedad, el mecanismo y **qué hacer**.

> ⚠️ **Warfarina + Ibuprofeno — GRAVE**
> *Aumento del riesgo de hemorragias (especialmente gastrointestinales).*
> **Qué hacer:** valorar beneficio/riesgo, añadir gastroprotector y controlar
> signos de hemorragia.

### 2. Cruzarlos contra el paciente que tiene delante

Carga lo que sabe del paciente y Consilio le dice si alguno de esos
medicamentos no le conviene **a esa persona en particular**:

- **Embarazo**, con la semana de gestación
- **Lactancia**
- **Función renal y hepática**
- **Alergias** a medicamentos
- **Patologías**, por el código CIE-10 de su historia clínica
- **Edad**, con los criterios de prescripción en el adulto mayor

> ⚠️ **Metformina — CONTRAINDICADO**
> *Insuficiencia renal*

### 3. Cargar el diagnóstico como lo tiene escrito

El médico escribe el código CIE-10 de la historia, o el nombre en castellano.
Consilio le muestra **cuántas alertas dispara cada código antes de elegirlo**,
así sabe si ese diagnóstico va a evaluar algo o no.

Y entiende la jerarquía: un paciente con **insuficiencia renal estadio 5**
recibe la advertencia de insuficiencia renal, aunque el código exacto de su
diagnóstico no sea el que usa la base. Consilio sabe que una es un caso de la
otra.

### 4. Confiar en lo que no le dice

Cuando Consilio no tiene información sobre un medicamento, **lo dice**. Aparece
marcado como *no evaluable*, nunca como seguro.

Y cuando una consulta falla, **también lo dice**, con un aviso explícito de que
el resultado está incompleto. Un vacío tranquiliza, y tranquilizar sin haber
evaluado nada es la peor forma de fallar que puede tener una herramienta
clínica.

---

## Lo que nos hace distintos

Cinco cosas, y las cinco tienen un número detrás.

### 1. La gravedad no la decide una sola fuente

Consilio cruza varias fuentes por cada par de medicamentos. **En 381 pares las
fuentes no coinciden en qué tan grave es, y en 275 de ésos alguna dice GRAVE.**

Lo habitual es elegir una fuente y mostrar lo que dice. Eso significa que en
esos 275 pares el aviso podría salir más suave de lo que corresponde.

Consilio **se queda con la gravedad más alta y dice quién la dijo.** Esconder
un desacuerdo entre fuentes no es resolverlo.

### 2. Cada aviso dice de dónde salió

En la mayoría de estos sistemas todas las alertas se ven iguales: no hay forma
de saber si una salió de una base clínica revisada o de interpretar el texto de
un prospecto.

En Consilio cada hallazgo declara su origen, y si la gravedad se dedujo de
texto libre en vez de venir estructurada, **lo dice en la tarjeta**. El médico
puede pesar el aviso en vez de tratarlos a todos igual.

### 3. Una alerta que no podemos verificar no se presenta como un hecho

De los **166 criterios de prescripción en el adulto mayor**, sólo 7 dependen
únicamente de la edad. Los otros dependen de algo que la receta no trae: una
comorbilidad, un valor de laboratorio, un tratamiento concomitante.

Consilio los muestra como **"verificar si…"**, no como *"pasa esto"*. Son menos
vistosos y es lo único honesto.

Esto no es un detalle de redacción: hay evidencia publicada de que **más del
90 % de estas alertas se rechazan, y que la mayoría de esos rechazos están
bien.** El problema no es que los médicos no lean; es que las alertas afirman
de más. Un sistema que avisa de todo enseña a ignorarlo.

### 4. Habla el idioma del vademécum local

**733 sustancias con el nombre del vademécum uruguayo**, más de 2.300 formas de
encontrar un medicamento escribiéndolo como se escribe acá: *aspirina*,
*dipirona*, *paracetamol*.

Y las patologías se buscan en castellano aunque el catálogo internacional esté
en inglés: quien escribe *"hepática"* encuentra las 130 alertas que cuelgan de
*enfermedad del hígado*.

### 5. Publicamos cuánto cubrimos

De los **6.847 productos comerciales** del vademécum uruguayo, **4.077 son
evaluables — el 59,5 %**, medido. El resto aparece marcado como no evaluable,
nunca como seguro.

Un dato que no depende de nosotros: **657 de esos productos (9,6 %) no tienen
principio activo asociado en el propio vademécum**. Son inevaluables por
construcción, para cualquier sistema.

Poner ese número sobre la mesa es poco habitual en esta categoría. Y lleva la
conversación a la única pregunta que importa: *¿cuánto de MI vademécum cubre
cada uno?*

---

## Qué hay adentro

### Interacciones entre medicamentos: **166.489**

| | |
|---|---|
| Base clínica curada | 160.235 pares con gravedad estructurada |
| Prospectos oficiales, por nombre | 3.629 pares que la base curada no tiene |
| Prospectos oficiales, **por clase** | 804 pares que una búsqueda por nombre no encuentra |
| Agencia reguladora europea | 1.821 pares **con el mecanismo y el manejo escritos en castellano** |

La expansión por clase importa porque **los prospectos no advierten por nombre,
advierten por clase**: dicen *"inhibidores de la MAO"*, no listas de moléculas.
Consilio entiende la clase y la expande. Así detecta combinaciones como
**fenelzina + fluoxetina** (síndrome serotoninérgico) o **sildenafil +
nitratos** (hipotensión potencialmente fatal), que un buscador de nombres deja
pasar en silencio.

### Alertas contra el paciente: **6.522**

5.112 contraindicaciones y 1.410 precauciones, sobre **965 condiciones
distintas**, consultables desde **552 códigos CIE-10**.

### Criterios de prescripción en el adulto mayor: **166**

Sobre 163 medicamentos, cada uno con la situación en la que aplica y qué hacer.

### Catálogo

**1.939 medicamentos**, **2.387 formas de buscarlos**, **1.248 prospectos
oficiales** incorporados y procesados.

Construido sobre fuentes de organismos públicos: la agencia de medicamentos de
Estados Unidos, la Biblioteca Nacional de Medicina de ese país, y la agencia
española de medicamentos.

---

## Cómo se integra

Consilio es un **servicio**, no una pantalla. Una sola integración y lo consumen
la historia clínica, el recetario electrónico y cualquier otro producto de la
casa.

También trae su **propia interfaz de consulta**, para quien prefiera usarlo
directo sin integrar nada: buscador con autocompletado, perfil del paciente,
filtros por gravedad y por fuente, búsqueda dentro de los resultados, y
resumen para copiar o imprimir.

---

## Qué lo hace sostenible

**El motor es propio.** No se alquila una base por usuario ni se queda atado a
la renovación de un proveedor.

Eso significa **precio predecible**, y algo más importante: cuando un
farmacéutico del equipo corrige una severidad o agrega el manejo clínico de una
interacción, **ese criterio queda incorporado** y ninguna actualización se lo
lleva por delante.

---

> ### En una frase
> **Consilio revisa cada receta en el momento en que se escribe, avisa con la
> gravedad más alta que encuentre y diciendo de dónde salió, y no afirma nada
> que no pueda respaldar.**

---

## Advertencia

Consilio genera información automáticamente a partir de fuentes públicas.
**No sustituye el criterio clínico.** Que no se encuentre una interacción
documentada no significa que no exista. Verificar con el prospecto oficial ante
cualquier duda.

---
---

## Nota interna — no forma parte del material comercial

Lo que este brochure **no dice**, a propósito:

1. **El 59,5 % se publica como medición, no como compromiso.** Está medido
   contra el dump de PROD del vademécum del 29/06 y va a subir. Decirlo está
   bien; ponerlo en un contrato, no — y si alguien pide garantizarlo, la
   respuesta es que se garantiza el método (lo no evaluable se declara), no el
   número.
2. **El texto clínico cubre 1.821 de 166.489, o sea el 1,1 %.** Es la parte
   curada por un regulador y por eso concentra lo que más se receta, pero **la
   mayoría de los hallazgos sigue saliendo con gravedad y sin explicación**.
   Los ejemplos del brochure (warfarina + ibuprofeno, simvastatina +
   claritromicina) están verificados y se pueden mostrar. **No prometer texto
   para un par cualquiera.**
3. **No hay chequeo de dosis.** Ninguna fuente abierta lo trae, en ninguna
   jurisdicción — está medido: de 40 prospectos oficiales actuales, 0 traen el
   campo de dosis máxima. Si alguien lo pide en una demo, es un "no" hoy.
4. **No hay duplicidad terapéutica** ni **reactividad cruzada de alergias**
   (sólo matchea el fármaco exacto declarado).
5. **La función renal entra como alterada/normal**, no por aclaramiento.
6. **Falta resolver la licencia de la base de interacciones**, que bloquea
   producción aunque no el desarrollo.
7. **Consilio todavía no corrió contra Recetalia en vivo.** Integración
   compilada y testeada, nunca ejecutada extremo a extremo.
