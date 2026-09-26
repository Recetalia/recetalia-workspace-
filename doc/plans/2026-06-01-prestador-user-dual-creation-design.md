# Spec: Cuenta de login de Prestador desde Gestión (creación dual) — 2026-06-01

> Workstream **B** de la tanda nueva. Reemplaza el alcance inicial ("usuario de consulta" + "usuario de conexión" separados): por decisión del usuario, **un mismo usuario de prestador sirve para ambas cosas** (consultar en el app y que la integración lo use para empujar recetas por la API). Sin separación de cuentas, sin esquema nuevo, sin rol nuevo, sin auth nueva.

## Contexto y problema

Hoy, cuando **Gestión** da de alta un Prestador (`MedicalProvider`), se crea **solo la entidad de negocio** en `recetalia-api-rest` (`MedicalProviderServiceImpl.createMedicalProvider` solo hace `save`). **No se crea la cuenta de login** en `security-api`. Por eso el prestador `medicare` se creó **a mano**.

En cambio, el alta de **Farmacia** sí hace **creación dual**: persiste la `Pharmacy` y registra el usuario en `security-api` con rollback si falla (`PharmacyServiceImpl.create` → `securityApiRecetaliaPort.registerUser(...)`).

**El objetivo:** que Gestión cree y gestione la cuenta de login del prestador, igual que hace con farmacias. Esa única cuenta (`ROLE_MEDICAL_PROVIDER`) ya sirve para:
- **Consulta**: el humano entra al `medical-provider-app`.
- **Conexión/API**: el sistema del prestador hace login → JWT → `POST /api/prescriptions/upsert-and-create` (ya protegido con `ROLE_MEDICAL_PROVIDER`).

Ambos flujos **ya funcionan** con una cuenta; lo único que falta es que Gestión la pueda **crear y resetear su clave**.

## Alcance

### En alcance
1. **Creación dual** en el alta de prestador: `createMedicalProvider` registra además el usuario de login en `security-api` (rol `ROLE_MEDICAL_PROVIDER`), con **rollback** de la entidad si el registro falla (mismo patrón que farmacias).
2. **Reset de password** del usuario del prestador desde Gestión (reutiliza `securityApiRecetaliaPort.renewPassword`).
3. **Crear** la sección **"Prestadores"** en `gestion-recetadigital-app` (hoy NO existe — solo hay un `medical-provider.service.ts` suelto, sin pantalla). Incluye: ruta + ítem de menú + listado + form de alta/edición (con cifrado AES del password + `info`) + acción "Resetear contraseña".
   - Nota: `MedicalProviderRequest` (backend) NO tiene `info` hoy → se agrega; el form de Gestión cifra el password reutilizando el mismo CryptoJS AES-ECB que ya usa el alta de farmacia.

### Fuera de alcance (explícito)
- **Separar** consulta vs conexión en dos cuentas (descartado por decisión: una sola cuenta hace ambas).
- **Auth por API-key / client-credentials** (queda para una iteración futura; hoy la integración usa el login JWT).
- **Dar de baja / desactivar el login**: `security-api` **no expone** endpoint para deshabilitar un usuario (`is_active`); solo register/renew/reset/login/refresh. Toggle de `MedicalProvider.status` (negocio) es posible pero **no** deshabilita el login. Se deja fuera; si se necesita, es un plan aparte que agrega endpoint en `security-api` + método en el puerto.
- Migrar el `medicare` existente (ya tiene su cuenta; no se toca).

## Datos / hechos verificados

- `MedicalProviderRequest` ya tiene `email`, `password` (línea 45), `name`, `status`, etc.
- `MedicalProviderServiceImpl.createMedicalProvider` solo persiste la entidad (no llama a security).
- Puerto existente `SecurityApiRecetaliaPort`: `registerUser(...)` → `POST {security}/api/auth/register`; `renewPassword(...)` → `POST {security}/api/auth/renew-password`.
- DTO `UserRequestSecurityApiRecetalia(name, email, password, role, applicationApiKey, info)`.
- Patrón de farmacia: `registerUser(name, email, password, "ROLE_PHARMACY", "farmacias-recetalia-app", info)`; security hace `applicationRepository.findByApiKey(applicationApiKey)`. En `applications`, `api_key == name`.
- Apps existentes: `security-api-recetalia`, `medics-recetalia-app`, `gestion_recetadigital`, `farmacias-recetalia-app`. **No hay** una app dedicada de prestadores.
- `medicare` (la cuenta existente) está en la app `security-api-recetalia`, rol `ROLE_MEDICAL_PROVIDER`.

## Diseño

### Backend — recetalia-api-rest (hexagonal, mismo patrón que `Pharmacy`)

`MedicalProviderServiceImpl.createMedicalProvider(request)`:
1. Persistir `MedicalProvider` (como hoy).
2. Llamar `securityApiRecetaliaPort.registerUser(new UserRequestSecurityApiRecetalia(`
   `request.getName(), request.getEmail(), request.getPassword(), "ROLE_MEDICAL_PROVIDER", <appApiKey>, request.getInfo()))`.
3. Si el registro falla → `medicalProviderRepository.delete(...)` (rollback) y propagar el error (igual que farmacias).
4. (Opcional) email de confirmación si farmacias lo hace; si no, omitir.

**Reset password**: nuevo método de servicio `resetPassword(medicalProviderId|email, newPassword, info)` que invoca `securityApiRecetaliaPort.renewPassword(...)`. Exponer endpoint `POST /api/medical-providers/{id}/reset-password` (o `/reset-password` por email), autenticado (rol gestión).

**Decisión — `applicationApiKey` del prestador:** reutilizar **`security-api-recetalia`** (donde ya vive `medicare`), para no introducir una app nueva. (Alternativa: agregar una fila `medical-provider-app` en `applications` — es un `INSERT`, no una tabla nueva; se puede hacer después si se quiere separar el tenant.)

**Sin cambios** en entidades, ni en el endpoint de recepción de recetas, ni en el modelo de auth.

### Frontend — gestion-recetadigital-app (ABM Prestadores existente)

- Verificar que el **form de alta** de prestador envíe `password` y el `info` (string para el cifrado AES, como en los otros altas). Si ya lo envía, no se toca; si no, agregar el campo password al form.
- Agregar acción **"Resetear contraseña"** en la lista/detalle de prestadores → diálogo con nueva clave → `POST /api/medical-providers/{id}/reset-password`. Mismo patrón PrimeNG (dialog) que el resto del ABM.

### Flujo resultante

```
Gestión: alta de prestador (name, email, password, ...)
  → recetalia-api-rest: save(MedicalProvider) + registerUser(security, ROLE_MEDICAL_PROVIDER)  [rollback si falla]
Prestador / su sistema:
  → login (email, password) → JWT
  → app medical-provider (consulta)   |   POST /api/prescriptions/upsert-and-create (push)   [ambos con el mismo JWT]
```

## Testing

- **Backend**: test de `createMedicalProvider` con el puerto de security **mockeado**: (a) éxito → entidad persistida + `registerUser` invocado con rol `ROLE_MEDICAL_PROVIDER`; (b) fallo de security → rollback (delete) + excepción. Test de `resetPassword` → invoca `renewPassword`.
- **Manual**: alta de un prestador de prueba desde Gestión → login con esas credenciales en `medical-provider-app` (consulta) y `POST /upsert-and-create` con el JWT (push).

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| `registerUser` falla (email ya existe en security) y deja la entidad creada | Rollback (delete) como en farmacias; devolver error claro |
| El form de Gestión no manda `password`/`info` | Verificar en implementación; agregar campo si falta |
| Cifrado AES del password (`/register` lo descifra) | Usar el mismo `info` y cifrado que los otros altas duales; o usar `/registerBack` si se quiere mandar password plano (a confirmar en el plan) |
| No se puede desactivar el login desde Gestión | Documentado como fuera de alcance; plan separado si se necesita |

## Criterios de éxito

- [ ] Alta de prestador desde Gestión crea la entidad **y** la cuenta de login (`ROLE_MEDICAL_PROVIDER`) en security-api, con rollback ante fallo.
- [ ] Con esas credenciales, el prestador entra al `medical-provider-app` (consulta) y puede `POST /upsert-and-create` (push) con el JWT.
- [ ] Gestión puede resetear la contraseña del prestador.
- [ ] Tests del service (éxito + rollback) en verde.

## Decisiones tomadas

| # | Tema | Decisión |
|---|---|---|
| 1 | Separación consulta/conexión | **No** — una sola cuenta hace ambas (opción 2) |
| 2 | Esquema nuevo | **No** — sin tabla ni columna ni rol nuevo |
| 3 | Auth de la integración | Reusa login JWT actual (API-key queda para futuro) |
| 4 | Rol de la cuenta | `ROLE_MEDICAL_PROVIDER` (existente) |
| 5 | App/tenant | Reusar `security-api-recetalia` (como medicare) |
| 6 | Baja de login | Fuera de alcance (security-api no lo soporta hoy) |
| 7 | Patrón backend | Creación dual idéntica a `PharmacyServiceImpl` (hexagonal, con rollback) |
