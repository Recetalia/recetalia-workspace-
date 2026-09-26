# Cómo cerrar los rojos frente a VIDAL

Qué hace falta para cada capacidad que hoy no tenemos, con la fuente, su
licencia textual y el esfuerzo real.

Todo lo de acá sale de investigación verificada. Donde una fuente no existe, se
dice que no existe en vez de estimarla.

---

## Primero: tres correcciones a lo que dábamos por cierto

### El ATC no se puede redistribuir comercialmente

La OMS es textual: *"Copying and distribution for commercial purposes is not
allowed"* ([atcddd.fhi.no](https://atcddd.fhi.no/copyright_disclaimer/)).

Podemos **usar** los códigos —vía RxClass o el diccionario de la AEMPS— pero no
publicar tablas ATC ni distribuirlas como dataset. Acabamos de cargar el ATC en
1.703 fármacos: para uso interno está bien; para redistribuir, no.

### SNOMED CT es gratis para nosotros

*"SNOMED International does not charge for Affiliate Licensing or for use of
SNOMED CT in Member countries"* — y **Uruguay y Chile son países miembros**
([snomed.org/members](https://www.snomed.org/members)).

Es una puerta que dábamos por cerrada y no lo está.

### INTERPOLAR tiene el motor, no los datos

Verificado clonando el repo: los dos `.xlsx` son **diccionarios de columnas**,
no reglas. La lista curada de contraindicaciones para ~700 fármacos que describe
el proyecto **no está publicada** — el repositorio al que apunta el README
devuelve 404.

Lo aprovechable es su **modelo de reglas**, que sí es bueno y copiable: umbrales
relativos al rango de referencia del laboratorio (`> ULN`, `>= 3*ULN`) con
fallback a un valor absoluto con su unidad. Eso resuelve el problema de que cada
laboratorio tiene rangos distintos.

---

## El rojo más grande: DOSIS

### El dato no existe, y está medido

El esquema SPL de la FDA **declara** los campos `doseQuantity` y
`maxDoseQuantity`. Se bajaron 40 etiquetas actuales de DailyMed:

```
40/40  traen <substanceAdministration> con sólo <routeCode>
 0/40  con doseQuantity
 0/40  con maxDoseQuantity
```

El slot existe y **nadie lo llena**. La FDA nunca indexó posología: sus ocho
conjuntos de indexación cubren unidad de facturación, sustancia y clase
farmacológica — ninguno de dosis.

FHIR R5 tiene el contenedor perfecto (`Dosage.maxDosePerPeriod`), pero está en
*Trial Use* y los servidores públicos devuelven **cero recursos** con guías de
dosificación.

Y nadie publicó dosis extraídas con licencia abierta. El trabajo más cercano
—FDA/NCTR 2021— **no liberó los datos**.

### Conclusión: hay que curarlo a mano

No hay tercera vía. O se extrae de openFDA (CC0) y de las fichas técnicas
europeas, o se licencia una base comercial.

**Cuánto:** el indicador DU90% de la OMS da el anclaje — un consultorio de
atención primaria usa unos **130 fármacos** para el 90 % de sus prescripciones.
Con **~100 moléculas se cubre el 80 %**.

**Qué hace falta por fármaco:** dosis habitual y máxima por vía e indicación,
máxima diaria absoluta, duración máxima, régimen pediátrico con tope, banda de
función renal con su estimador y unidad, y la fuente citada con fecha.

**Esfuerzo estimado: 200 a 400 horas de farmacéutico** para los primeros 100,
más revisión anual. Un LLM sobre el texto CC0 puede hacer el primer pase y bajar
eso quizá a la mitad, pero **la revisión humana no es opcional**: la
trazabilidad a la fuente es lo que defiende al producto si una alerta falla.

### Y un hallazgo que cambia el diseño

Las tasas de rechazo de estas alertas son brutales, y están medidas:

> En UCI, **93 % de override en alertas de dosis alta** — y el **88,8 % de esos
> rechazos fue juzgado apropiado.**

O sea: no es que los médicos ignoren alertas buenas. **Las alertas son malas.**

La causa identificada es la indicación desconocida. Si se compara contra la
dosis máxima de cualquier indicación, se pierden sobredosis reales; si se compara
contra la más estrecha, se genera ruido. Un hospital midió que extender su regla
de 187 a 1.251 fármacos habría pasado de 450 a **17.725 alertas por mes**.

**Lo que sí funciona**, también medido: prescribir con la indicación
estructurada bajó los errores del 28,3 % al 6,6 % de las órdenes.

### Cómo lo haría

1. **Nunca alertar cuando falta el dato.** Sin peso, no se dispara el chequeo por
   mg/kg: se muestra *"no evaluado por falta de peso"* y se ofrece cargarlo. Un
   motor que alerta sobre datos ausentes se apaga solo.
2. **Grados, no binario.** Superar el máximo absoluto bloquea; superar el de la
   indicación interrumpe sólo si la indicación es conocida; salir del rango
   habitual informa.
3. **Empezar por índice terapéutico estrecho**, no por cobertura: metotrexato,
   digoxina, anticoagulantes, opioides, litio, aminoglucósidos, colchicina. Ahí
   el rechazo apropiado es raro y la alerta se gana la confianza.
4. **La infradosis va como informativa desde el día uno** — aporta menos valor
   que la sobredosis, según evaluación pediátrica.
5. **Instrumentar los rechazos desde el primer día.** Es la única forma de saber
   qué fármaco necesita rango por indicación. Con eso, un equipo bajó los
   overrides 63 % en tres meses.

---

## Función renal: de sí/no a bandas

No existe tabla abierta de umbrales por fármaco. KDIGO está bloqueado
(CC BY-NC-ND y permiso escrito explícito); las bases holandesa y alemana son
contratos comerciales.

**Pero hay un modelo pragmático y publicado:** desde enero de 2026 el
G-Standaard holandés usa cortes de **90 / 60 / 30 / 15 mL/min**, alineados con la
EMA. No hace falta un umbral por fármaco para empezar: hace falta **asignar cada
fármaco a una banda**.

### El error de unidades que hay que evitar

Cockcroft-Gault da **mL/min absolutos** y depende del peso. CKD-EPI da
**mL/min/1,73 m² indexado**.

**Comparar un eGFR indexado contra un umbral escrito en mL/min es un error de
unidades**, y no es teórico: en obesidad la indexación subestima el filtrado real
y genera alertas espurias de "reducir dosis"; en ancianos, CKD-EPI sobreestima
frente a Cockcroft-Gault, con riesgo de **no** reducir un anticoagulante.

Las fichas anteriores a 2009 están escritas contra Cockcroft-Gault; la guía de la
FDA de 2024 ya recomienda eGFR.

**Diseño:** no elegir un estimador global. Guardar por regla `{estimador,
unidad, umbral}`, calcular los dos, disparar con aquel contra el que se escribió
la regla, y marcar la discordancia en fármacos de índice terapéutico estrecho.

El costo real no es la fórmula: es que el motor pasa a **depender de peso, talla
y creatinina cargados**.

### Las fórmulas son libres

Una fórmula matemática no es objeto de derecho de autor. El paper está
protegido; la ecuación no. Se re-derivan y se cita.

Mosteller, Du Bois, Haycock (superficie corporal), Cockcroft-Gault, CKD-EPI 2021
sin raza, Schwartz pediátrico.

---

## Pediatría: una sola puerta, y hay que golpearla

**Kinderformularium está cerrado, y de forma inusualmente amplia.** Prohíbe el
uso comercial y además *"integrar los datos y/o métodos de cálculo en otros
sitios web o aplicaciones"* — o sea, prohíbe hasta el método.

**SwissPedDose es la única pista real.** La oficina federal suiza publica, con
todas las letras:

> *"The most recent XML file (as of 31 December 2025) from SwissPedDose is
> available from the FOPH on request"* … *"may be used and modified by third
> parties"*

Permiso explícito de uso **y modificación**, sobre XML estructurado real: unas
700 recomendaciones, 230 sustancias.

⚠️ Con una advertencia: la oficina cortó el financiamiento en febrero de 2025, así
que es un **snapshot congelado**, no un feed vivo.

**Acción: pedir el XML a la FOPH suiza.** Es un email, como el de la AEMPS.

Lo demás está cerrado: el libro de bolsillo de la OMS es "all rights reserved",
la lista pediátrica esencial y el libro AWaRe son CC BY-NC-SA, y el BNF for
Children prohíbe explícitamente su uso en productos de IA.

---

## Reactividad cruzada en alergias: curar, no descargar

No existe fuente abierta. **Y el ATC no sirve como atajo**, falla en las dos
direcciones:

- Amoxicilina, cefadroxilo y cefprozilo comparten la misma cadena lateral —16 %
  de reactividad cruzada— y están en **tres grupos ATC distintos**.
- Al revés, el grupo `J01DB` mete en la misma bolsa a la **cefazolina**, que
  tiene cadena única y es explícitamente segura, con cefalexina, que es de alto
  riesgo.

Lo que manda es la **cadena lateral R1**, no la generación ni el grupo: 38 % de
reactividad con cadena idéntica contra 1,5 % con cadena distinta.

### Dos alertas que hay que NO dar

Esto vale tanto como saber dónde alertar:

**La reactividad cruzada entre sulfamidas antibióticas y no antibióticas es un
mito.** Un estudio del *NEJM* lo desarmó: los alérgicos a sulfamidas reaccionaban
**más** a penicilina que a sulfamidas no antibióticas — predisposición atópica,
no reacción cruzada. **No alertar** furosemida, hidroclorotiazida, celecoxib ni
sulfonilureas.

**Los carbapenémicos se pueden administrar aun con anafilaxia previa a
penicilina**, según el parámetro de práctica de las academias americanas de
alergia.

### Y una advertencia sobre las tablas publicadas

Un estudio de 2025 comparó cuatro tablas de reactividad cruzada publicadas: de
1.090 celdas comparables, **394 discrepancias y 272 con consejo opuesto** entre
seguro e inseguro.

**No guardar un flag único de consenso.** Guardar procedencia por arista, con su
referencia.

---

## Duplicidad terapéutica: el modelo es clase × cupo × excepciones

**Ni ATC4 ni ATC5 alcanzan**, y nuestras 1.593 reglas de la AEMPS tampoco, por
una razón de fondo: la regla de la OMS archiva un producto combinado bajo el ATC
de su ingrediente *principal*, así que **el segundo ingrediente es invisible** a
cualquier coincidencia por prefijo. El paracetamol dentro de una combinación
nunca matchea el paracetamol solo. Y el ácido acetilsalicílico tiene tres ATC
distintos: dos prescripciones de AAS pueden **no compartir prefijo alguno**.

### El número que ordena el diseño

> **El 80 % de las alertas de duplicidad se ignoran, y sólo el 4,1 % son
> clínicamente relevantes. Un tercio eran combinaciones intencionales.**

Por eso lo que hacen las bases comerciales no es coincidencia de clase: es
**clase de duplicación más un cupo permitido por clase**. Textual de una de
ellas: *"not simply two drugs in the same therapeutic class, that may be validly
prescribed together"*.

### Tres capas

1. **Intersección de conjuntos de ingredientes** — cupo cero, siempre peligroso.
   Captura el paracetamol en combinación y el AAS multi-código, que las reglas
   por ATC no pueden expresar.
2. **Capa de mecanismo sobre RxClass**, no sobre ATC. Es lo que unifica los AINEs
   dispersos en tres grupos, y las benzodiacepinas con los hipnóticos Z.
3. **Tabla propia de excepciones** `clase → N permitido`: IECA + antagonista del
   calcio + tiazida, LABA + LAMA, insulina basal más bolo, doble antiagregación
   post-stent, triple terapia para *H. pylori*, amoxicilina con clavulánico.

Esa tercera capa **es la parte que ninguna fuente abierta va a dar**, y es la que
decide si el módulo sirve o se ignora.

---

## Nivel de evidencia: la oportunidad más limpia

**No lo tiene ni VIDAL.** Su manual no muestra nivel de evidencia ni referencia
bibliográfica en ninguna alerta.

Y es construible con licencias limpias:

- **El esquema del payload**: *Minimal Information Model for PDDIs*, **CC BY**.
  Diez campos, entre ellos evidencia, mecanismo, factores modificadores y acción
  recomendada. Dice explícitamente que *"los enlaces a la evidencia son
  esenciales"*.
- **El vocabulario de tipos de evidencia**: **DIDEO**, CC BY 4.0. Más de 30 tipos
  en 7 grupos, diseñado justamente para derivar un nivel de confianza desde el
  tipo de evidencia.
- **Las clases de acción**: la escala ORCA — evitar, usualmente evitar, minimizar
  riesgo, sin acción, sin interacción. Son hechos, implementables libremente.

### El tramo que nos hace dueños del resultado

Tres niveles: guía farmacogenética con su referencia · prospecto oficial (CC0) ·
y **una señal estadística calculada por nosotros sobre los datos crudos de
farmacovigilancia de la FDA**, que son dominio público.

Ese tercer nivel replica lo que hace una base conocida del rubro **sin heredar su
problema de licencia** — esa base no declara licencia en ningún lado — y el
resultado es nuestro.

Mostrar identificador, título, revista y DOI. **Nunca el resumen**: es del
editor.

---

## Alimentos y alcohol: no existe estructurado, se construye

Ninguna fuente estructurada fármaco→alimento→efecto es a la vez gratuita y
comercialmente usable. Todo lo estructurado es no comercial o pago; todo lo libre
es texto.

⚠️ Una trampa concreta: las monografías de MedlinePlus son justo las que
querríamos y están explícitamente prohibidas — *"You may not ingest and/or brand
the copyrighted content found on MedlinePlus in an EHR"*.

**El activo que sí sirve**: la tabla de enzimas hepáticas de la FDA, obra del
gobierno de EE.UU., clasifica el **pomelo como inhibidor moderado de CYP3A** y la
hierba de San Juan como inductor fuerte, con las listas completas de sustratos.
Es el validador de nuestras reglas.

**Unas 20 a 25 reglas cubren más del 95 % de lo accionable.** Los grupos: pomelo
y CYP3A4, vitamina K con anticoagulantes, tiramina con IMAO —y con linezolid—,
quelación por calcio y hierro en quinolonas, tetraciclinas, levotiroxina y
bifosfonatos, potasio con IECA, y **alcohol con sus cuatro mecanismos distintos**.

Un detalle que evita un falso positivo clásico: el pomelo afecta a simvastatina,
lovastatina y atorvastatina, **pero no** a pravastatina, rosuvastatina ni
fluvastatina.

---

## Lo que no se cierra con datos

Marcado CE como producto sanitario, certificación sanitaria y proceso de
materiovigilancia. Eso es plata, tiempo y estructura, no información.

Vale saber el efecto secundario: **embeber un dispositivo de clase IIb arrastra
al producto anfitrión al marco regulatorio europeo**.

---

## Orden sugerido

**Gratis y ya en disco** — sólo hay que cruzar por ATC:

1. Mecanismo y manejo clínico: 2.426 reglas de la AEMPS.
2. Duplicidad: 1.593 pares, más las tres capas de arriba.
3. Geriatría: 303 alertas de la AEMPS **con umbrales de laboratorio**, más
   STOPP/START v3 y EU(7)-PIM, ambos CC BY 4.0.

**Un email cada uno:**

4. XML de SwissPedDose a la oficina federal suiza — pediatría.
5. AEMPS, para blindar el uso comercial.

**Construcción propia, por orden de retorno:**

6. Nivel de evidencia — nadie lo tiene, licencias limpias.
7. Alimentos y alcohol — 25 reglas, tampoco lo tiene VIDAL.
8. Reactividad cruzada — curar por cadena lateral, con las dos supresiones.
9. Bandas de función renal — 90/60/30/15, con el estimador guardado por regla.
10. **Dosis** — 100 fármacos, 200 a 400 horas de farmacéutico. Lo último, porque
    es lo más caro y lo que más ruido genera si se hace mal.
