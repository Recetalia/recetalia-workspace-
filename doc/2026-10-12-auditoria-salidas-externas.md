# Auditoría: ¿a dónde envía datos Recetalia? — 2026-10-12

Relevamiento del código de las 3 APIs y los 5 frontends, contrastado con el contenedor real de PROD
(`159.203.26.217`, `docker inspect` de las variables `EXTERNAL_API_*`, sin leer valores secretos).

## Conclusión

No hay telemetría, analytics, trackers ni envíos ocultos. Todo lo que sale hacia afuera es una
integración funcional conocida. Tres de ellas reciben **datos de salud o personales de terceros**:

| Destino | Desde | Qué datos | Cuándo |
|---|---|---|---|
| **Twilio** (EE.UU.) — WhatsApp | transversal `WhatsAppServiceImpl.java:32`, payload en `PrescriptionUsesCaseServiceUseCaseImpl.java:242-262` | teléfono, nombre y apellido del paciente, médico, código de receta (6 car.), medicamentos con frecuencia y duración | scheduler c/5 min + recordatorio diario 10:00 |
| **SMTP `mail.iwtg.com`** | transversal `EmailService.java:45` | lo que llegue a `POST /email/send`: altas/validaciones de médicos y farmacias, invitación QF, anulación de dispensación, link de reset de contraseña con su token. Copia siempre a `hello@recetalia.com` | eventos de alta, validación, reset |
| **Consilio** `app.consilio.medicinainteligente.ai` (165.22.231.175) | api-rest `ConsilioPortImpl.java:108` | principios activos + perfil: sexo, edad, embarazo/semanas, lactancia, función renal/hepática, alergias, CIE-10. **Sin nombre ni CI** | el médico consulta interacciones al recetar. **Encendido en PROD** (verificado) |

Otros destinos externos sin datos de pacientes:
- DigitalOcean API: sólo IDs del droplet y de la DB, para el monitor.
- Bases MySQL gestionadas en DigitalOcean.
- Let's Encrypt.
- En el navegador: Google Fonts, jsDelivr (bootstrap.js) y cdnjs (materialize.css). Reciben IP y Referer de cada usuario.

Verificado en PROD:
- `EXTERNAL_API_SECURITY_API_RECETALIA` y `EXTERNAL_API_TRANSVERSAL_API_RECETALIA` apuntan a la red interna de Docker.
- `api.recetalia.com/.../email/send` devuelve 404 desde afuera.

## ⚠ Envío oculto a un tercero — sitio institucional (activo en PROD)

Lo encontré en una segunda pasada, por pedido de la sesión de DoctorConsultas, que halló lo mismo allá.
El sitio se importó tal cual del Plesk viejo (commit `c8269be`, 2026-07-10).

- `recetalia-site/mailer/_email-sender.php:38` hace `AddBCC("soporte@avisil.com")`.
  - Lo mismo en `inversores/mailer/_email-sender.php:38` y `lanzamiento/mailer/_email-sender.php:38`.
  - Lo usan los formularios de contacto de `index.php:248`, `tutorial-farmacias/index.php:128` e `inversores/index.php:178`.
  - Viajan nombre, email y comentario del visitante; en el formulario de lanzamiento, también teléfono y especialidad.
- `lanzamiento/mailer/contact.php:49` y `contact2.php:41` tienen `$address = "soporte@avisil.com"` como destinatario único.
  - Ningún formulario los llama, pero están desplegados y se pueden ejecutar con un POST directo.
- `_email-sender.php:28-30` tiene en el código la contraseña SMTP de `notificaciones@doctorconsultas.com`, con `verify_peer=false`.
- Verificación en PROD:
  - En el contenedor `recetalia-site` del .217 están esas líneas.
  - `recetalia.com/`, `/lanzamiento/` e `/inversores/` responden 200.
- En los backends Java no hay BCC ni destinatarios ajenos activos: `jhomotta@gmail.com` sólo aparece en firmas `@author` y en líneas comentadas.
- No hay webhooks ni pagos.

## Riesgos encontrados (no son fugas hoy, son caminos a una)

1. **URLs por defecto públicas en `application.yml`** (sin `${...}`). Las tapa el override del compose.
   - `recetalia-api-rest:84`: security-api apunta a `https://apipre.recetalia.com`. Se le mandan contraseñas en claro.
   - `recetalia-api-rest:85` y `security-api-recetalia:59`: transversal apunta a `https://api.recetadigital.uy` (hoy no responde).
   - Un stack sin el override enviaría credenciales y tokens de reset por internet a otro host.
2. **`/email/send` sin autenticación**: acepta cualquier destinatario, cuerpo y adjunto. Sólo lo protege que no se publique fuera de la red de Docker.
3. **`mail.debug: true`** en `transversal app-service/application.yml:62`: volcaría la sesión SMTP (incluidos los tokens) a stdout.
   No se vio en los logs de PROD de los últimos 7 días (`grep -c "DEBUG SMTP\|RCPT TO"` = 0).
4. **Datos personales en logs**:
   - `PatientServiceImpl.java:68` imprime la CI del paciente.
   - `show-sql` y Spring Security en DEBUG en la configuración principal.
   - `UserServiceImpl.java:114` loguea emails.
5. **Frontends**:
   - `console.log(finalKey)` imprime la clave de cifrado de la contraseña en el login de medics `:93`, farmacias `:103`, gestion `:93` y medical-provider `:89`. La clave además está fija en el código.
   - bootstrap de jsDelivr se carga sin `integrity` (SRI) en farmacias, medics y qf, con el JWT en localStorage. Un CDN comprometido podría robar sesiones.
6. **Dominio viejo `recetadigital.uy`**:
   - `medical-provider-app/src/environments/environment.ts:4-5` es la configuración por defecto del build.
   - `gestion .../medic-list.component.html:37`.
7. **Twilio y Consilio como encargados de tratamiento**: datos de salud en un tercero (Twilio en EE.UU.). Requiere base legal / contrato de encargado (Ley 18.331).
