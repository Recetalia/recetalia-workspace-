# TODO — Recetalia workspace

Hallazgos detectados durante la revisión transversal del workspace (2026-04-28). Items agrupados por severidad y proyecto. Cada checkbox es un cambio concreto y verificable.

> Fuente: análisis cruzado de `CLAUDE.md` + `doc/specs/*` + `doc/architecture-overview.md` de cada proyecto y del propio plan `deploy-recetalia/doc/plans/single-server-deploy.md`. Ver ese documento de arquitectura para el contexto completo.

---

## 🔴 Seguridad — crítico

### transversal-recetalia-api (sin Spring Security)
- [ ] Agregar `spring-boot-starter-security` + `SecurityWebFilterChain` mínimo. Hoy `/api/**` está sin filtro. Mitigación actual: nginx no lo expone, pero un slip de config lo deja abierto.
- [x] **`/api/dnmaxml/read?path=…`** acepta rutas de filesystem arbitrarias — ✅ 2.6.1 (2026-09-27): sólo archivos regulares dentro de `/srv/dnma_info` (`dnma.xml.dir`), con symlinks y `..` resueltos. Lo usa api-rest tras el upload de Gestión.
- [ ] **`/api/email/send`** es un relay SMTP abierto — proteger con auth + restringir orígenes (lo único que debe usarlo es `security-api-recetalia` para reset de password).
- [ ] `CorsConfig.java` mapea `/apiContactCenter/**` (no existe) — limpiar y mapear el path real `/api/**` con whitelist concreta de subdominios `*pre.recetadigital.uy` / prod.

### security-api-recetalia (reset de password)
- [x] **`renew-password` no requiere auth ni token de reset** — ✅ 2.6.1 (2026-09-27): exige `X-Internal-Api-Key` (api-rest) o el JWT del propio usuario; register*/renew-passwordBack/request-reset-back/users-exist-back sólo con la clave interna. `/request-reset` rechaza urls fuera de `*.recetalia.com`.
- [x] ✅ (ya corregido antes de 2.6.1: token aleatorio largo, ver `PasswordResetTokenServiceImpl`) **Reset token = `UUID.randomUUID().substring(0,5)`** (5 chars, ~60M combinaciones) → bruteforceable. Cambiar a UUID completo (o token random ≥ 32 chars) + expiry corto + invalidación al usar.
- [ ] Hashear el reset token en DB en vez de guardarlo en texto.
- [ ] `JwtTokenFilter` está declarado `@Component` pero `addFilterBefore(...)` está comentado en `JwtSecurityConfig` — decidir: o se usa (descomentar) o se borra el componente entero.

### recetalia-api-rest
- [ ] **`POST /api/medics` es público** — cualquiera puede crear médicos seteando `status` y `medicalProviderId`. Proteger con auth + validar quién puede setear esos campos.
- [ ] **`@PreAuthorize("hasRole('TESTROLEr')")`** en `/api/prescriptions/admin-data` — typo + rol inexistente. Decidir el rol real o eliminar el endpoint.
- [ ] Endpoint `admin-data2` dumpea las authorities del caller — eliminar (es debug residual).

### Cross-API
- [ ] CORS `allowedOrigins("*")` en `recetalia-api-rest` (`WebConfig.java`) y `transversal-recetalia-api` — restringir a la lista concreta de subdominios.
- [ ] **Passwords plain-text en DB** de `recetalia-api-rest` (Medic, MedicalProvider, Patient, Pharmacy). Migrar a BCrypt — implica cambios coordinados en 5+ repos (login se hace en `security-api`, pero el CRUD que crea/edita pasa por `recetalia-api-rest`).
- [ ] `PatientResponse` expone el campo `password` al frontend — quitarlo del DTO.
- [ ] `SecurityConfiguration` imprime el JWT secret decodificado al arrancar — eliminar el log.
- [ ] `logging.level.io.jsonwebtoken: DEBUG` y `org.springframework.security: DEBUG` en pre-prod/prod — bajar a INFO.
- [ ] Verificar en runtime que el JWT firmado por `security-api-recetalia` (HS256) es realmente validable por `recetalia-api-rest` (HS512 con secret distinto en `application.yml`). Documentar el algoritmo y secret efectivos.

### Cross-frontend (los 4 Angular)
- [ ] AES-ECB con clave hardcoded `'ahjsdfhjbqer56243'` en los bundles JS — es ofuscación, no cifrado. Decidir: (a) eliminar y depender solo de TLS, o (b) implementar cifrado real (RSA con clave pública del server, p.ej.). Ver `EncryptionUtil` en `security-api-recetalia` para mantener el contrato sincronizado.

### Secrets management
- [ ] Secrets commiteados en `application.yml` de las 3 APIs (JWT, MySQL DO, Twilio, SMTP). Mover a `.env` del server + `${SPRING_*}` env vars + rotar credenciales (al menos JWT secret y SMTP).
- [ ] `recetali_receta` vive en 2 hosts distintos (`143.110.212.167` para `recetalia-api-rest`, DO managed para `transversal`) — verificar consistencia o unificar host. Riesgo de drift de schema/datos silencioso.

---

## 🟠 Bugs funcionales (afectan al usuario)

### Cross-frontend (los 4 Angular)
- [ ] **`authGuard`/`AuthGuard` rama `INACTIVE` comentada** — usuarios marcados como `INACTIVE` siguen entrando. Habilitar la rama de redirect a login con mensaje.
- [ ] `refreshToken` llega del backend y se ignora — sólo se refresca cuando algo devuelve 401. Implementar refresh anticipado o eliminar el campo del flujo si no se va a usar.
- [ ] `provideClientHydration()` comentado pese a SSR activo (`prerender: true`) — habilitar o documentar por qué no.
- [ ] `provideHttpClient()` se llama dos veces en `app.module.ts` (`withFetch()` y `withInterceptorsFromDi()`) + `HttpClientModule` legacy importado — consolidar en una sola llamada.

### farmacias-recetalia-app
- [ ] `DispensationFileService.recipeTypeColor` contiene un `debugger` statement — eliminar.

### medics-recetalia-app
- [ ] `home.component.ts` referencia `messagesibleReg: String;` (typo, undefined en `register.component.ts:161`).
- [ ] Limpiar URLs `localhost` comentadas en `environment.ts` y `prescription.service.ts`.

### medical-provider-app
- [ ] `MedicalProviderService` NO usa el envelope `ApiResponse<T>` — devuelve raw. Inconsistente con el resto del workspace. Alinear o documentar.
- [ ] `provideClientHydration()` registrado dos veces (redundante).
- [ ] `BrowserModule`, `HttpClientModule`, `provideClientHydration()` listados duplicados en `app.module.ts`.

### transversal-recetalia-api
- [ ] `WhatsAppController#sendMessage` hace `subscribe(...)` y devuelve `SUCCESS` sincrónico — la respuesta no refleja la entrega real de Twilio. Convertir a `Mono` y propagar el resultado.
- [ ] Soft-delete cosmético: columnas `deletedAt` en entidades sin `@SQLDelete`/`@Where` → `delete()` borra físicamente. Decidir: implementar soft-delete real o eliminar las columnas.
- [ ] `PrescriptionRepository.findViewPrescriptionsByStatus` no filtra `deletedAt`.
- [ ] `spring.jpa.datasource.read-only: true` está seteado pero la app usa R2DBC, no JPA — eliminar la propiedad muerta.

### recetalia-api-rest
- [ ] `POST /api/medical-providers/login` existe pero hace compare plain-text contra MySQL y NO emite token — eliminar (la responsabilidad es de `security-api`) o documentar.

---

## 🟡 Tech debt / consistencia

### Contrato API (toca varios repos)
- [ ] Typos baked-in: `frecuency`, `frecuencyUnit`, `isCronic`, `cronicCode`, `nombreLaboratory`, `rutLaboratory`, `Droug`, `Especiality`, `RegistergModule`, `getPatiensByMedic…`, `search-available-Prescriptions-by-code`. Cambiarlos requiere coordinar 5+ repos — planificar como migración en una pasada.
- [ ] Paginación dual: `Pagination<T>` (Spring Data full) vs `Page<T>` (simplificada) coexisten en el mismo workspace. Unificar.
- [ ] `condvtaId` es `string|null` en `DispensationRequest` y `number|null` en `PrescriptionRequest` — alinear el tipo.

### Cross-frontend
- [ ] No hay lint ni format configurados en ninguno de los 4 frontends (sin ESLint, sin Prettier). Agregar al menos uno consistente.
- [ ] No hay E2E configurado en ningún frontend.
- [ ] `RegistergModule` (typo) — renombrar a `RegisterModule` (toca todos los frontends).
- [ ] `medical-provider-app` usa configs Angular `local`/`prod` en vez de `development`/`production` — alinear con el resto.
- [ ] `Auth-response.ts` con casing distinto al resto de los archivos en `model/response/` — renombrar a `auth-response.ts` (medics, medical-provider).
- [ ] `medics-recetalia-app`: `angular-phone-number-input` + `intl-tel-input` coexisten — quedarse con uno.
- [ ] `medical-provider-app`: carpeta `pipe/` (singular) vs convención `pipes/` del resto.

### recetalia-api-rest
- [ ] **Sin Flyway/Liquibase + `ddl-auto=none`** → schema drift silencioso. Agregar Flyway con baseline del schema actual.
- [ ] Field injection (`@Autowired` sobre atributos) en todos los services — migrar a constructor injection.
- [ ] Validación inconsistente: sólo `MedicRequest` y `MedicEspecialityRequest` usan `@NotNull`/`@Email`/`@Size`. El resto sólo tiene Swagger docs.
- [ ] Status / type values (`ACTIVE`, `INACTIVE`, `AVAILABLE`, `PENDING`, `DISPENSED`, …) son `String` plano — convertir a enums.
- [ ] Puerto: `application.yml` declara `spring.server.port: 8080` (anidado, propiedad inválida) además del `server.port: 8092`. Limpiar.

### security-api-recetalia
- [ ] **Flyway está como dependencia pero `spring.flyway.enabled: false`** — habilitar y aplicar las migraciones existentes (`V1__create_schema.sql`, `V2__data.sql`, `V3__create_password_reset_table.sql`).
- [ ] Carpeta `enviroment/` (sic) — renombrar a `environment/` (rompe rutas internas, ver `docker-compose.yaml`).
- [ ] JWT `role` claim es un único string (toma sólo el primer rol) — multi-rol queda mutilado. Cambiar a array.

### transversal-recetalia-api
- [ ] **Hexagonal boundary violations:** `domain/usecase` declara `implementation project(':recetalia-db')`, `:dnma-db`, `:whatsapp-service`, `:email-service`, `:uruguay-dnma-xml` y los importa concretos (`PrescriptionAdapter`, `AmpAdapter`, `VmpAdapter`). Se rompe la inversión de dependencias. Refactor por puertos.
- [ ] Controllers importan `EmailDto` y `WhatsAppGateway` de los driven-adapter modules (cross-layer leakage).
- [ ] `rest-consumer`, `helpers/metrics`, `helpers/utility` declarados pero sin sources — eliminar o implementar.
- [ ] `architecture.txt` está desactualizado respecto al árbol real — actualizar o eliminar.
- [ ] Dos `EmailServiceUseCaseImpl.java` / `PatientServiceUseCaseImpl.java` overlapping en el top-level de `domain/usecase`.

### deploy-recetalia
- [ ] El `.env` real del server vive en `138.197.150.98`. Documentar quién es el owner de las credenciales del registry y el procedimiento de rotación.
- [ ] `LETSENCRYPT_STAGING` debe quedar en `0` post-bootstrap — verificar que sigue así.
- [ ] Verificar conectividad regular del server pre-prod a `143.110.212.167:3306` y a la DB DO managed (`:25060`) — ya validado en Fase 2.2 pero conviene un health-check periódico.

---

## ✅ Verificado / cerrado

### Deploy infraestructura (Fase 1-7, 2026-04-22)
- Pre-prod corriendo en `138.197.150.98` con docker-compose; los 8 servicios `running`.
- Login E2E funcionando desde los 4 frontends contra `security-api`.
- Branch `register_medic` desplegado en `recetalia-api-rest` con `PharmacyController` y `MedicController.getByEmail`.
- `transversal-recetalia-api` no expuesto públicamente.
- Configuración Angular `preprod` con `fileReplacements` aplicada en los 4 frontends.

### Ciclo "Fixes Testeo DEV & PRE" (2026-04-29)

Spec: `doc/plans/2026-04-28-fixes-testeo-dev-pre-design.md`
Plan: `doc/plans/2026-04-28-fixes-testeo-dev-pre-plan.md`

Backend (`recetalia-api-rest`, branch `register_medic`):
- [x] **G4 + G8** Timezone fix — `ZoneId.of("America/Montevideo")` en PrescriptionController + DispensationController. Commits: `9b68454`, `b1c771c`. Bonus: flip `<` → `<=` en DispensationRepository (main + count query).
- [x] **G7-BE + G11-BE** NPE-safe DNMA lookup en `PrescriptionServiceImpl.mapPrescriptionWithAmpDetailsOption2` y método sibling `mapPrescriptionWithAmpDetails`. WARN log con `productId` cuando lookup vacío. Setters preservados. Commits: `2bc384f`, `bfd2211`, `f3af6c2`.
- [x] **G9-BE** `DispensationSearchRow` extendido con `getPharmacyId/Name/BusinessName`; `DispensationRepository` SELECT extendido + JOIN `pharmacies`. `EnrichedDispensationRow` actualizado. Commits: `3e2ee09`, `eed3daf`.
- [x] **G10-BE** `DispensationController.search` acepta `@RequestParam pharmacyId, status`; relax `pharmacyId` a no-required. Commit: `eed3daf`.

Frontend `medics-recetalia-app` (branch `feature/workspace-bootstrap`):
- [x] **M1, M2** Eliminados `<select>` Horas/Días en modal "Buscar medicamento" (`medicine-list.component.html`); Crónico con margen. Commit: `151721f`.
- [x] **M3** `loadPrescriptions` disparado en `ngOnInit` de `prescription-list.component.ts`. Commit: `9c04f67`.
- [x] **M5, M6** Sidebar default expandido (`isSidebarHidden=false`); nombre del médico mostrado en sidebar (decoded JWT mail → MedicsService.getByEmail). Commit: `e6c4d3b`.

Frontend `farmacias-recetalia-app` (branch `feature/workspace-bootstrap`):
- [x] **F1, F2** Sidebar default expandido + nombre comercial de la farmacia. Commit: `79f7e7d`.
- [x] **F3** `dispensation-list` ngOnInit refactorizado con error handler explícito (antes faltaba). Commit: `7483514`.
- [x] **F6** `this.code = ''` tras dispensar exitoso (en pendingDispensations === 0). Commit: `105b224`.

Frontend `gestion-recetadigital-app` (branch `feature/workspace-bootstrap`):
- [x] **G1** `loadPharmacies` disparado en `ngOnInit` de `pharmacy-list.component.ts`. Commit: `99c3bb9`.
- [x] **G2** `sort=createdAt,desc` agregado en `patient.service.ts:searchPatientsByKeyword`. Commit: `0a19a79`.
- [x] **G3** `loadPrescriptions` disparado en `ngOnInit` del modal `prescription-list.component.ts` cuando `config.data.patient`. Commit: `e1abaad`.
- [x] **G5, G7-FE** Columna MÉDICO + helper `displayPrescriptionProductName(p)` con fallback `vmpDsc → ampDsc → prodMsp → productId → '—'`. Commit: `4f360b2`.
- [x] **G9-FE, G11-FE** Columnas MÉDICO/FARMACIA/ESTADO en dispensaciones; helper `displayDispensationProductName(r)` con fallback. `dispensation-search-row.ts` interface extendido. Commit: `5022605`.
- [x] **G10** Filtro Farmacia handler corregido (usaba referencia vieja); filtro Estado agregado (declaración + handler + service forward). Commit: `88c6cee`.

Deploy a pre-prod:
- [x] 7 imágenes construidas localmente y pusheadas al registry (build sequencial tras incrementar Colima a 16 GB RAM).
- [x] `deploy.sh root@138.197.150.98 /opt/recetalia` ejecutado; force-recreate de los 8 servicios.
- [x] Smoke tests HTTP verdes: 4 frontends 200, API especialities 200, transversal 404 (no expuesto), registry 200, 9 containers healthy.

### ⚠️ Pendientes a validar en browser por el usuario

- [ ] **G6** Filtro MÉDICO en gestion > Prescripciones — diagnóstico estático no encontró bug. Verificar en runtime; si sigue roto, iterar.
- [ ] **G10** Filtros en gestion > Dispensaciones — código corregido pero verificar runtime (especialmente Estado, que se agregó completo).
- [ ] **G7/G11** Fallback `productId` en medicamentos vacíos — sólo aparece si hay productos rotos en DNMA. Validar `docker logs recetalia-api-rest | grep WARN | grep DNMA` para ver si hay productos con lookup fallido.
- [ ] **G4/G8** Filtro fechas 26-03 → 24-04: ahora debería traer todos los registros. Verificar en gestión Prescripciones y Dispensaciones.
- [ ] Login flow desde los 4 frontends.
- [ ] **Git push al origin de los 4 repos** (`recetalia-api-rest:register_medic`, 3 frontends `feature/workspace-bootstrap`) — SOLO tras verificación browser.

### Follow-ups deferidos (no bloquean deploy)

- Code reviewer flagged: `applyVmpDetailsForTest` es una reimplementación paralela del production VMP branch en lugar de delegar; refactor para que `mapPrescriptionWithAmpDetailsOption2` llame al seam, así los tests cubren el path real.
- F4, F5 (Dispensadores y AMPP en farmacias > Dispensar): descartados del scope.
- M4 (Crear Paciente bug en medics): descartado del scope.

---

## Cómo usar este TODO

- Los items marcables con `[ ]` son cambios concretos y verificables. Cuando se completen, marcar `[x]` y mover los relevantes a la sección **Verificado / cerrado** con fecha y referencia al commit/PR.
- Para correcciones que afecten al **contrato HTTP compartido** (DTO, endpoint, envelope), abrir un plan en `doc/plans/` antes de empezar — el cambio probablemente toca 5+ repos.
- Para batches grandes de cambios, usar el skill `superpowers:writing-plans` para formalizar el plan con criterios de éxito.
