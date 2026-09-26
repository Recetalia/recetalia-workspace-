# Planes transversales

Planes de implementación que afectan a **más de un proyecto** del workspace (frontends ↔ APIs, o cambios de contrato cross-repo).

Para planes que viven dentro de un solo proyecto, usar el `doc/plans/` de ese proyecto.

## Formato

Seguir el skill `superpowers:writing-plans` para el formato (objetivos, criterios de éxito verificables, pasos, riesgos, checkpoints de revisión).

## Candidatos identificados en el análisis inicial

Ver la sección **Tech debt transversal** en [architecture-overview.md](architecture-overview.md). Son cambios que probablemente justifiquen un plan dedicado aquí:

- Rotación de secrets (JWT, DB, Twilio, SMTP) y saneamiento de `application.yml` en las 3 APIs.
- Reemplazo del AES-ECB hardcoded en los 4 frontends + security-api por TLS + password hashing server-side real.
- Hash de passwords en DB de `recetalia-api-rest`.
- Unificación del formato de paginación (`Pagination<T>` vs `Page<T>`).
- Agregar Spring Security + filtros JWT a `transversal-recetalia-api`.
- Cerrar `/api/dnmaxml/read` y `/api/email/send` (transversal).
- Revertir el `JwtTokenFilter` comentado en `security-api-recetalia`.
- Des-comentar y completar el bloqueo de usuarios `INACTIVE` en los 4 `authGuard`.
- Corregir `POST /api/medics` (hacer protegido y quitar campos sensibles del request).
- Habilitar migraciones (Flyway) y eliminar `ddl-auto=none`.
- Corrección coordinada de typos del contrato (`frecuency`, `isCronic`, `Droug`, etc.) — requiere deploy sincronizado.
