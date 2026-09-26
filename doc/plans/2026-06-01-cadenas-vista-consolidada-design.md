# Spec: Cadenas — Vista consolidada para Usuario Administrador (app Farmacias) — 2026-06-01

> Workstream **A1** (de la tanda nueva). A2 = "Dashboard en el app de farmacias" va en un spec separado.

## Objetivo

Dar a un **Usuario Administrador de cadena** una vista **consolidada de las dispensaciones de todas las sucursales de su cadena**, filtrable por **sucursal** y **fecha**, dentro de `farmacias-recetalia-app`. Un usuario de farmacia normal sigue viendo solo su sucursal.

## Conceptos

- **Cadena** = entidad `Franchise` en `recetalia-api-rest`. Una farmacia (`Pharmacy`) pertenece a 0 o 1 cadena vía `Pharmacy.franchiseId`.
- **Sucursal** = una `Pharmacy` con `franchiseId` asignado.
- **Usuario Administrador de cadena** = usuario de farmacia con el rol nuevo `ROLE_PHARMACY_ADMIN`. Su cadena se deriva de **su propia farmacia** (`email → Pharmacy → franchiseId`), reutilizando el mecanismo de scope que ya usa el app. Sin tabla ni columna ni vínculo nuevo.

## Alcance

### En alcance
1. Rol `ROLE_PHARMACY_ADMIN` (seed en `security-api`).
2. `farmacias-recetalia-app`: el `authGuard` acepta `ROLE_PHARMACY_ADMIN` (además de `ROLE_PHARMACY`); ítem de menú **"Cadenas"** visible solo para ese rol; pantalla nueva de dispensaciones consolidadas (selector de sucursal + fechas).
3. `recetalia-api-rest`: endpoint nuevo para listar las sucursales de una cadena (poblar el selector); autorizar `ROLE_PHARMACY_ADMIN` en los endpoints que use la pantalla.

### Fuera de alcance (explícito)
- **ABM del admin en Gestión** (alta automática del usuario admin): follow-up. En v1 el rol `ROLE_PHARMACY_ADMIN` se asigna manualmente/seed a un usuario de farmacia existente.
- **A2 — Dashboard en farmacias** (spec separado).
- Permisos finos por sucursal dentro de la cadena (el admin ve todas las sucursales de su cadena).
- Cambiar el endpoint de búsqueda de dispensaciones (ya soporta lo necesario).

## Hechos verificados (reutilizables)

- `GET /api/dispensations/search` ya acepta `pharmacyId`, `franchiseId`, `startDate`, `endDate` (+ otros) y devuelve `Page<DispensationSearchRow>`. Con `franchiseId` trae las dispensaciones de **todas** las sucursales de la cadena; agregando `pharmacyId` se filtra una sucursal.
- `farmacias-recetalia-app`: el `authGuard` valida `route.data['roles']` contra el rol del JWT; `AuthService.getCurrentUser()` resuelve la farmacia del usuario por email (`PharmacyService.getByEmail` → incluye `franchiseId`). La lista de dispensaciones existente filtra por `pharmacyId` y tiene filtros de fecha + export Excel/PDF.
- `security-api`: roles sembrados en `V2__data.sql` (no existe `ROLE_PHARMACY_ADMIN`). El rol va como string con prefijo `ROLE_` y se usa directo como authority.
- `recetalia-api-rest`: `SecurityConfiguration` valida JWT (OAuth2 resource server); algunos endpoints `permitAll`, el resto `authenticated()`; algunos con `@PreAuthorize` por rol.

## Diseño

### security-api
- Agregar el rol `ROLE_PHARMACY_ADMIN` (INSERT en la tabla `roles`, siguiendo `V2__data.sql`). Como Flyway está deshabilitado, se inserta también en la DB pre-prod (igual que el resto de seeds).

### recetalia-api-rest (hexagonal)
- **Nuevo endpoint**: `GET /api/pharmacies/by-franchise/{franchiseId}` → lista las `Pharmacy` (sucursales) de una cadena. Implementación: `PharmacyRepository.findByFranchiseId(franchiseId)` (excluyendo `deletedAt`), mapeado a `PharmacyResponse`. Patrón: controller → service → repository, igual que el resto de `Pharmacy`.
- **Autorización**: asegurar que `ROLE_PHARMACY_ADMIN` pueda llamar `GET /api/dispensations/search` y `GET /api/pharmacies/by-franchise/{id}`. El JWT decoder ya mapea el claim `role` a authority; con `authenticated()` alcanza. Si algún endpoint tiene `@PreAuthorize` que excluya al admin, ampliarlo.
- El `currentUserAuthenticatedService` (resolución por email) ya cubre `ROLE_PHARMACY_ADMIN` si su email corresponde a una `Pharmacy`.

### farmacias-recetalia-app
- **Guard / routing**: agregar `ROLE_PHARMACY_ADMIN` a `data.roles` de la ruta home (junto a `ROLE_PHARMACY`), o una ruta hija específica `cadenas` con `data: { roles: ['ROLE_PHARMACY_ADMIN'] }`.
- **AuthService**: exponer el `franchiseId` del usuario actual (hoy `getCurrentUser()` devuelve `pharmacyId`; agregar `franchiseId`). La pantalla Cadenas lo usa para el `franchiseId` del consolidado.
- **Menú (sidebar)**: ítem **"Cadenas"** con `*ngIf` por rol admin (el sidebar lee el rol del usuario actual).
- **Pantalla "Cadenas" (nueva)**: 
  - Al iniciar, obtiene el `franchiseId` del admin y carga las sucursales de la cadena vía `GET /api/pharmacies/by-franchise/{franchiseId}` para el **selector de sucursal** (incluye opción **"Todas"**).
  - Tabla de dispensaciones consultando `GET /api/dispensations/search?franchiseId=<cadena>[&pharmacyId=<sucursal>]&startDate&endDate` (paginada). Reutiliza el componente/estructura de la lista de dispensaciones existente (columnas, paginación, export si aplica), cambiando el scope de `pharmacyId` a `franchiseId` + selector de sucursal.
  - Filtros: selector de sucursal (default "Todas") + rango de fechas.

### Flujo

```
Login (ROLE_PHARMACY_ADMIN) → guard OK → menú muestra "Cadenas"
Pantalla Cadenas:
  getCurrentUser() → franchiseId del admin
  GET /api/pharmacies/by-franchise/{franchiseId} → sucursales (selector)
  GET /api/dispensations/search?franchiseId=…[&pharmacyId=…]&startDate&endDate → tabla consolidada
```

## Creación de un admin para pruebas

Asignar `ROLE_PHARMACY_ADMIN` (en `securitydb.user_roles`) a un usuario de farmacia existente cuya `Pharmacy` tenga `franchiseId` (p.ej. una sucursal de **Pigalle**). Verificar que su email exista como `Pharmacy` en `recetali_receta`.

## Testing

- **Backend**: test de `PharmacyService.getByFranchise` / repositorio (`findByFranchiseId` devuelve solo las de esa cadena, excluye soft-deleted). El `search?franchiseId` ya está cubierto por el endpoint existente.
- **Manual/E2E**: con un usuario admin de prueba (rol asignado), login en farmacias → ver "Cadenas" → el consolidado muestra dispensaciones de varias sucursales; filtrar por una sucursal y por fechas funciona; un usuario `ROLE_PHARMACY` normal **no** ve "Cadenas".

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| El admin no tiene `franchiseId` (su farmacia es independiente) | Validar: si no hay cadena, mostrar mensaje ("tu farmacia no pertenece a una cadena") y no romper |
| Volumen alto de dispensaciones de la cadena | La búsqueda ya es paginada (`Page`) |
| Endpoint de búsqueda con `@PreAuthorize` que excluya al admin | Revisar y ampliar la autorización en implementación |
| JWT single-role: un usuario admin que además tenga otro rol podría caer en otro claim | Asignar `ROLE_PHARMACY_ADMIN` como rol del usuario admin (cuenta dedicada) |

## Criterios de éxito

- [ ] Existe el rol `ROLE_PHARMACY_ADMIN` y un usuario admin de prueba puede loguearse en farmacias.
- [ ] El admin ve el ítem "Cadenas"; un `ROLE_PHARMACY` normal no.
- [ ] La pantalla Cadenas muestra dispensaciones consolidadas de la cadena, con selector de sucursal (incl. "Todas") y filtro de fechas, funcionando.
- [ ] `GET /api/pharmacies/by-franchise/{id}` devuelve las sucursales de la cadena (sin las eliminadas).
- [ ] Test del repositorio/servicio en verde.

## Decisiones tomadas

| # | Tema | Decisión |
|---|---|---|
| 1 | Identidad del admin | Rol nuevo `ROLE_PHARMACY_ADMIN` (seed, sin tabla/columna) |
| 2 | Cadena del admin | Derivada de su propia farmacia (`email → Pharmacy → franchiseId`) |
| 3 | Consolidado | Reusa `GET /api/dispensations/search?franchiseId=…` (existente) |
| 4 | Selector de sucursal | Endpoint nuevo `GET /api/pharmacies/by-franchise/{id}` |
| 5 | Alta del admin | Manual/seed en v1 (ABM en Gestión = follow-up) |
| 6 | Dashboard farmacia | Spec separado (A2) |
