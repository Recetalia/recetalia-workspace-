# Consilio: aviso inline en la pantalla de receta (médicos) — 2026-09-26

**Estado:** implementado en `medics-recetalia-app` 2.x.y (`99d7133`, `050a7e8`; merges `5ea2fb7`, `1b0ccad`), deployado en PRE (.98). PROD sin tocar.

## Qué hace
- Componente `app-consilio-inline-warning` (`home/prescriptions/consilio-inline-warning/`), entre la tarjeta
  "Agregar medicamento / Consultar Consilio" y la de "Prescribir": se ve sin scroll extra al terminar de cargar medicamentos.
- Sólo con el médico habilitado (`GET /drug-interactions/access`, el mismo flag que ya usa la pantalla). No habilitado o
  mientras carga el flag: no se renderiza y no hay llamadas a `/check`.
- Automático: cada cambio de la lista (alta/baja/edición) → debounce 600 ms → `distinctUntilChanged` por
  `productType:productId` en orden → `switchMap` (cancela la consulta anterior) → `POST /drug-interactions/check`.
- Estados: tarjeta con color por severidad máxima (hallazgos + duplicidades) y, por ítem, badge con severidad en texto
  (Grave/Moderada/Leve/Revisar), par de nombres comerciales y resumen; duplicidades con el mismo título que el modal.
  Sin hallazgos → "Consilio: sin alertas para estos medicamentos". Error o `motorDisponible:false` → gris
  "Consilio no disponible en este momento". Nunca bloquea Prescribir.
- "Ver detalle en Consilio" abre el MISMO modal (`openConsilio()`). El botón "Consultar Consilio" y el modal no cambian.
- Accesibilidad: región `role="status"` + `aria-live="polite"` presente mientras el médico está habilitado (la región existe
  antes de que cambie el contenido, así el lector lo anuncia); la severidad siempre va en texto, no sólo en color.

## Decisiones
- **< 2 productos: no se llama.** El modal con 1 producto sólo evalúa si hay perfil de paciente (`/patient-check`); `/check`
  con uno solo no da duplicidades ni interacciones. El inline no usa perfil (lo edita el médico en el modal).
- **Reuso, no copia:** `ConsilioService.check`; `SEVERIDAD_ORDEN/LABEL`, `severidadLabel/Class`, `nombreProducto`,
  `duplicidadTitulo`, `fuenteLabel` pasaron de métodos del modal a funciones exportadas del mismo archivo, que usan ambos.
  Colores por severidad en el partial `consilio-dialog/_consilio-severidad.scss` (major `#c0392b`, moderate `#d98b06`,
  minor `#0e7490`, unknown `#7c3aed`, los que ya tenía el modal).
- **Duplicidad sin severidad = moderada**, igual que el modal.
- **Detección de cambios:** `prescriptionsRequest` pasó a getter/setter que recalcula `consilioProductos`; alta/baja/edición
  reemplazan el array en vez de mutarlo. Así el `@Input` cambia de referencia y no hace falta `ngDoCheck`.
- **SSR:** el componente sólo se suscribe en browser (`isPlatformBrowser`).
- **Resumen corto:** `manejo` → `evidencia` (recortado a 160) → si ambos null, `sustancias · Fuente: X`. Medido en PRE:
  sildenafilo (AMP 108711000179105) + nitroglicerina (AMP 116231000179108) devuelve `major`, `fuente: ddinter`,
  `manejo: null`, `evidencia: null` (curl con `medico@pruebas.com` a `apipre.../drug-interactions/check`); sin el
  fallback, la línea quedaba vacía.

## Campos de la respuesta de `/check` que usa el componente
`motorDisponible`; `hallazgos[].{severidad, par.a/b.{productType, productId, sustancia}, sustancias, manejo, evidencia,
fuente}`; `duplicidades[].{capa, clase, claseDescripcion, sustancias, productos, severidad}`. No usa `noEvaluables`,
`sinHallazgos`, `duplicidadesNoAlertadas` ni `disclaimer` (quedan en el modal).

## Tests
`consilio-inline-warning.component.spec.ts` (10) + 3 nuevos en `prescription-add.component.spec.ts`; con el modal y el
servicio: 39/39 OK. En `prescriptions/**` fallan 3 specs scaffold ajenos (List/Info/Prescriptions "should create"),
que ya fallaban en la base `cef7724`.
