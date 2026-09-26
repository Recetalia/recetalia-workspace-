# Recetalia — Arquitectura transversal del workspace

Mapa completo de cómo encajan las 4 apps Angular con las 3 APIs Spring Boot. Derivado del análisis de cada proyecto (ver `CLAUDE.md` y `doc/specs/` en cada uno). Todas las afirmaciones son verificables en código.

---

## 1. Inventario de proyectos

### Frontends (Angular SSR, NgModule, TypeScript strict)

| Proyecto | Angular | Rol protegido | UI stack | Observable distintivo |
|---|---|---|---|---|
| [farmacias-recetalia-app](../farmacias-recetalia-app/) | 18.2 | `ROLE_PHARMACY` | PrimeNG 17 + Material 18 + Bootstrap 5 | `authGuard` llama al backend en cada activación |
| [medics-recetalia-app](../medics-recetalia-app/) | 18.2 | Médico | PrimeNG 17 + Material + Bootstrap + Quill + jQuery | Schematic `standalone: false` |
| [medical-provider-app](../medical-provider-app/) | 18.1 | Provider | Material 18 + PrimeNG 17 + ngx-charts | Configuraciones Angular se llaman `local` / `prod` (no estándar) |
| [gestion-recetadigital-app](../gestion-recetadigital-app/) | 18.2 | `ROLE_MANAGEMENT` | PrimeNG 17 (primario) + Material (solo login) + Bootstrap | Exports XLSX/PDF client-side con guard `isPlatformBrowser` |

### APIs (Spring Boot 3.x, Java 21)

| Proyecto | Boot | Puerto | Persistencia | Base path | Propósito |
|---|---|---|---|---|---|
| [recetalia-api-rest](../recetalia-api-rest/) | 3.3.0 | — | JPA + MySQL | `/api/*` | CRUD del dominio: medics, medical-providers, especialities, patients, prescriptions |
| [security-api-recetalia](../security-api-recetalia/) | 3.3.4 | 8091 | JPA + MySQL | `/api/auth/*` | Login, refresh, reset de password, gestión de usuarios con roles |
| [transversal-recetalia-api](../transversal-recetalia-api/) | 3.4.1 | 8093 | R2DBC + MySQL (2 DBs) | `/api/*` | Catálogo DNMA (Uruguay), ingesta XML, integraciones Twilio WhatsApp + SMTP |

---

## 2. Mapa de integración apps ↔ APIs

```
  ┌─────────────────────────┐   ┌─────────────────────────┐
  │   4 Angular frontends   │   │   4 Angular frontends   │
  │  (environment.apiUrl)   │   │ (securityApiRecetaliaUrl)│
  └────────────┬────────────┘   └────────────┬────────────┘
               │                              │
               ▼                              ▼
     ┌──────────────────┐           ┌──────────────────────┐
     │ recetalia-api-   │           │ security-api-        │
     │     rest         │           │    recetalia         │
     │ (CRUD dominio)   │           │ (login / reset)      │
     │   MySQL JPA      │           │   MySQL JPA :8091    │
     └──────────────────┘           └──────────┬───────────┘
                                               │ REST (reset emails)
                                               ▼
                                ┌──────────────────────────────┐
                                │ transversal-recetalia-api    │
                                │ (DNMA catalog, WhatsApp,     │
                                │  email, XML ingest) :8093    │
                                │ WebFlux + R2DBC, 2 DBs       │
                                └──────────────────────────────┘
```

**Observaciones del mapa:**
- Los frontends **NO** apuntan directamente a `transversal-recetalia-api` — el env solo expone los otros dos.
- `security-api-recetalia` **sí** consume `transversal-recetalia-api` para envío de emails (reset-password).
- `transversal-recetalia-api` se conecta a dos bases separadas: `recetali_receta` (dominio) y `recetali_dnma` (catálogo medicamentos Uruguay).
- No hay comunicación asíncrona (bus de eventos): todo es REST síncrono.

---

## 3. Flujo de autenticación end-to-end

1. **Cliente (cualquiera de los 4 frontends)** cifra el password con `CryptoJS` AES-ECB/PKCS7:
   - Clave = `"ahjsdfhjbqer56243"` + `dynamicInfo` (10 chars UUID) → paddeada a 32 bytes.
   - Body: `{ email, password: <ciphertext>, info: <dynamicInfo> }`.
2. **security-api-recetalia** (`/api/auth/login`) descifra con `EncryptionUtil` usando la **misma clave hardcoded** + `info` recibido.
3. Compara contra el password en DB (plain text) y devuelve JWT **HS256**, 24h, con claims `sub`, `mail`, `role`, `iat`, `exp`.
4. **Frontend** persiste `token` + `role` en `localStorage`.
5. `AuthInterceptor` agrega `Authorization: Bearer …` a cada request saliente y dispara logout en 401.
6. `authGuard` / `AuthGuard` protege las rutas; valida rol contra `localStorage.role`.
7. **recetalia-api-rest** valida el mismo JWT como OAuth2 resource-server con un **secret compartido distinto** (HS512 base64).

### Discrepancias detectadas en el flujo

- **security-api usa HS256, recetalia-api-rest usa HS512 con secret distinto** → parece un mismo token pero cada API verifica con configuración independiente. Verificar qué secret se está usando realmente en producción.
- **`JwtTokenFilter` en security-api-recetalia está comentado** (`addFilterBefore(...)` deshabilitado) — la validación de JWT entrante en esa API está efectivamente rota.
- **`renew-password` en security-api NO requiere auth ni token de reset** → cualquiera puede resetear el password de cualquier usuario por email.
- **Reset token = `UUID.randomUUID().substring(0,5)`** → 5 caracteres, entropía trivialmente bruteforceable.
- **`authGuard` en los 4 frontends** detecta usuarios `INACTIVE` pero la rama que bloquea está **comentada** → inactivos pasan.
- **No hay refresh token real** — el campo `refreshToken` se recibe pero se ignora; JWT expiry sólo surge en el siguiente 401.

---

## 4. Contrato HTTP compartido

Patrones de request/response usados por **todas** las APIs y servicios:

- **Response envelope** — `recetalia-api-rest`: `GenericResponse<T> { status, answer, applicationProvider, metadata, serverDateTime }`. Frontends unwrappean `.answer` cuando `status === 'SUCCESS'`.
- **Paginación** — dos formatos coexisten en el workspace:
  - `Pagination<T>` (shape completa Spring Data) — prescriptions, medics, pharmacies, patients.
  - `Page<T>` (shape simplificada) — dispensations.
- **Error centralizado** en `recetalia-api-rest` vía `GlobalExceptionHandler` (`ResourceNotFoundException` → 404, otros → 500).

---

## 5. Modelo de dominio compartido

Entidades que circulan entre apps y APIs con la misma forma (aproximada):

| Entidad | Duplicada en | Observación |
|---|---|---|
| `Medic` | recetalia-api-rest, consumida por 4 frontends | Password en plain text en DB |
| `MedicalProvider` | recetalia-api-rest | Password en plain text |
| `Patient` | recetalia-api-rest | Password en plain text; `PatientResponse` expone `password` al frontend |
| `Pharmacy` | recetalia-api-rest | Password en plain text |
| `Prescription` | recetalia-api-rest + transversal-recetalia-api | Typos: `frecuency`, `frecuencyUnit`, `isCronic`, `cronicCode` |
| `Dispensation` | recetalia-api-rest | `condvtaId` es `string\|null` en `DispensationRequest` pero `number\|null` en `PrescriptionRequest` |
| `Product` / `Droug` / `Laboratory` / `Vademecum` | recetalia-api-rest + transversal-recetalia-api | Typo `Droug`; `especialityId`, `nombreLaboratory`, `rutLaboratory` |
| `User` (con roles `@ManyToMany`) | security-api-recetalia | Sólo esta API modela roles explícitamente; el resto del workspace usa un único string `role` |

---

## 6. Tech debt transversal (afecta varios proyectos)

### Seguridad (crítico)

- **AES-ECB con clave hardcoded `ahjsdfhjbqer56243`** presente en los 4 frontends (bundle JS público) **y** en `security-api-recetalia` — es ofuscación, no cifrado.
- **Secrets commiteados en repo:** JWT secret + credenciales MySQL DigitalOcean + credenciales Twilio + SMTP viven en `application.yml` de las 3 APIs.
- **`transversal-recetalia-api` sin seguridad alguna:** sin `spring-security`, sin filtros, sin `SecurityWebFilterChain`. Endpoints notables expuestos públicamente:
  - `/api/dnmaxml/read?path=...` — acepta rutas de filesystem arbitrarias.
  - `/api/email/send` — relay SMTP abierto.
- **`POST /api/medics` en recetalia-api-rest es público** — cualquiera crea médicos, incluso seteando `status` y `medicalProviderId`.
- **`@PreAuthorize("hasRole('TESTROLEr')")`** en `/api/prescriptions/admin-data` (typo y rol inexistente) + endpoint `admin-data2` que dumpea authorities del caller.
- **CORS `allowedOrigins("*")`** en recetalia-api-rest y transversal-recetalia-api.
- **Passwords en plain text** en DB de `recetalia-api-rest` en entidades Medic/MedicalProvider/Patient/Pharmacy/User.
- **Logs sensibles** — `SecurityConfiguration` imprime el JWT secret decodificado al arrancar; `io.jsonwebtoken` en DEBUG.

### Consistencia

- **Typos baked-in** en el contrato (frontend → backend): `frecuency`, `frecuencyUnit`, `isCronic`, `cronicCode`, `nombreLaboratory`, `rutLaboratory`, `Droug`, `Especiality`, `RegistergModule`, `getPatiensByMedic…`, `search-available-Prescriptions-by-code`. Cambiarlos requiere coordinar 5+ repos.
- **Paginación dual** (`Pagination<T>` vs `Page<T>`).
- **`enviroment/`** (sic) en `security-api-recetalia`.

### Frontend común

- Ninguno tiene **lint/format** (ni ESLint ni Prettier).
- `provideHttpClient()` duplicado en `app.module.ts` + `HttpClientModule` legacy en varios frontends.
- `provideClientHydration()` comentado a pesar de SSR activo.
- `authGuard`/`AuthGuard` con rama `INACTIVE` comentada en los 4 frontends — bug consistente.
- `refreshToken` llega y se ignora en todos.

### Backend común

- **Sin migraciones aplicadas:** `recetalia-api-rest` usa `ddl-auto=none` sin Flyway; `security-api-recetalia` tiene dependencia Flyway pero `enabled: false`. Schema drift silencioso.
- **Field injection** (`@Autowired` sobre atributos) en `recetalia-api-rest`.
- **Soft-delete cosmético:** columnas `deletedAt` sin `@SQLDelete`/`@Where` → `delete()` borra físico.
- **Violaciones de arquitectura hexagonal** en `transversal-recetalia-api` — `domain/usecase` depende directamente de adapters concretos.

---

## 7. Cómo usar este documento

- **Antes de tocar el contrato** (DTO compartido, endpoint, envelope) → releer sección 4 y 5; el cambio probablemente toca 5+ repos.
- **Antes de trabajar en auth/login/roles** → releer sección 3 y la subsección de Seguridad en 6.
- **Para planes cross-project** (migraciones coordinadas, rotación de secrets, refactor del contrato) → crear un plan en [plans/](plans/) usando el skill `superpowers:writing-plans`.
- **Para el contexto específico de un proyecto** → ir a su `CLAUDE.md` + `doc/specs/`.
