# Backlog — Recetalia workspace

Qué falta y qué se descartó. El detalle del release en curso vive en
[doc/plans/2026-08-18-qf-contacto-obligatorio-plan.md](doc/plans/2026-08-18-qf-contacto-obligatorio-plan.md)
(2.3.0 — en PRE, falta PROD). El anterior, en
[doc/plans/2026-08-10-release-2.2.0-prod-plan.md](doc/plans/2026-08-10-release-2.2.0-prod-plan.md).

## AHORA

- **[tarea · plataforma · S]** Cerrar la mudanza de Consilio PROD (ya corre en 165.22.231.175 desde 2026-10-02)
  Falta: retirar `30-`/`31-consilio*.conf` y sus certs del edge del 178 (dueño sites-manager-ea; sin tráfico, la
  renovación LE va a fallar); `ufw` en el 165 (hoy firewall inactivo, sólo escuchan 22/80/443); deploys de Consilio
  ahora son 3: PROD 165 (save/load o build), landing en el 178, PRE en el .98 — documentarlo en `consilio/docs/deploy.md`.
- **[bloqueado · core · S]** Consilio: patologías en castellano — pedir licencia de DeCS
  Las 1.517 patologías MeSH se muestran en inglés salvo 144 traducidas a mano. La fuente oficial
  es DeCS (BIREME/OPS/OMS): gratis, pero descarga/API exige licencia por formulario
  (https://decs.bvsalud.org/en/for-developers/). La copia en UMLS (MSHSPA) es nivel 3: no sirve
  para producción. Pablo decidió 2026-09-25 "sólo fuentes oficiales" (sin traducción IA).
  ← bloqueado por: Pablo completa el formulario de licencia DeCS

- **[tarea · repo · S]** `recetalia-security-testing` no tiene remoto: 23 commits sólo en la Mac
  Es el único repo del workspace sin `origin`. Todo el trabajo de la suite de pentest y stress
  vive únicamente en el disco de Pablo. Crear el repo en la organización y pushear.

- **[decisión · datos · S]** El apex `medicinainteligente.ai` ya no apunta al `.98`
  Resuelve a `178.128.234.182` (otro droplet, sirve una landing Next.js), pero el `.98`
  sigue corriendo el contenedor `mi-landing` y su vhost `45-medicinainteligente.conf`
  afirma que "el apex resuelve directo a este server". Nadie le pega. Decidir si el vhost
  y el contenedor se retiran del `.98` o si el apex vuelve — mientras tanto ocupa disco en
  un server que está al 85%.

- **[tarea · core · S]** Pedir a la FOPH suiza el XML de SwissPedDose
  Es un email, y es **lo único estructurado de pediatría con permiso explícito** que se consigue
  gratis: ~700 recomendaciones sobre 230 sustancias, y la oficina federal publica textualmente
  que "may be used and modified by third parties". El Kinderformularium holandés está cerrado
  —prohíbe hasta integrar sus métodos de cálculo— y no hay alternativa abierta.
  ⚠️ Es una foto congelada al 31/12/2025: cortaron el financiamiento en feb-2025, no es un feed.

- **[bloqueado · core · S]** Cobertura ponderada por prescripción real
  Necesita acceso a la tabla `prescription`. Hoy publicamos 59,5% por producto y 52,7% por
  sustancia, que son métricas de catálogo: tratan igual a la dipirona que a un
  antineoplásico que se receta una vez al año. La ponderada es el número honesto para
  vender, y además da **el ranking de lo que falta ordenado por cuánto se receta**, que es
  la lista de trabajo del farmacéutico. Detalle en
  [doc/plans/2026-09-16-consilio-pendientes-plan.md](doc/plans/2026-09-16-consilio-pendientes-plan.md).

- **[tarea · core · M]** Consilio nunca corrió contra Recetalia vivo
  El código Java compila, tiene 8 tests y un test de contrato contra payload real, pero
  `recetalia-api-rest` nunca se levantó apuntando al motor. Falta correrlo con
  `EXTERNAL_API_CONSILIO=http://localhost:8100` y pegarle al endpoint con un token real.
  Necesita credenciales de una MySQL de dev, o el OK para usar las del `.env` contra pre-prod.

- **[decisión · core · M]** Licencia de DDInter: negociar o construir sin ella
  CC BY-NC-SA 4.0. Con las 14 categorías ATC cargadas (2026-09-25; antes 8, 160.235 pares) aporta
  **234.981 de 237.160** pares distintos (99,1 %), y en **231.127** (97,5 %) es la única fuente.
  **Bloquea producción, no desarrollo.**
  Sin DDInter quedan **6.033** pares distintos (2,5 %) —4.433 filas de openFDA (1.824 sin DDInter)
  más 1.821 de la AEMPS (376 sin DDInter); 221 pares tienen las dos—. Medido 2026-09-26 con
  `select count(*) from (select distinct drug_a_id,drug_b_id from interaction [where source=…])`
  sobre `recetalia_interactions.db` (md5 `c44ca8b…`, idéntica en la Mac y el `.98`).
  El esquema soporta las dos salidas: `DELETE FROM interaction WHERE source='ddinter'` y se
  repuebla. La AEMPS mejora el escenario sin DDInter: es la única fuente con texto clínico.
  Antes de negociar, verificar la licencia en ddinter2.scbdd.com — el dato viene del repo que
  forkeamos y su propio autor dejó escrito que no la verificó.

- **[tarea · gestión · M]** Validar 2.2.0 en producción
  El release está desplegado y verificado por HTTP, pero **ningún humano lo usó todavía**. Plan
  listo para el tester en [doc/plans/2026-08-12-pruebas-prod-2.2.0.md](doc/plans/2026-08-12-pruebas-prod-2.2.0.md).
  El bloque 5 (habilitar un QF y su primer ingreso) es el único circuito que nunca se probó
  contra datos reales en ningún ambiente.

- **[decisión · core · S]** Habilitar un QF ahora DEPENDE del servicio de mail
  Desde la 2.5.0, si la invitación no sale, `validate` falla y no sella `validatedAt`. Es lo
  correcto —no deja a nadie marcado como habilitado sin poder entrar— pero significa que **con
  el SMTP caído nadie se puede habilitar**. En PRE eso es hoy el estado (ver el item de abajo).
  Decidir: se deja así, o se permite habilitar con un aviso de "invitación no enviada".
  Código: `PharmaceuticalDirectorRegistrationServiceImpl.validate`.

- **[bug · plataforma · M]** El SMTP de PRE está roto: `535 5.7.8 authentication failed`
  Verificado el 2026-09-02 en el log de `transversal-recetalia-api` del `.98`. Credenciales
  inválidas. **Ningún mail sale de PRE** — ni invitaciones de QF ni altas de médico/farmacia.
  Es anterior a este trabajo (era DT-7 del plan de agosto) y hoy bloquea probar en PRE todo lo
  que mande mail: el D6 de la 2.5.0 hubo que cerrarlo en PRODUCCIÓN.
  → desbloquea: probar el flujo de habilitación entero en PRE en vez de en PROD

- **[deuda · plataforma · S]** Un ingress caído se VE pero no AVISA
  Desde 2026-09-26 el Monitor de Infra de Gestión chequea 4 fronts + security-api de PRE y PROD
  (`GET /api/control-dashboard/infra/ingress`, 520-530 de Cloudflare = caído). Pero sólo si alguien
  abre el dashboard. Falta job en `ControlDashboardScheduler` que mande mail al detectar caída
  (el 2026-09-02 el nginx del `.98` estuvo días muerto sin que nadie se enterara).
- **[decisión · gestión · M]** Cómo le llega el acceso a cada QF del arrastre
  **Resuelto el CÓMO en la 2.5.0**: Gestión ya no asigna ninguna clave — habilitar manda al QF
  un mail con el link para que defina la suya. Lo que sigue abierto es el arrastre de abajo.
  ~~Gestión asigna la clave~~, pero **NINGÚN QF tiene email: 0 de 221** (medido en PROD 2026-08-13;
  tampoco tienen teléfono: 0/221). El único canal es la farmacia, y esas sí tienen email las 337.
  Sin resolver esto el módulo del QF no puede usarse aunque esté desplegado.
  Planilla de relevamiento generada: `~/Downloads/QF-por-farmacia-PROD-2026-08-13.xlsx`
  (regenerable con `doc/scripts/gen-qf-xlsx.py`). **Dónde cargarlos ya está resuelto** (modal
  "Editar contacto" de la 2.3.0, en la solapa Habilitados). Lo que falta es **quién contacta a
  las 334 farmacias y con qué texto**. A partir de la 2.3.0 los QF nuevos ya entran con email y
  celular obligatorios, así que este agujero se cierra solo hacia adelante: es sólo el arrastre.

- **[decisión · datos · M]** Curar los 20 CJPs colisionados
  Ya no es hipotético: en PRODUCCIÓN hay 20 QF en `NEEDS_REVIEW` que abarcan **65 de las 337
  farmacias**, y no pueden usar el módulo del QF hasta que alguien corrija el dato. Los dos más
  grandes: CJP `1` (Florencia Larrosa) y `84805` (Andrea Fillippini), 7 farmacias cada uno.
  La dispensación normal de esas farmacias no está afectada.

- **[decisión · datos · M]** 144 de 479 médicos no tienen prestador asignado
  Medido en PROD 2026-08-20 (`medic.medicalProviderId IS NULL`); en PRE son 142. **40 de ellos
  tienen recetas.** Destapado al arreglar el 404 del listado de recetas: el código ya no se rompe
  con esos médicos, pero la pregunta de fondo sigue abierta — ¿tienen que tener prestador y quedó
  sin migrar, o hay médicos legítimamente sueltos? De la respuesta depende si el dato se corrige
  o si la app tiene que tratar "médico sin prestador" como un caso normal para siempre.

- **[deuda · datos · S]** Hay 4 QF y 3 farmacias de prueba en la base de PRODUCCIÓN
  CJP `446788` ("Test Test"), `453652` ("NombDirTest ApeDirTest") y `9876543` ("test test"), cada
  uno asignado a una farmacia ficticia (`Farmacia `, `Test`, `test`). Ensucian todo conteo sobre
  farmacias (337 vs 334 reales) y aparecen en cualquier listado o export. Decidir si se borran.
  **+1 el 2026-09-02**: CJP `9998887` ("PRUEBA INVITACION"), creado para cerrar el D6 de la
  2.5.0 (verificar que el mail de invitación sale). Habilitado y visible en la solapa
  Habilitados. Se dejó vivo a propósito para poder clickear el link del mail; borrarlo con
  `bash /tmp/d6.sh limpiar` en el `.217`. **Este tiene dueño y fecha: no es arrastre.**

- **[tarea · datos · S]** Faltan usuarios de prueba en PRE
  Un prestador con `MedicalProvider` asociado y un admin de cadena con franquicia. También
  `api-c3@recetalia.com`, que **existe en PROD pero no en PRE**. Sin ellos esas rutas se validan
  sólo con tests unitarios.

- **[bug · core · M]** Un prestador puede editar o borrar cualquier médico
  Hallado 2026-09-26 (`fix/medics-endpoints-rol`): `GET/PUT/DELETE /api/medics/{id}` aceptan
  ROLE_MEDICAL_PROVIDER sin ownership, y ve a todos en `GET /api/medics`. No se acotó porque el alta
  del prestador no manda `medicalProviderId` → sus médicos quedan sin prestador. Arreglo: asignar el
  prestador del token al crear + filtrar listado y edición por prestador.

- **[tarea · docs · S]** Brochure y comparativo VIDAL dicen 166.489 interacciones
  Medido 2026-09-26 (`count(distinct drug_a_id, drug_b_id)` en `recetalia_interactions.db`): 237.160 pares
  (241.235 filas); sin DDInter quedan 6.033 (2,5%). Actualizar `doc/2026-09-23-consilio-brochure.md`,
  `doc/2026-09-23-consilio-vs-vidal.md` y regenerar el PDF.

- **[bug · core · S]** Un médico con `status=DELETED` sigue logueando y usando la API
  Medido en PRE 2026-09-26: `medico@pruebas.com` tiene `medic.status=DELETED` y hace login, emite
  token y opera. El login (security-api) no mira el status del médico de recetalia-api-rest.
  Verificar si en PROD pasa igual; un médico dado de baja no debería poder recetar.

- **[deuda · docs · S]** `consilio/docs/deploy.md` describe el despliegue en el `.98`
  Consilio se mudó al 178.128.234.182 el 2026-09-26 (corte hecho: DNS, certs reemitidos con la cuenta LE
  del edge, contenedor del `.98` parado con imagen y vhosts en `nginx/bak/`). Actualizar el doc con el 178:
  `/opt/consilio`, `docker-compose.mi.yml`, vhosts `30-`/`31-` en `/opt/edge/conf.d`, cómo se sube la base.
- **[deuda · plataforma · S]** `CREDENTIALS.local.md` copiado en `/opt/recetalia/<repo>/` del .217 y del .98
  Desde junio (rsync de fuentes). No entra a las imágenes, pero está en disco de PROD. Borrarlo en ambos
  servers y agregar la exclusión al rsync de `deploy.sh` y al procedimiento manual de build en server.

- **[deuda · plataforma · M]** transversal sin Spring Security: `/api/email/send` es un relay abierto
  Sólo alcanzable desde la red interna de docker (nginx no expone transversal, verificado 2026-09-27), pero
  cualquier contenedor de la red puede mandar mails como notificaciones@. Agregar auth (clave interna).

- **[decisión · gestión · S]** Dos cuentas de Gestión viejas: `gestion@gestion.com` y `gestrecetalia@gmail.com`
  ROLE_MANAGEMENT en PROD, sin logins registrados desde 2026-07-18 (auditoría 2026-09-27). ¿Se usan? Si no,
  borrarlas: ven todo Gestión.

## DESPUÉS

- **[bug · plataforma · S]** `registrypre.recetadigital.uy` y `qfpre.doctorconsultas.com` no resuelven en DNS
  Medido 2026-10-01: `dig` vacío para los dos (el contenedor `recetalia-registry` del .98 sí corre). Sin el
  registry, `deploy.sh` no puede hacer push/pull (por eso los deploys se hacen con build en server). Pablo:
  recrear los A en Cloudflare o decidir retirar el registry y el alias qfpre de DoctorConsultas.

- **[deuda · plataforma · S]** Las imágenes 2.6.0 no están en el registry
  El deploy de 2.6.0 a PROD (2026-09-27) construyó en el `.217` sin `compose push` (el `.98`, que hostea el
  registry, estaba justo de disco). Un `deploy.sh` normal hace `pull` y traería versiones viejas del registry.
  Pushear las 7 imágenes 2.6.0 al registry con disco suficiente en el `.98`, o documentar el build en server.

- **[deuda · plataforma · S]** `deploy.sh` no sirve para el `.98`: hace `docker compose pull` + `up -d` de todo
  En el `.98` las imágenes son `:dev` construidas en el server; el pull/up global puede pisarlas. El deploy
  a PRE del 2026-09-26 se hizo a mano (rsync + build de a una + up de 7 servicios). Darle al script un modo
  dev98 (build en server, up sólo de los servicios tocados) o documentar el procedimiento manual.

- **[bug · core · S]** El filtro de médicos no anda en ninguna app: `GET /api/medics/search` no existe
  Médicos, Farmacias y Gestión lo llaman; cae en `/{id}` con id "search" → 404 silencioso.

- **[deuda · gestión · S]** Gestión tiene ruteado `/register` copiado de la app de médicos
  Componentes de médicos arrastrados a Gestión (perfil con ruta comentada, `/register` activo).

- **[decisión · plataforma · S]** QF tiene el service worker apagado a propósito
  `qf-recetalia-app/src/app/app.module.ts:33` `enabled: false` (2026-07-22, workaround del cacheo viejo).
  Desde 2026-09-26 tiene `AppUpdateService` (inerte sin SW). Decidir si se reactiva el SW (PWA) o se deja.

- **[tarea · core · S]** Consilio: routine semanal de calidad
  Pablo eligió (2026-09-24) una routine semanal: refrescar fuentes que cambian (openFDA, AEMPS),
  correr la suite y `consilio/scripts/eval_duplicidad.py` (12 casos; exit 1 si falla) y abrir PR.
  Límite: un agente en la nube no ve la base (gitignored, DDInter NC) ni el `.98`; el deploy sigue
  siendo manual. Armar con la skill `schedule`.

- **[tarea · docs · S]** Brochure de PONS (agente `backend-hl7-fhir-c7`)
  Pedido enviado 2026-09-25 con el método del de Consilio (`doc/brochure/`): paleta Medicina
  Inteligente, Powered by iwtg.com por página, cifras vivas. Falta confirmar subdominio y logo.

- **[feature · core · M]** Consilio: capa de mecanismo (RxClass) para la duplicidad
  Medido 2026-09-24: clonazepam (N03AE, figura como antiepiléptico) + alprazolam (N05BA) **no
  alerta** aunque son dos benzodiacepinas — la clase ATC4 de la AEMPS no los junta. La capa de
  mecanismo sobre RxClass (MoA/EPC) une benzodiacepinas con hipnóticos Z y AINEs dispersos. Sumar
  el caso a `tests/regression/casos_duplicidad.json` cuando se haga.

- **[bug · core · S]** Consilio: el autocompletado no encuentra nombres castellanos completos
  Visto en la UI 2026-09-25: "amlodipino" y "fludrocortisona" no dan resultados ("amlo" sí).
  `search_drugs` busca por prefijo de alias y no usa el respaldo DNMA/esqueleto que ya tiene
  `drug_id_by_name`.

- **[decisión · core · S]** Consilio: curar las clases de duplicidad demasiado amplias
  `J01D` (34 anclas: cefalosporinas + carbapenems), `J01C` y `H02AB` alertan cualquier par de la
  clase. Revisar con criterio farmacéutico si van `desactivada` o con cupo en
  `consilio/data/duplicidad_cupos.json`; la única excepción cargada (Addison) está `validado: false`.

- **[tarea · core · L]** Consilio: curar las dosis a mano (~100 fármacos)
  **No hay fuente abierta en ninguna jurisdicción, y ahora está medido**: de 40 etiquetas SPL
  actuales de DailyMed, **0/40 traen `doseQuantity` y 0/40 `maxDoseQuantity`** — el campo existe
  en el esquema de la FDA y nadie lo llena. FHIR R5 tiene el contenedor perfecto
  (`Dosage.maxDosePerPeriod`) y los servidores públicos devuelven 0 recursos con guías.
  Anclaje de esfuerzo: el DU90% de la OMS da ~130 fármacos para el 90% de las recetas de
  atención primaria; **con ~100 se cubre el 80%**. Son 200–400 h de farmacéutico, más revisión
  anual. Un LLM sobre el texto CC0 de openFDA + los SmPC de la EMA (uso comercial permitido con
  atribución) hace el primer pase; la revisión humana y la trazabilidad a la fuente no son
  opcionales. Fuentes y verbatims en
  [doc/2026-09-23-consilio-cerrar-los-rojos.md](doc/2026-09-23-consilio-cerrar-los-rojos.md).
  ⚠️ **Va último a propósito.** Medido: 93% de override en alertas de dosis alta en UCI, y el
  88,8% de esos overrides juzgado *apropiado* — o sea, las alertas son malas, no los médicos.
  Arrancar por índice terapéutico estrecho (metotrexato, digoxina, anticoagulantes, litio), no
  por cobertura; nunca alertar cuando falta el dato; infradosis informativa desde el día uno.
  ← bloqueado por: decidir quién es el farmacéutico que cura

- **[feature · core · M]** Consilio: nivel de evidencia por alerta
  **No lo tiene ni VIDAL** (su manual no muestra evidencia ni bibliografía en ninguna alerta) y
  es construible con licencias limpias: el *Minimal Information Model for PDDIs* (CC BY) como
  esquema, DIDEO (CC BY 4.0) como vocabulario de tipos de evidencia, y la escala ORCA para las
  acciones. El tercer nivel —una señal estadística calculada por nosotros sobre los datos crudos
  de farmacovigilancia de la FDA, que son dominio público— replica lo que hace una base conocida
  del rubro **sin heredar su problema de licencia**, y el resultado es nuestro.
  Mostrar identificador, título, revista y DOI; **nunca el resumen**, que es del editor.

- **[feature · core · S]** Consilio: interacciones con alimentos y alcohol
  Tampoco es eje de alerta en VIDAL. No existe fuente estructurada libre, pero **~25 reglas
  cubren más del 95% de lo accionable**: pomelo y CYP3A4, vitamina K con anticoagulantes,
  tiramina con IMAO y linezolid, quelación en quinolonas/tetraciclinas/levotiroxina/bifosfonatos,
  potasio con IECA, y alcohol con sus cuatro mecanismos. La tabla de enzimas hepáticas de la FDA
  (obra del gobierno de EE.UU.) es el validador.
  ⚠️ Las monografías de MedlinePlus están explícitamente prohibidas en una historia clínica.

- **[feature · core · M]** Consilio: reactividad cruzada en alergias
  Hoy sólo matcheamos el fármaco exacto. **El ATC no sirve de atajo y falla en las dos
  direcciones**: amoxicilina/cefadroxilo/cefprozilo comparten cadena lateral (16% de reactividad)
  y están en tres grupos ATC distintos; y `J01DB` mete a la cefazolina —cadena única, segura— con
  la cefalexina. Lo que manda es la **cadena lateral R1**: 38% con cadena idéntica vs 1,5% con
  distinta. Hay que curarlo.
  ⚠️ Dos alertas que hay que **NO** dar, y valen tanto como las que sí: la reactividad cruzada
  entre sulfamidas antibióticas y no antibióticas es un mito (NEJM/Strom 2003 — los alérgicos
  reaccionaban *más* a penicilina), y los carbapenémicos son seguros aun con anafilaxia previa a
  penicilina (AAAAI 2022). Nada de flag único de consenso: **procedencia por arista** — un
  estudio de 2025 halló 272 celdas con consejo opuesto entre cuatro tablas publicadas.
  **Medido 2026-09-24**: una alergia declarada como clase ("penicilina") resuelve por alias exacto
  a **Benzylpenicillin** y sólo alerta contra ese fármaco → falso negativo para amoxicilina y el
  resto de la clase. `_match_allergies` necesita tratar nombres de clase como clase, no como molécula.

- **[feature · core · M]** Consilio: función renal por bandas, no sí/no
  Hoy es binario. No hay tabla abierta de umbrales por fármaco (KDIGO está bloqueado: CC BY-NC-ND
  + permiso escrito), pero **no hace falta**: el G-Standaard holandés usa desde enero de 2026 los
  cortes **90/60/30/15 mL/min**, y el trabajo es asignar cada fármaco a una banda.
  ⚠️ El error a evitar: Cockcroft-Gault da mL/min **absolutos**, CKD-EPI da mL/min/1,73 m²
  **indexados**. Compararlos contra el mismo umbral es un error de unidades — en obesidad genera
  alertas falsas de "reducir dosis"; en ancianos, riesgo de **no** reducir un anticoagulante.
  Guardar `{estimador, unidad, umbral}` **por regla**, calcular los dos y marcar discordancia.
  Las fórmulas se pueden implementar libremente: una ecuación no es objeto de copyright.
  ← bloqueado por: que la receta traiga peso, talla y creatinina

- **[tarea · core · S]** Escribir a `smhaem@aemps.es` por el uso comercial
  Los datos ya están descargados y el aviso legal de la AEMPS prohíbe *transformarlos*, que es
  exactamente lo que hace el cruce por ATC. Aclararlo antes de que esté en producción, no después.

- **[deuda · plataforma · S]** El disco del .98 se llena solo y nadie avisa
  El 2026-09-18 estaba al **92%** (4,6 GB libres) antes de tres builds; `docker builder
  prune -af` liberó 6,4 GB. Es la tercera vez que pasa. Cuando llega al 100% MySQL crashea
  en pleno commit y el síntoma se lee como bug de aplicación (200 que no persiste, login en
  504) — o sea que se diagnostica leyendo código en vez de mirando `df`. Falta un prune
  periódico o una alerta de disco en el Monitor de Infraestructura.

- **[deuda · core · S]** DDInter no trae mecanismo ni manejo clínico
  El 97% de los hallazgos sale con el par y la gravedad, sin explicar por qué ni qué hacer.
  Es lo que más notó quien probó la interfaz. Las columnas `mechanism` y `management` existen
  en `interaction` esperando curación propia (`source='recetalia'`, sobrevive a los re-seeds).
  Empezar por las combinaciones de riesgo más recetadas.

- **[decisión · core · S]** 657 productos del DNMA sin sustancia asociada
  Su VMP no tiene filas en `vmp_sustancia`: es un hueco del dato del MSP, no nuestro, y ningún
  mapeo lo arregla. Son el 9,6% de los AMP y para el médico son tan inevaluables como los
  demás. Decidir si se reportan al MSP o sólo se documentan.

- **[deuda · datos · S]** El dump de PRE del DNMA tiene más datos que el de PROD
  1.526 sustancias contra 1.390, 7.548 AMP contra 6.847. Todo lo medido va contra PROD, que es
  lo que está vivo. Entender por qué divergen: puede ser carga nueva que no bajó.

- **[bug · core · M]** Emitir N recetas en una consulta no es atómico y se come los errores
  `medics-recetalia-app/.../prescription-add/prescription-add.component.ts:194-214` dispara un
  POST por medicamento dentro de un `forEach`, sin `forkJoin`: si falla el 3ro, los 2 primeros
  ya quedaron creados y el médico no se entera (los errores van sólo a `console.error`). Además
  cada respuesta OK hace `router.navigate(['/prescriptions'])`, o sea que navega N veces.
  Encontrado el 2026-09-14 relevando el feature de interacciones.

- **[deuda · core · S]** `DnmaDatabaseServiceImpl` concatena ids en el `IN (...)`
  SQL injection latente: `recetalia-api-rest/.../service/impl/DnmaDatabaseServiceImpl.java` arma
  las listas del `IN` por concatenación de string en vez de `PreparedStatement`. Las consultas
  nuevas del feature de interacciones van parametrizadas; las existentes quedan.

- **[deuda · core · S]** No hay filtro por vencimiento de receta
  `PrescriptionRepository.findPrescriptionsByPatientIdAndMedicalProviderId` filtra por `status`,
  nunca por `expireAt` — que no aparece en ninguna query del proyecto. Sin eso no se puede
  sumar "lo que el paciente ya toma" al chequeo de interacciones, que es donde está el riesgo
  clínico real.
  ← bloqueado por: nada; es previo a extender el alcance del chequeo

- **[decisión · datos · S]** Quién revisa los `unresolved` del mapeo DNMA↔RxCUI
  El job de sync va a dejar una lista de sustancias sin equivalente en RxNorm (español/INN vs
  inglés/USAN). Alguien con criterio farmacéutico —¿el D.T.?— tiene que resolverlas a mano en
  `drug_substance_rxnorm_alias`. Sin dueño, la cobertura del feature se congela donde la deje
  el match automático.

- **[deuda · plataforma · L]** El `.98` corre CentOS 7 con kernel 3.10: las imágenes modernas no arrancan
  Medido 2026-09-05 al montar el sitio institucional en PRE: `php:7.4-apache` (Debian bullseye,
  APR 1.7) exige `getrandom()` (kernel ≥ 3.17) y Apache muere en loop con `AH00141`. Se esquivó con
  la variante `-buster` sólo en `docker-compose.dev98.yml`. CentOS 7 está fuera de soporte desde
  2024-06: cualquier imagen base nueva (Node 20+, Debian bookworm, glibc ≥ 2.34) puede fallar igual,
  y PRE deja de parecerse a PROD (`.217`, Ubuntu kernel 6.8). Reinstalar o migrar el `.98` es un
  proyecto aparte: comparte nginx con DoctorSuite, DoctorConsultas, FHIR y Keycloak.

- **[decisión · sitio · S]** El tutorial de químicos no tiene landing, sólo el PDF suelto
  Desde 2026-09-08 existe `recetalia.com/tutorial-quimicos.pdf`, pero el de farmacias además tiene
  página propia (`tutorial-farmacias/index.php`: video embebido + botón "DESCARGAR PDF"). Decidir si
  el QF lleva landing análoga o el link directo al PDF alcanza. Si lleva, hay que ver desde dónde se
  entra (hoy nada del sitio linkea al PDF nuevo).

- **[deuda · plataforma · S]** No se puede purgar la caché de Cloudflare desde la Mac
  No hay token de CF en ningún `.env` ni en el entorno (verificado 2026-09-08), así que toda purga es
  manual por dashboard. Muerde en cada cambio de estático: los `.pdf` salen con `max-age=14400`, o sea
  que un archivo reemplazado sigue vivo hasta 4 h en los PoPs que no revalidaron. Crear un token de
  zona con permiso de purge y guardarlo donde vive el resto de los secretos.

- **[bug · sitio · S]** Todo el sitio institucional desborda a lo ancho en celular
  Captura headless a 390 px (2026-09-05): la home, la página vieja y la nueva de farmacias se salen
  por la derecha, header incluido ("Ingresar" y el título quedan cortados). Es del template
  (`styles.css`/`responsive.css` del tema themeix), no del listado. Falta encontrar el elemento con
  ancho fijo y arreglarlo una vez para todas las páginas.

- **[deuda · sitio · S]** `<base href="https://recetalia.com/">` en todas las páginas: PRE carga los assets de PROD
  Consecuencia medida en `https://138.197.150.98:8443`: CSS y JS vienen de PROD (no se prueba lo
  que se deployó) y las webfonts de Font Awesome se bloquean por CORS → íconos cuadrados sólo en
  PRE. Sacar el `<base>` (o hacerlo relativo) y, aparte, darle al sitio de PRE un hostname propio
  (`sitepre.recetalia.com` en Cloudflare + `server_name` en `40-recetalia-site.conf`) en vez de
  IP:8443 con cert propio.

- **[bug · core · M]** Un usuario con dos roles pierde el segundo en el token
  El claim `role` del JWT es **un solo string, el primero de `user.getRoles()`**. Medido en PROD:
  `recetaliat2@gmail.com` tiene `ROLE_PHARMACY` **y** `ROLE_PHARMACY_ADMIN`, y su token sale con
  `ROLE_PHARMACY` — o sea que nunca puede ejercer el camino de admin de cadena. Preexistente, pero
  pesa más desde 2.2.0 porque la autorización ahora se deriva del rol. Efecto colateral: ese
  usuario **no sirve para probar la vista consolidada de cadenas**; los admins reales son
  `sanroque@recetalia.com` y `pigalle@recetalia.com` (`franchise.adminEmail`).

- **[deuda · docs · S]** El README de `deploy-recetalia` documenta un deploy que ya no se usa
  Describe build local + `scripts/build-and-push.sh` + push al registry. El flujo real es rsync de
  los repos a `/opt/recetalia/<app>/` y `docker compose build` **en cada server** con su propio
  `.env`. Peor: el `.env` local trae `FRONTEND_CONFIGURATION=preprod` + `IMAGE_TAG=latest` —
  seguir el README al pie hornearía la API de PRE en la imagen que consume PROD.

- **[deuda · plataforma · S]** No se puede saber qué versión corre en un server
  Los `package.json` dicen `"version": "0.0.0"` y las imágenes usan tags móviles (`:latest` en
  PROD, `:dev` en PRE), así que "¿qué hay en prod?" hoy se responde por fecha de imagen y
  grepeando marcadores en el bundle — que además es fácil de hacer mal (un literal que existe en
  ambas versiones da un falso OK). Sellar el tag semver como `LABEL org.opencontainers.image.version`
  de la imagen, o como env var visible en un endpoint.

- **[deuda · repo · M]** Los specs autogenerados fallan de antes en los dos fronts
  Medido con `ng test --watch=false --browsers=ChromeHeadless`: **Gestión 18 FAILED / 17 SUCCESS**
  y **farmacias 16 FAILED / 11 SUCCESS** (esta última contra el tag `2.2.0`, 2026-08-19). Son los
  specs `should create` autogenerados por el CLI que nunca se completaron — les falta `HttpClient`
  y las declaraciones de los componentes hijos. `npm test` no sirve como semáforo: una regresión
  nueva se pierde entre los fallos viejos, y hay que comparar contra la línea base a mano en cada
  release. Arreglo mínimo: borrarlos. Son specs que no prueban nada y cuestan una medición por tanda.

- **[deuda · gestión · S]** Cuarta copia inline del armado del objeto `Phone` en Gestión
  El mismo bloque (`countryCode`/`national`/`international`/`type`/`validated` desde
  `parsePhoneNumberFromString`) está repetido en `medic-update`, `profile`, `pharmacy-update` y
  ahora en el modal de contacto del QF. Farmacias ya lo tiene extraído en
  `shared/utils/phone-payload.util.ts` con su spec: replicar ese util en Gestión y reemplazar las
  cuatro copias. Divergen de verdad — `pharmacy-update` usa `parsedPhone.getType()` y las otras
  hardcodean `'mobile'`.

- **[deuda · gestión · S]** El modal de clave del QF se puede cerrar con el POST en vuelo
  Escape y la X no están gateados por `saving`, así que el operador puede cerrar el diálogo
  mientras se guarda la clave; si después falla, el error se escribe en un campo ya invisible y
  la falla queda muda. En la 2.3.0 se arregló en el modal de contacto
  (`[closable]="!savingContact" [closeOnEscape]="!savingContact"`) pero **no** en el de clave,
  que es el que asigna credenciales.

- **[deuda · datos · S]** NBSP en el CJP `56130`
  Falso positivo de colisión: es la misma persona con un espacio de no separación. Limpiar los 2
  registros, o normalizar en la query — que obliga a tocar backfill y recálculo, que tienen que
  quedar idénticos.

- **[deuda · plataforma · M]** La conexión JDBC escribe UTF-8 en columnas `latin1`
  Cualquier nombre con acento se corrompe al guardarse. Afecta a toda la plataforma, no sólo al QF.

- **[deuda · core · S]** Borrar `/api/prescriptions/admin-data` y `/admin-data2`
  Scaffolding de debug: el primero devuelve un string fijo, el segundo los roles del que llama.
  No los usa ningún frontend. Quedaron a la vista al limpiar los `@PreAuthorize` muertos.

- **[bug · core · M]** Los errores de validación devuelven 500 en vez de 400
  `GlobalExceptionHandler` mapea cualquier `Exception` a 500, así que una
  `MethodArgumentNotValidException` sale como error del servidor. Visto al probar
  `owned-by-provider` con `ids` vacío.
  **Ya no es cosmético: condiciona el diseño.** En la 2.3.0 no se pudo marcar `managerEmail`
  como `@NotBlank` en `PharmacyRequest` —que es lo natural— porque ese DTO lo comparte
  `PUT /api/pharmacies/{id}` y habría roto la edición de farmacia de Gestión con un 500 mudo.
  La obligatoriedad quedó sólo en el formulario, y el endpoint nuevo de contacto valida a mano
  con `BusinessRuleException` en vez de con Bean Validation. Mientras esto no se arregle, cada
  validación nueva paga el mismo rodeo. Arreglo: un `@ExceptionHandler(MethodArgumentNotValidException)`
  que devuelva 400 con los campos que fallaron.
  → desbloquea: usar Bean Validation en los DTOs compartidos

- **[decisión · core · S]** El `documentValidator` está muerto
  En las dos apps lee `idNumber`/`idType` pero los formularios usan `manager*`, así que el
  documento del D.T. no se valida. Activarlo puede empezar a rechazar altas que hoy pasan.

- **[deuda · core · S]** `registeredAt` no se exige en el backend
  La invariante del QF (`ACTIVE` ∧ `validatedAt` ∧ `registeredAt`) se apoya en un guard del front.

- **[deuda · plataforma · S]** 5 `conflicting server name` en el nginx del `.98`
  Medido 2026-10-01: los 5 (apipre, medicospre, farmaciaspre, gestionpre, prestadorespre) están en `10-frontends`/
  `20-apis` y en `15-dev` con los MISMOS upstreams; gana el primero y `nginx -t` pasa. Inocuo: sacar los bloques de 15-dev.
  `farmaciaspre`, `medicospre`, `prestadorespre`, `gestionpre` y `apipre` están declarados dos
  veces (`10-frontends.conf` y `15-dev.conf`), y nginx **ignora uno de los dos bloques** en cada
  caso. Preexistente y sin efecto visible hoy, pero significa que la mitad de esa config no se
  aplica y nadie sabe cuál gana.

- **[deuda · core · S]** El deep link sigue roto por una causa sin identificar
  Se arreglaron dos (301 a `http://` y el prerender servido como fallback). Es preexistente,
  afecta a toda la app y no impide usarla.

## ALGÚN DÍA

- **[tarea · plataforma · S]** Subdominios `*.consilio.medicinainteligente.ai`: habilitar uno cuando haga falta
  DNS creado 2026-09-26 → `.98`. Wildcard en gris (DNS only): proxeado falla TLS en el edge (Universal SSL
  cubre un solo nivel; medido curl exit 35). Sin cert wildcard (pedía token CF por DNS-01): por cada
  subdominio nuevo, cert Let's Encrypt HTTP-01 como `consilio/deploy/46-consilio.conf` (copiar el bloque con
  su `server_name`, emitir con `certbot certonly --webroot`, symlink en conf.d, `nginx -t` + reload).

- **[bug · plataforma · S]** Los `*.demo.doctorconsultas.com` de tres niveles fallan TLS
  El cert universal de Cloudflare cubre `*.doctorconsultas.com`, un solo nivel. El origin los
  sirve bien (200/302 con `Host` header). Es de otro producto que comparte el nginx del `.98`;
  se anota para no volver a diagnosticarlo.

## DESCARTADOS

- **[tarea · plataforma]** ~~Rotar 4 secretos que estuvieron commiteados~~ — 2026-09-26
  Pablo: "por ahora no hay problema" (repos privados). Eran clave DB PROD `doadmin`, `jwt.secret`, SMTP
  notificaciones@ y Auth Token Twilio; siguen en el historial de GitHub. El código ya no los trae.

- **[tarea · core]** ~~Activar `@EnableMethodSecurity` y corregir los 4 `@PreAuthorize`~~ — 2026-08-11
  Se borraron las 4 anotaciones y su regla pasó a los matchers de `SecurityConfiguration`, que
  queda como única fuente de autorización por rol. Ya no hay nada que activar, y tener la
  autorización en dos lugares era el problema de fondo.
