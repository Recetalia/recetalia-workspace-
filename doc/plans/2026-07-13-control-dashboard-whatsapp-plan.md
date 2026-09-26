# Monitor de WhatsApp (Dashboard de Control) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tab "WhatsApp" del dashboard de Control en Gestión: lista cada WhatsApp enviado por Twilio con su status, destinatario y las recetas vinculadas.

**Architecture:** El transversal persiste una fila `whatsapp_message` por (SID Twilio, prescription) al enviar; api-rest expone `/api/control-dashboard/whatsapp/*` (solo `ROLE_MANAGEMENT`) leyendo esa tabla y refrescando status contra Twilio vía el transversal; Gestión agrega la sección Control con el tab WhatsApp. Spec: [2026-07-13-control-dashboard-design.md](2026-07-13-control-dashboard-design.md).

**Tech Stack:** Spring WebFlux + R2DBC (transversal), Spring MVC + JPA (api-rest), Twilio SDK, Angular 18 NgModule + PrimeNG (gestion).

**Regla de branching:** branch `feat/control-dashboard` creado desde `2.x.y` en `transversal-recetalia-api`, `recetalia-api-rest` y `gestion-recetadigital-app`. NUNCA commitear en `2.x.y`. Merge solo con OK explícito de Pablo.

**Ambiente de trabajo:** todo se desarrolla y prueba contra el ambiente DEV (server LOCAL `138.197.150.98`, MySQL local puerto 3307, dominios `*pre.recetalia.com`). Prod no se toca en este plan.

---

### Task 0: Branches y DDL en dev

**Files:** ninguno (git + SQL).

- [ ] **Step 0.1: Crear branches desde 2.x.y en los 3 repos**

```bash
for r in transversal-recetalia-api recetalia-api-rest gestion-recetadigital-app; do
  cd /Users/pablo/iwtg/recetalia-workspace/$r
  git checkout 2.x.y && git pull && git checkout -b feat/control-dashboard
done
```

Expected: `Switched to a new branch 'feat/control-dashboard'` en cada repo.

- [ ] **Step 0.2: Crear la tabla en la MySQL dev (LOCAL)**

```bash
ssh recetalia-preprod 'docker exec -i recetalia-mysql mysql -urecetalia_dev -pRecDev98_x7Kq2mVt recetali_receta' <<'SQL'
CREATE TABLE IF NOT EXISTS whatsapp_message (
  id varchar(36) NOT NULL,
  twilioSid varchar(40) NOT NULL,
  prescriptionId varchar(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL, -- ⚠️ debe matchear la collation de prescription.id (latin1_swedish_ci en la DB real) o el FK falla con ERROR 3780
  notificationId varchar(36) NULL,
  phone varchar(50) NOT NULL,
  templateType varchar(30) NOT NULL,
  status varchar(20) NOT NULL DEFAULT 'queued',
  errorCode varchar(20) NULL,
  sentAt timestamp NOT NULL,
  statusUpdatedAt timestamp NULL,
  createdAt timestamp(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updatedAt timestamp(6) NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  UNIQUE KEY uq_wa_sid_prescription (twilioSid, prescriptionId),
  KEY idx_wa_sentAt (sentAt),
  KEY idx_wa_status (status),
  CONSTRAINT fk_wa_prescription FOREIGN KEY (prescriptionId) REFERENCES prescription (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SQL
```

- [ ] **Step 0.3: Verificar**

Run: `ssh recetalia-preprod 'docker exec recetalia-mysql mysql -urecetalia_dev -pRecDev98_x7Kq2mVt recetali_receta -e "DESCRIBE whatsapp_message;"'`
Expected: las 12 columnas de arriba.

---

### Task 1: transversal — `WhatsAppGateway` devuelve el SID

**Files:**
- Modify: `transversal-recetalia-api/infrastructure/driven-adapters/whatsapp-service/src/main/java/com/recetalia/gateway/WhatsAppGateway.java`
- Modify: `transversal-recetalia-api/infrastructure/driven-adapters/whatsapp-service/src/main/java/com/recetalia/WhatsAppServiceImpl.java`
- Test: `transversal-recetalia-api/domain/usecase/src/test/java/com/recetalia/PrescriptionNotificationDedupTest.java` (se adapta el mock)

- [ ] **Step 1.1: Cambiar la interfaz para devolver el SID**

```java
// gateway/WhatsAppGateway.java
public interface WhatsAppGateway {
  /** Envía el mensaje y devuelve el SID de Twilio del mensaje creado. */
  Mono<String> sendMessage(com.recetalia.model.WhatsAppMessage message);
}
```

- [ ] **Step 1.2: Adaptar la implementación**

En `WhatsAppServiceImpl.sendMessage`, reemplazar el cuerpo por (nota: `Mono.fromCallable`, no `fromRunnable`, porque ahora devuelve valor; `subscribeOn(boundedElastic)` porque el SDK de Twilio es bloqueante):

```java
@Override
public Mono<String> sendMessage(WhatsAppMessage message) {
  return Mono.fromCallable(() -> {
    String to = message.getTo().replace(" ", "").trim();
    Message messageResponse = Message.creator(
            new PhoneNumber("whatsapp:" + to),
            new PhoneNumber("whatsapp:" + sender.trim()),
            (String) null)
        .setContentSid(message.getContentSid())
        .setContentVariables(message.getMessageVariablesJsonString())
        .create();
    System.out.println("Message sent successfully SID: " + messageResponse.getSid());
    return messageResponse.getSid();
  }).subscribeOn(reactor.core.scheduler.Schedulers.boundedElastic());
}
```

- [ ] **Step 1.3: Compilar y correr los tests existentes (van a fallar los mocks)**

Run: `cd /Users/pablo/iwtg/recetalia-workspace/transversal-recetalia-api && ./gradlew test 2>&1 | tail -20`
Expected: FAIL de compilación en `PrescriptionNotificationDedupTest` (los `when(...sendMessage...).thenReturn(Mono.empty())` ya no tipan).

- [ ] **Step 1.4: Adaptar los mocks del test de dedup**

En `PrescriptionNotificationDedupTest`, reemplazar **todas** las ocurrencias de:

```java
when(whatsAppGateway.sendMessage(any(WhatsAppMessage.class))).thenReturn(Mono.empty());
```

por:

```java
when(whatsAppGateway.sendMessage(any(WhatsAppMessage.class))).thenReturn(Mono.just("SMtest0000000000000000000000000000"));
```

(el test `revertsClaim_whenSendFailsAfterClaim` que usa `Mono.error(...)` queda igual).

- [ ] **Step 1.5: Verificar verde y commitear**

Run: `./gradlew test 2>&1 | tail -5` → Expected: `BUILD SUCCESSFUL`.

```bash
git add -A && git commit -m "feat(whatsapp): sendMessage devuelve el SID de Twilio"
```

---

### Task 2: transversal — persistir `whatsapp_message` al enviar

**Files:**
- Create: `transversal-recetalia-api/infrastructure/driven-adapters/recetalia-db/src/main/java/com/recetalia/recetaliadb/entity/WhatsappMessageEntity.java`
- Create: `transversal-recetalia-api/infrastructure/driven-adapters/recetalia-db/src/main/java/com/recetalia/recetaliadb/repository/WhatsappMessageRepository.java`
- Create: interfaz gateway `WhatsappMessageAdapter` + su implementación en el adapter (ver step 2.1 para ubicación exacta)
- Modify: `transversal-recetalia-api/domain/usecase/src/main/java/com/recetalia/PrescriptionUsesCaseServiceUseCaseImpl.java`
- Test: `transversal-recetalia-api/domain/usecase/src/test/java/com/recetalia/WhatsappMessagePersistTest.java`

- [ ] **Step 2.1: Ubicar el patrón del adapter existente**

Run: `grep -rn "interface PrescriptionAdapter" /Users/pablo/iwtg/recetalia-workspace/transversal-recetalia-api --include="*.java"`
Expected: un archivo (probablemente en `domain/model/.../gateway/` o similar). **Colocar `WhatsappMessageAdapter` (interfaz) en ese MISMO package, y su implementación junto a la implementación de `PrescriptionAdapter`** (mismo módulo recetalia-db, package `...adapter`).

- [ ] **Step 2.2: Entity R2DBC**

```java
// recetaliadb/entity/WhatsappMessageEntity.java
package com.recetalia.recetaliadb.entity;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Table("whatsapp_message")
public class WhatsappMessageEntity {
  @Id
  private String id;

  @Column("twilioSid")
  private String twilioSid;

  @Column("prescriptionId")
  private String prescriptionId;

  @Column("notificationId")
  private String notificationId;

  @Column("phone")
  private String phone;

  @Column("templateType")
  private String templateType;

  @Column("status")
  private String status;

  @Column("errorCode")
  private String errorCode;

  @Column("sentAt")
  private LocalDateTime sentAt;

  @Column("statusUpdatedAt")
  private LocalDateTime statusUpdatedAt;
}
```

- [ ] **Step 2.3: Repository R2DBC**

```java
// recetaliadb/repository/WhatsappMessageRepository.java
package com.recetalia.recetaliadb.repository;

import com.recetalia.recetaliadb.entity.WhatsappMessageEntity;
import org.springframework.data.r2dbc.repository.Modifying;
import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;

@Repository
public interface WhatsappMessageRepository extends ReactiveCrudRepository<WhatsappMessageEntity, String> {

  @Modifying
  @Query("UPDATE whatsapp_message SET status = :status, errorCode = :errorCode, statusUpdatedAt = :now WHERE twilioSid = :sid")
  Mono<Long> updateStatusBySid(String sid, String status, String errorCode, LocalDateTime now);
}
```

- [ ] **Step 2.4: Gateway (interfaz de dominio) + implementación**

Interfaz — en el package hallado en step 2.1 (junto a `PrescriptionAdapter`):

```java
public interface WhatsappMessageAdapter {
  /** Persiste una fila por prescription vinculada al mensaje enviado. */
  Mono<Void> saveSent(String twilioSid, java.util.List<String> prescriptionIds,
                      String phone, String templateType);
}
```

Implementación — junto a la impl de `PrescriptionAdapter` en el módulo recetalia-db:

```java
@Component
@RequiredArgsConstructor
public class WhatsappMessageAdapterImpl implements WhatsappMessageAdapter {

  private final WhatsappMessageRepository repository;

  @Override
  public Mono<Void> saveSent(String twilioSid, List<String> prescriptionIds,
                             String phone, String templateType) {
    LocalDateTime now = LocalDateTime.now();
    List<WhatsappMessageEntity> rows = prescriptionIds.stream()
        .map(pid -> WhatsappMessageEntity.builder()
            .id(UUID.randomUUID().toString())
            .twilioSid(twilioSid)
            .prescriptionId(pid)
            .phone(phone)
            .templateType(templateType)
            .status("queued")
            .sentAt(now)
            .build())
        .toList();
    return repository.saveAll(rows).then();
  }
}
```

⚠️ R2DBC hace UPDATE (no INSERT) cuando el `@Id` viene seteado. Si `saveAll` no inserta, la impl debe hacer los INSERT con `R2dbcEntityTemplate.insert(...)` (inyectar `R2dbcEntityTemplate` en lugar del repository):

```java
return Flux.fromIterable(rows).flatMap(template::insert).then();
```

(elegir esta variante directamente si `BaseEntity`/el repo no implementan `Persistable`).

- [ ] **Step 2.5: Test del usecase (falla primero)**

Nuevo `WhatsappMessagePersistTest.java` en el mismo package del test de dedup, con el mismo esqueleto de mocks (copiar el setUp de `PrescriptionNotificationDedupTest`) + mock del nuevo adapter:

```java
@Test
void persistsWhatsappMessageRows_afterSuccessfulSend() {
  when(prescriptionAdapter.findPrescriptionsEnrichedByStatus(any(LocalDateTime.class), eq("PENDING")))
      .thenReturn(Flux.just(samplePrescription())); // helper existente; su DTO debe exponer getId()
  when(prescriptionAdapter.claimPendingForSending(anyCollection(), any(LocalDateTime.class)))
      .thenReturn(Mono.just(1L));
  when(whatsAppGateway.sendMessage(any(WhatsAppMessage.class)))
      .thenReturn(Mono.just("SMabc123"));
  when(whatsappMessageAdapter.saveSent(anyString(), anyList(), anyString(), anyString()))
      .thenReturn(Mono.empty());

  StepVerifier.create(service.processPendingPrescriptions())
      .expectNextCount(1)
      .verifyComplete();

  verify(whatsappMessageAdapter, times(1))
      .saveSent(eq("SMabc123"), argThat(ids -> !ids.isEmpty()), anyString(), eq("PENDING"));
}

@Test
void doesNotPersist_whenSendFails() {
  when(prescriptionAdapter.findPrescriptionsEnrichedByStatus(any(LocalDateTime.class), eq("PENDING")))
      .thenReturn(Flux.just(samplePrescription()));
  when(prescriptionAdapter.claimPendingForSending(anyCollection(), any(LocalDateTime.class)))
      .thenReturn(Mono.just(1L));
  when(whatsAppGateway.sendMessage(any(WhatsAppMessage.class)))
      .thenReturn(Mono.error(new RuntimeException("twilio down")));
  when(prescriptionAdapter.revertPendingClaim(anyCollection(), any(LocalDateTime.class)))
      .thenReturn(Mono.just(1L));

  StepVerifier.create(service.processPendingPrescriptions()).verifyComplete();

  verify(whatsappMessageAdapter, never()).saveSent(anyString(), anyList(), anyString(), anyString());
}
```

Run: `./gradlew :usecase:test 2>&1 | tail -10` → Expected: FAIL (el usecase no conoce `whatsappMessageAdapter`).

- [ ] **Step 2.6: Modificar el usecase**

En `PrescriptionUsesCaseServiceUseCaseImpl`:
1. Agregar el campo `private final WhatsappMessageAdapter whatsappMessageAdapter;` (constructor injection como los demás adapters — actualizar también la construcción del service en los tests).
2. En `handlePendingPrescription`, donde hoy hace `whatsAppGateway.sendMessage(message).thenReturn(prefix)`, encadenar la persistencia:

```java
List<String> groupIds = enrichedList.stream().map(PrescriptionViewDTO::getId).toList();
String templateType = reminders ? "REMINDER" : "PENDING";
return whatsAppGateway.sendMessage(message)
    .flatMap(sid -> whatsappMessageAdapter
        .saveSent(sid, groupIds, message.getTo(), templateType)
        .onErrorResume(persistErr -> {
          logger.error("⚠️ WhatsApp enviado (sid={}) pero falló persistir whatsapp_message: {}",
              sid, persistErr.getMessage());
          return Mono.empty(); // el envío YA salió: no revertir el claim por un error de auditoría
        })
        .thenReturn(prefix))
    .doOnSuccess(...)   // igual que hoy
    .onErrorResume(...) // igual que hoy (revert de claim si falló el ENVÍO)
```

⚠️ Si `PrescriptionViewDTO` no tuviera `getId()`, agregarle el campo `id` al DTO y al SELECT del view/query que lo llena (verificar con `grep -n "class PrescriptionViewDTO" -r domain/`).

- [ ] **Step 2.7: Verde + commit**

Run: `./gradlew test 2>&1 | tail -5` → Expected: `BUILD SUCCESSFUL` (dedup tests + nuevos).

```bash
git add -A && git commit -m "feat(whatsapp): persistir whatsapp_message (sid+prescription) al enviar"
```

---

### Task 3: transversal — endpoints internos de status e histórico Twilio

**Files:**
- Create: `transversal-recetalia-api/infrastructure/driven-adapters/whatsapp-service/src/main/java/com/recetalia/model/WhatsAppStatusDTO.java`
- Create: `transversal-recetalia-api/infrastructure/driven-adapters/whatsapp-service/src/main/java/com/recetalia/TwilioMessageQueryService.java`
- Modify: el `WhatsAppController` existente (entry-points/reactive-web) — agregar 2 GETs
- Test: `transversal-recetalia-api/infrastructure/driven-adapters/whatsapp-service/src/test/java/com/recetalia/TwilioMessageQueryServiceTest.java`

- [ ] **Step 3.1: DTO**

```java
// model/WhatsAppStatusDTO.java
package com.recetalia.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class WhatsAppStatusDTO {
  private String sid;
  private String to;         // ej "whatsapp:+59899..."
  private String status;     // queued|sent|delivered|read|failed|undelivered
  private String errorCode;  // nullable
  private String dateSent;   // ISO, nullable
}
```

- [ ] **Step 3.2: Servicio de consulta a Twilio (interfaz + impl juntas, patrón del módulo)**

```java
// TwilioMessageQueryService.java
package com.recetalia;

import com.recetalia.model.WhatsAppStatusDTO;
import com.twilio.rest.api.v2010.account.Message;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.scheduler.Schedulers;

import java.time.ZonedDateTime;
import java.util.List;

@Service
public class TwilioMessageQueryService {

  /** Status actual de una lista de SIDs (fetch individual, SDK bloqueante → boundedElastic). */
  public Flux<WhatsAppStatusDTO> fetchStatuses(List<String> sids) {
    return Flux.fromIterable(sids)
        .flatMap(sid -> reactor.core.publisher.Mono.fromCallable(() -> {
              Message m = Message.fetcher(sid).fetch();
              return toDto(m);
            })
            .subscribeOn(Schedulers.boundedElastic())
            .onErrorResume(e -> reactor.core.publisher.Mono.just(
                WhatsAppStatusDTO.builder().sid(sid).status("unknown").build())));
  }

  /** Mensajes históricos de la cuenta entre fechas (para los previos a esta feature). */
  public Flux<WhatsAppStatusDTO> listHistoric(ZonedDateTime from, ZonedDateTime to, int limit) {
    return reactor.core.publisher.Mono.fromCallable(() -> {
          var reader = Message.reader()
              .setDateSentAfter(from)
              .setDateSentBefore(to)
              .setPageSize(Math.min(limit, 500));
          return reader.read().stream().limit(limit).map(this::toDto).toList();
        })
        .subscribeOn(Schedulers.boundedElastic())
        .flatMapMany(Flux::fromIterable);
  }

  private WhatsAppStatusDTO toDto(Message m) {
    return WhatsAppStatusDTO.builder()
        .sid(m.getSid())
        .to(m.getTo())
        .status(m.getStatus() != null ? m.getStatus().toString() : null)
        .errorCode(m.getErrorCode() != null ? String.valueOf(m.getErrorCode()) : null)
        .dateSent(m.getDateSent() != null ? m.getDateSent().toString() : null)
        .build();
  }
}
```

- [ ] **Step 3.3: Test unitario del mapeo (lo llamable sin Twilio real)**

El SDK de Twilio es estático → el test cubre `toDto` indirectamente vía un test de contrato del DTO y el manejo de error de `fetchStatuses` (SID inexistente sin credenciales → cae en `onErrorResume` → status `unknown`):

```java
// TwilioMessageQueryServiceTest.java
package com.recetalia;

import com.recetalia.model.WhatsAppStatusDTO;
import org.junit.jupiter.api.Test;
import reactor.test.StepVerifier;

import java.util.List;

class TwilioMessageQueryServiceTest {

  private final TwilioMessageQueryService service = new TwilioMessageQueryService();

  @Test
  void fetchStatuses_mapsErrorsToUnknown() {
    // Sin Twilio.init() válido, el fetch lanza -> debe degradar a status=unknown, nunca propagar
    StepVerifier.create(service.fetchStatuses(List.of("SMnoexiste")))
        .expectNextMatches(dto -> dto.getSid().equals("SMnoexiste") && dto.getStatus().equals("unknown"))
        .verifyComplete();
  }
}
```

Run: `./gradlew :whatsapp-service:test 2>&1 | tail -5` → Expected: FAIL (clase no existe) → crear (step 3.2) → PASS.

- [ ] **Step 3.4: Endpoints en el WhatsAppController existente**

Localizar: `grep -rn "class WhatsAppController" infrastructure/entry-points/`. Agregar (mismo patrón `GenericResponse` del controller):

```java
@GetMapping("/status")
public Flux<WhatsAppStatusDTO> getStatuses(@RequestParam("sids") String sids) {
  return twilioMessageQueryService.fetchStatuses(Arrays.asList(sids.split(",")));
}

@GetMapping("/historic")
public Flux<WhatsAppStatusDTO> getHistoric(
    @RequestParam("from") @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
    @RequestParam("to") @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
    @RequestParam(value = "limit", defaultValue = "200") int limit) {
  ZoneId uy = ZoneId.of("America/Montevideo");
  return twilioMessageQueryService.listHistoric(
      from.atStartOfDay(uy).toOffsetDateTime().toZonedDateTime(),
      to.plusDays(1).atStartOfDay(uy).toOffsetDateTime().toZonedDateTime(),
      limit);
}
```

(inyectar `TwilioMessageQueryService` por constructor; si el controller responde `GenericResponse<T>` en los demás métodos, envolver igual para consistencia).

- [ ] **Step 3.5: Verde + commit**

Run: `./gradlew build -x test 2>&1 | tail -3` y `./gradlew test 2>&1 | tail -3` → `BUILD SUCCESSFUL`.

```bash
git add -A && git commit -m "feat(whatsapp): endpoints internos de status por SID e histórico Twilio"
```

---

### Task 4: api-rest — entity, repository y queries del monitor

**Files:**
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/domain/model/entities/WhatsappMessage.java`
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/domain/repository/WhatsappMessageRepository.java`
- Test: `recetalia-api-rest/src/test/java/com/recetalia/api/application/service/impl/ControlWhatsappServiceImplTest.java` (se escribe en Task 5; acá solo compila)

- [ ] **Step 4.1: Entity JPA**

```java
// entities/WhatsappMessage.java
package com.recetalia.api.application.domain.model.entities;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

@Getter
@Setter
@Entity
@Table(name = "whatsapp_message")
public class WhatsappMessage {

  @Id
  @Column(name = "id", nullable = false, length = 36)
  private String id;

  @Column(name = "twilioSid", nullable = false, length = 40)
  private String twilioSid;

  @Column(name = "prescriptionId", nullable = false, length = 36)
  private String prescriptionId;

  @Column(name = "notificationId", length = 36)
  private String notificationId;

  @Column(name = "phone", nullable = false, length = 50)
  private String phone;

  @Column(name = "templateType", nullable = false, length = 30)
  private String templateType;

  @Column(name = "status", nullable = false, length = 20)
  private String status;

  @Column(name = "errorCode", length = 20)
  private String errorCode;

  @Column(name = "sentAt", nullable = false)
  private Instant sentAt;

  @Column(name = "statusUpdatedAt")
  private Instant statusUpdatedAt;

  @PrePersist
  public void prePersist() {
    if (this.id == null) this.id = UUID.randomUUID().toString();
  }
}
```

- [ ] **Step 4.2: Repository con la query del listado (native, con count y filtros)**

```java
// repository/WhatsappMessageRepository.java
package com.recetalia.api.application.domain.repository;

import com.recetalia.api.application.domain.model.entities.WhatsappMessage;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;

public interface WhatsappMessageRepository extends JpaRepository<WhatsappMessage, String> {

  interface MonitorRow {
    String getTwilioSid();
    Instant getSentAt();
    String getPhone();
    String getTemplateType();
    String getStatus();
    String getErrorCode();
    String getPrescriptionId();
    String getPrescriptionCode();
    String getPatientName();
    String getMedicName();
  }

  @Query(value = """
      SELECT w.twilioSid AS twilioSid, w.sentAt AS sentAt, w.phone AS phone,
             w.templateType AS templateType, w.status AS status, w.errorCode AS errorCode,
             w.prescriptionId AS prescriptionId, p.code AS prescriptionCode,
             CONCAT(pa.name, ' ', pa.lastname) AS patientName,
             CONCAT(m.name, ' ', m.lastname) AS medicName
      FROM whatsapp_message w
      JOIN prescription p ON p.id = w.prescriptionId
      JOIN patient pa ON pa.id = p.patientId
      JOIN medic m ON m.id = p.medicId
      WHERE w.sentAt >= :from AND w.sentAt < :to
        AND (:status IS NULL OR w.status = :status)
        AND (:search IS NULL OR :search = ''
             OR LOWER(CONCAT(pa.name, ' ', pa.lastname)) LIKE LOWER(CONCAT('%', :search, '%'))
             OR w.phone LIKE CONCAT('%', :search, '%')
             OR LOWER(p.code) LIKE LOWER(CONCAT('%', :search, '%')))
      ORDER BY w.sentAt DESC
      """,
      countQuery = """
      SELECT COUNT(*)
      FROM whatsapp_message w
      JOIN prescription p ON p.id = w.prescriptionId
      JOIN patient pa ON pa.id = p.patientId
      JOIN medic m ON m.id = p.medicId
      WHERE w.sentAt >= :from AND w.sentAt < :to
        AND (:status IS NULL OR w.status = :status)
        AND (:search IS NULL OR :search = ''
             OR LOWER(CONCAT(pa.name, ' ', pa.lastname)) LIKE LOWER(CONCAT('%', :search, '%'))
             OR w.phone LIKE CONCAT('%', :search, '%')
             OR LOWER(p.code) LIKE LOWER(CONCAT('%', :search, '%')))
      """,
      nativeQuery = true)
  Page<MonitorRow> findMonitorRows(@Param("from") Instant from, @Param("to") Instant to,
                                   @Param("status") String status, @Param("search") String search,
                                   Pageable pageable);

  @Query(value = """
      SELECT COUNT(DISTINCT CASE WHEN w.sentAt >= :todayStart THEN w.twilioSid END) AS sentToday,
             COUNT(DISTINCT CASE WHEN w.sentAt >= :weekStart THEN w.twilioSid END) AS sentWeek,
             COUNT(DISTINCT CASE WHEN w.status IN ('delivered','read') THEN w.twilioSid END) AS delivered,
             COUNT(DISTINCT CASE WHEN w.status IN ('failed','undelivered') THEN w.twilioSid END) AS failed,
             COUNT(DISTINCT w.twilioSid) AS total
      FROM whatsapp_message w
      WHERE w.sentAt >= :weekStart
      """, nativeQuery = true)
  SummaryRow summary(@Param("todayStart") Instant todayStart, @Param("weekStart") Instant weekStart);

  interface SummaryRow {
    Long getSentToday();
    Long getSentWeek();
    Long getDelivered();
    Long getFailed();
    Long getTotal();
  }

  @Modifying
  @Query("UPDATE WhatsappMessage w SET w.status = :status, w.errorCode = :errorCode, w.statusUpdatedAt = :now WHERE w.twilioSid = :sid")
  int updateStatusBySid(@Param("sid") String sid, @Param("status") String status,
                        @Param("errorCode") String errorCode, @Param("now") Instant now);

  List<WhatsappMessage> findByTwilioSidIn(List<String> sids);
}
```

- [ ] **Step 4.3: Compilar + commit**

Run: `cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest && ./gradlew compileJava 2>&1 | tail -3` → `BUILD SUCCESSFUL`.

```bash
git add -A && git commit -m "feat(control-dashboard): entity y repository de whatsapp_message"
```

---

### Task 5: api-rest — service + consumer al transversal + controller

**Files:**
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/dto/response/WhatsappMonitorResponse.java` (+ DTOs anidados en el mismo archivo)
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/infrastructure/adapter/transversal/services/WhatsappRestConsumer.java`
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/infrastructure/adapter/transversal/services/impl/WhatsappRestConsumerImp.java`
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/ControlWhatsappService.java`
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/service/impl/ControlWhatsappServiceImpl.java`
- Create: `recetalia-api-rest/src/main/java/com/recetalia/api/application/controller/ControlDashboardController.java`
- Test: `recetalia-api-rest/src/test/java/com/recetalia/api/application/service/impl/ControlWhatsappServiceImplTest.java`

- [ ] **Step 5.1: DTOs de respuesta**

```java
// dto/response/WhatsappMonitorResponse.java
package com.recetalia.api.application.dto.response;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.List;

@Data @Builder @NoArgsConstructor @AllArgsConstructor
public class WhatsappMonitorResponse {
  private List<MessageRow> rows;
  private long totalElements;
  private int totalPages;

  @Data @Builder @NoArgsConstructor @AllArgsConstructor
  public static class MessageRow {
    private String twilioSid;
    private Instant sentAt;
    private String phone;
    private String templateType;
    private String status;
    private String errorCode;
    private String patientName;
    private String medicName;
    private List<PrescriptionRef> prescriptions; // 1..N recetas del mismo mensaje

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class PrescriptionRef {
      private String id;
      private String code;
    }
  }

  @Data @Builder @NoArgsConstructor @AllArgsConstructor
  public static class Summary {
    private long sentToday;
    private long sentWeek;
    private long delivered;
    private long failed;
    private long total;         // mensajes distintos (por SID) de la semana
    private double deliveredPct; // delivered/total*100, 0 si total=0
  }
}
```

- [ ] **Step 5.2: Consumer REST al transversal (patrón `DnmaRestConsumerPortImp`)**

```java
// services/WhatsappRestConsumer.java
package com.recetalia.api.application.infrastructure.adapter.transversal.services;

import java.util.List;
import java.util.Map;

public interface WhatsappRestConsumer {
  /** GET {transversal}/whatsapp/status?sids=a,b → [{sid,status,errorCode,...}] */
  List<Map<String, String>> getStatuses(List<String> sids);

  /** GET {transversal}/whatsapp/historic?from&to&limit → mensajes Twilio crudos */
  List<Map<String, String>> getHistoric(String fromIso, String toIso, int limit);
}
```

```java
// services/impl/WhatsappRestConsumerImp.java
package com.recetalia.api.application.infrastructure.adapter.transversal.services.impl;

import com.recetalia.api.application.infrastructure.adapter.transversal.services.WhatsappRestConsumer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.List;
import java.util.Map;

@Component
public class WhatsappRestConsumerImp implements WhatsappRestConsumer {

  private final RestTemplate restTemplate;

  @Value("${external.api.transversal-api-recetalia}")
  private String transversalApiBaseUrl;

  public WhatsappRestConsumerImp(RestTemplate restTemplate) {
    this.restTemplate = restTemplate;
  }

  @Override
  public List<Map<String, String>> getStatuses(List<String> sids) {
    String url = transversalApiBaseUrl + "/whatsapp/status?sids=" + String.join(",", sids);
    return exchangeList(url);
  }

  @Override
  public List<Map<String, String>> getHistoric(String fromIso, String toIso, int limit) {
    String url = transversalApiBaseUrl + "/whatsapp/historic?from=" + fromIso + "&to=" + toIso + "&limit=" + limit;
    return exchangeList(url);
  }

  private List<Map<String, String>> exchangeList(String url) {
    HttpHeaders headers = new HttpHeaders();
    headers.set("Accept", "application/json");
    return restTemplate.exchange(url, HttpMethod.GET, new HttpEntity<>(headers),
        new ParameterizedTypeReference<List<Map<String, String>>>() {}).getBody();
  }
}
```

(⚠️ si el `WhatsAppController` del transversal envuelve en `GenericResponse`, ajustar acá el tipo a esa envoltura — mantener simetría con lo hecho en Task 3 step 3.4.)

- [ ] **Step 5.3: Test del service (falla primero)**

```java
// ControlWhatsappServiceImplTest.java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.repository.WhatsappMessageRepository;
import com.recetalia.api.application.dto.response.WhatsappMonitorResponse;
import com.recetalia.api.application.infrastructure.adapter.transversal.services.WhatsappRestConsumer;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ControlWhatsappServiceImplTest {

  @Mock WhatsappMessageRepository repository;
  @Mock WhatsappRestConsumer whatsappRestConsumer;
  @InjectMocks ControlWhatsappServiceImpl service;

  private WhatsappMessageRepository.MonitorRow row(String sid, String presId, String code) {
    return new WhatsappMessageRepository.MonitorRow() {
      public String getTwilioSid() { return sid; }
      public Instant getSentAt() { return Instant.parse("2026-07-13T12:00:00Z"); }
      public String getPhone() { return "+59899111222"; }
      public String getTemplateType() { return "PENDING"; }
      public String getStatus() { return "sent"; }
      public String getErrorCode() { return null; }
      public String getPrescriptionId() { return presId; }
      public String getPrescriptionCode() { return code; }
      public String getPatientName() { return "Ana Test"; }
      public String getMedicName() { return "Dr House"; }
    };
  }

  @Test
  void list_groupsRowsBySid() {
    when(repository.findMonitorRows(any(), any(), any(), any(), any()))
        .thenReturn(new PageImpl<>(List.of(row("SM1", "p1", "AAA111"), row("SM1", "p2", "AAA112"))));

    WhatsappMonitorResponse res = service.list(Instant.EPOCH, Instant.now(), null, null, 0, 25);

    assertThat(res.getRows()).hasSize(1); // 2 filas, 1 mensaje
    assertThat(res.getRows().get(0).getPrescriptions()).hasSize(2);
    assertThat(res.getRows().get(0).getTwilioSid()).isEqualTo("SM1");
  }

  @Test
  void refreshStatus_updatesRowsWithTwilioData() {
    when(whatsappRestConsumer.getStatuses(List.of("SM1")))
        .thenReturn(List.of(Map.of("sid", "SM1", "status", "delivered")));
    when(repository.updateStatusBySid(eq("SM1"), eq("delivered"), isNull(), any())).thenReturn(1);

    var updated = service.refreshStatus(List.of("SM1"));

    assertThat(updated).containsEntry("SM1", "delivered");
    verify(repository).updateStatusBySid(eq("SM1"), eq("delivered"), isNull(), any());
  }
}
```

Run: `./gradlew test --tests '*ControlWhatsappServiceImplTest' 2>&1 | tail -5` → Expected: FAIL de compilación (service no existe).

- [ ] **Step 5.4: Service**

```java
// service/ControlWhatsappService.java
package com.recetalia.api.application.service;

import com.recetalia.api.application.dto.response.WhatsappMonitorResponse;

import java.time.Instant;
import java.util.List;
import java.util.Map;

public interface ControlWhatsappService {
  WhatsappMonitorResponse list(Instant from, Instant to, String status, String search, int page, int size);
  WhatsappMonitorResponse.Summary summary();
  Map<String, String> refreshStatus(List<String> sids);
  List<Map<String, String>> historic(String fromIso, String toIso, int limit);
}
```

```java
// service/impl/ControlWhatsappServiceImpl.java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.repository.WhatsappMessageRepository;
import com.recetalia.api.application.dto.response.WhatsappMonitorResponse;
import com.recetalia.api.application.infrastructure.adapter.transversal.services.WhatsappRestConsumer;
import com.recetalia.api.application.service.ControlWhatsappService;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class ControlWhatsappServiceImpl implements ControlWhatsappService {

  private static final ZoneId UY = ZoneId.of("America/Montevideo");

  private final WhatsappMessageRepository repository;
  private final WhatsappRestConsumer whatsappRestConsumer;

  public ControlWhatsappServiceImpl(WhatsappMessageRepository repository,
                                    WhatsappRestConsumer whatsappRestConsumer) {
    this.repository = repository;
    this.whatsappRestConsumer = whatsappRestConsumer;
  }

  @Override
  public WhatsappMonitorResponse list(Instant from, Instant to, String status, String search,
                                      int page, int size) {
    Page<WhatsappMessageRepository.MonitorRow> rows =
        repository.findMonitorRows(from, to, emptyToNull(status), emptyToNull(search),
            PageRequest.of(page, size));

    // Agrupa filas (una por prescription) en mensajes (una por SID), preservando orden
    Map<String, WhatsappMonitorResponse.MessageRow> bySid = new LinkedHashMap<>();
    for (var r : rows.getContent()) {
      bySid.computeIfAbsent(r.getTwilioSid(), sid -> WhatsappMonitorResponse.MessageRow.builder()
              .twilioSid(sid).sentAt(r.getSentAt()).phone(r.getPhone())
              .templateType(r.getTemplateType()).status(r.getStatus()).errorCode(r.getErrorCode())
              .patientName(r.getPatientName()).medicName(r.getMedicName())
              .prescriptions(new ArrayList<>()).build())
          .getPrescriptions()
          .add(new WhatsappMonitorResponse.MessageRow.PrescriptionRef(
              r.getPrescriptionId(), r.getPrescriptionCode()));
    }
    return WhatsappMonitorResponse.builder()
        .rows(new ArrayList<>(bySid.values()))
        .totalElements(rows.getTotalElements())
        .totalPages(rows.getTotalPages())
        .build();
  }

  @Override
  public WhatsappMonitorResponse.Summary summary() {
    Instant todayStart = LocalDate.now(UY).atStartOfDay(UY).toInstant();
    Instant weekStart = todayStart.minus(6, ChronoUnit.DAYS);
    var s = repository.summary(todayStart, weekStart);
    long total = s.getTotal() == null ? 0 : s.getTotal();
    long delivered = s.getDelivered() == null ? 0 : s.getDelivered();
    return WhatsappMonitorResponse.Summary.builder()
        .sentToday(nz(s.getSentToday())).sentWeek(nz(s.getSentWeek()))
        .delivered(delivered).failed(nz(s.getFailed())).total(total)
        .deliveredPct(total == 0 ? 0 : Math.round(delivered * 1000.0 / total) / 10.0)
        .build();
  }

  @Override
  @Transactional
  public Map<String, String> refreshStatus(List<String> sids) {
    Map<String, String> result = new LinkedHashMap<>();
    if (sids == null || sids.isEmpty()) return result;
    List<Map<String, String>> statuses = whatsappRestConsumer.getStatuses(sids);
    Instant now = Instant.now();
    for (Map<String, String> st : statuses) {
      String sid = st.get("sid");
      String status = st.get("status");
      if (sid == null || status == null || "unknown".equals(status)) continue;
      repository.updateStatusBySid(sid, status, st.get("errorCode"), now);
      result.put(sid, status);
    }
    return result;
  }

  @Override
  public List<Map<String, String>> historic(String fromIso, String toIso, int limit) {
    return whatsappRestConsumer.getHistoric(fromIso, toIso, limit);
  }

  private static String emptyToNull(String s) { return (s == null || s.isBlank()) ? null : s; }
  private static long nz(Long l) { return l == null ? 0 : l; }
}
```

- [ ] **Step 5.5: Tests verdes**

Run: `./gradlew test --tests '*ControlWhatsappServiceImplTest' 2>&1 | tail -5` → Expected: PASS.

- [ ] **Step 5.6: Controller (mismo estilo que DashboardController)**

```java
// controller/ControlDashboardController.java
package com.recetalia.api.application.controller;

import com.recetalia.api.application.dto.response.WhatsappMonitorResponse;
import com.recetalia.api.application.service.ControlWhatsappService;
// GenericResponse/ResponseStatus: mismos imports que usa DashboardController
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/control-dashboard/whatsapp")
public class ControlDashboardController {

  private static final ZoneId UY = ZoneId.of("America/Montevideo");
  private final ControlWhatsappService service;

  public ControlDashboardController(ControlWhatsappService service) {
    this.service = service;
  }

  @GetMapping
  public ResponseEntity<GenericResponse<WhatsappMonitorResponse>> list(
      @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
      @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate,
      @RequestParam(required = false) String status,
      @RequestParam(required = false) String search,
      @RequestParam(defaultValue = "0") int page,
      @RequestParam(defaultValue = "25") int size) {
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS,
        service.list(startDate.atStartOfDay(UY).toInstant(),
            endDate.plusDays(1).atStartOfDay(UY).toInstant(), status, search, page, size)));
  }

  @GetMapping("/summary")
  public ResponseEntity<GenericResponse<WhatsappMonitorResponse.Summary>> summary() {
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, service.summary()));
  }

  @PostMapping("/refresh-status")
  public ResponseEntity<GenericResponse<Map<String, String>>> refreshStatus(@RequestBody List<String> sids) {
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, service.refreshStatus(sids)));
  }

  @GetMapping("/historic")
  public ResponseEntity<GenericResponse<List<Map<String, String>>>> historic(
      @RequestParam String from, @RequestParam String to,
      @RequestParam(defaultValue = "200") int limit) {
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, service.historic(from, to, limit)));
  }
}
```

- [ ] **Step 5.7: Restringir a ROLE_MANAGEMENT — verificar primero el string real del authority**

⚠️ Hay antecedente de doble prefijo `ROLE_ROLE_` en este stack. Verificar el claim real ANTES de elegir el matcher:

```bash
TOKEN=$(curl -s -X POST "https://apipre.recetalia.com/security-api-recetalia/api/auth/loginBack" \
  -H "Content-Type: application/json" \
  -d '{"email":"gestion@recetalia.com","password":"1wtg_p4ss","info":"000"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool
```

Expected: el payload muestra el rol (ej. `"role": "ROLE_MANAGEMENT"`). Luego mirar cómo `SecurityConfiguration` (o el `JwtAuthenticationConverter`) transforma ese claim en authorities — buscar con `grep -rn "hasAuthority\|hasRole\|ROLE_" src/main/java --include="*.java" | grep -i security | head`.

En `SecurityConfiguration`, agregar el matcher ANTES del catch-all autenticado, usando el string verificado:

```java
.requestMatchers("/api/control-dashboard/**").hasAuthority("<AUTHORITY_VERIFICADO>") // ej ROLE_MANAGEMENT
```

- [ ] **Step 5.8: Build + commit**

Run: `./gradlew build 2>&1 | tail -3` → `BUILD SUCCESSFUL`.

```bash
git add -A && git commit -m "feat(control-dashboard): endpoints /api/control-dashboard/whatsapp (ROLE_MANAGEMENT)"
```

---

### Task 6: Validación backend en dev (integración real)

**Files:** ninguno (deploy dev + curl).

- [ ] **Step 6.1: Sembrar 2 mensajes de prueba en la DB dev** (vinculados a recetas reales de la copia)

```bash
ssh recetalia-preprod 'docker exec -i recetalia-mysql mysql -urecetalia_dev -pRecDev98_x7Kq2mVt recetali_receta' <<'SQL'
INSERT INTO whatsapp_message (id, twilioSid, prescriptionId, phone, templateType, status, sentAt)
SELECT UUID(), 'SMseed000000000000000000000000001', p.id, '+59899000001', 'PENDING', 'sent', NOW()
FROM prescription p ORDER BY p.createdAt DESC LIMIT 1;
INSERT INTO whatsapp_message (id, twilioSid, prescriptionId, phone, templateType, status, sentAt)
SELECT UUID(), 'SMseed000000000000000000000000002', p.id, '+59899000002', 'REMINDER', 'failed', NOW() - INTERVAL 1 DAY
FROM prescription p ORDER BY p.createdAt ASC LIMIT 1;
SQL
```

- [ ] **Step 6.2: Build + deploy de las 2 APIs al ambiente dev**

```bash
# transversal y api-rest: rsync fuentes a LOCAL y build allá (tag :dev), igual que los frontends
for r in transversal-recetalia-api recetalia-api-rest; do
  rsync -az --delete --exclude .git --exclude build --exclude .gradle \
    /Users/pablo/iwtg/recetalia-workspace/$r/ recetalia-preprod:/opt/recetalia/$r/
done
ssh recetalia-preprod 'cd /opt/recetalia/deploy-recetalia && \
  COMPOSE_PROFILES=registry docker compose build recetalia-api-rest transversal-recetalia-api && \
  COMPOSE_PROFILES=registry docker compose up -d recetalia-api-rest transversal-recetalia-api'
```

Expected: contenedores recreados `Up` (verificar `docker ps`).

- [ ] **Step 6.3: Probar el listado y el summary con token de gestión**

```bash
TOKEN=$(curl -s -X POST "https://apipre.recetalia.com/security-api-recetalia/api/auth/loginBack" \
  -H "Content-Type: application/json" \
  -d '{"email":"gestion@recetalia.com","password":"1wtg_p4ss","info":"000"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -s "https://apipre.recetalia.com/recetalia-api-rest/api/control-dashboard/whatsapp?startDate=2026-07-01&endDate=2026-07-31" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | head -40
curl -s "https://apipre.recetalia.com/recetalia-api-rest/api/control-dashboard/whatsapp/summary" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

Expected: `SUCCESS` con los 2 seeds (paciente/médico/código reales de la copia) y summary con `sentToday=1, failed=1`.

- [ ] **Step 6.4: Probar que un rol NO management recibe 403**

```bash
TOKEN2=$(curl -s -X POST "https://apipre.recetalia.com/security-api-recetalia/api/auth/loginBack" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"Recetalia2026!","info":"000"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -s -o /dev/null -w "%{http_code}\n" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/control-dashboard/whatsapp/summary" \
  -H "Authorization: Bearer $TOKEN2"
```

Expected: `403`.

- [ ] **Step 6.5: refresh-status y historic (Twilio real, read-only)**

En dev el transversal tiene `TWILIO_AUTH_TOKEN=dev-invalid` → `fetchStatuses` degrada a `unknown` y el service NO pisa el status. Probar la degradación:

```bash
curl -s -X POST "https://apipre.recetalia.com/recetalia-api-rest/api/control-dashboard/whatsapp/refresh-status" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '["SMseed000000000000000000000000001"]' | python3 -m json.tool
```

Expected: `SUCCESS` con `answer: {}` (vacío — sin credenciales no actualiza nada, no rompe). La prueba con Twilio real queda para la validación en prod (Task final), o antes si Pablo autoriza setear temporalmente las credenciales reales SOLO de lectura en el transversal dev.

- [ ] **Step 6.6: Commit de cierre de fase backend** (si hubo fixes durante la validación).

---

### Task 7: gestion — service Angular + modelos

**Files:**
- Create: `gestion-recetadigital-app/src/app/model/response/whatsapp-monitor-response.ts`
- Create: `gestion-recetadigital-app/src/app/services/control-dashboard.service.ts`
- Test: `gestion-recetadigital-app/src/app/services/control-dashboard.service.spec.ts`

- [ ] **Step 7.1: Modelos**

```typescript
// model/response/whatsapp-monitor-response.ts
export interface PrescriptionRef {
  id: string;
  code: string;
}

export interface WhatsappMessageRow {
  twilioSid: string;
  sentAt: string;
  phone: string;
  templateType: 'PENDING' | 'REMINDER';
  status: string;
  errorCode?: string;
  patientName: string;
  medicName: string;
  prescriptions: PrescriptionRef[];
}

export interface WhatsappMonitorResponse {
  rows: WhatsappMessageRow[];
  totalElements: number;
  totalPages: number;
}

export interface WhatsappSummary {
  sentToday: number;
  sentWeek: number;
  delivered: number;
  failed: number;
  total: number;
  deliveredPct: number;
}
```

- [ ] **Step 7.2: Test del service (falla primero)**

```typescript
// services/control-dashboard.service.spec.ts
import { TestBed } from '@angular/core/testing';
import { HttpClientTestingModule, HttpTestingController } from '@angular/common/http/testing';
import { ControlDashboardService } from './control-dashboard.service';
import { environment } from '../../environments/environment';

describe('ControlDashboardService', () => {
  let service: ControlDashboardService;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({ imports: [HttpClientTestingModule] });
    service = TestBed.inject(ControlDashboardService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it('unwraps SUCCESS answer for whatsapp list', () => {
    const answer = { rows: [], totalElements: 0, totalPages: 0 };
    service.getWhatsappMessages('2026-07-01', '2026-07-31', 0, 25).subscribe(r => {
      expect(r.totalElements).toBe(0);
    });
    const req = http.expectOne(r => r.url === `${environment.apiUrl}/control-dashboard/whatsapp`);
    expect(req.request.params.get('startDate')).toBe('2026-07-01');
    req.flush({ status: 'SUCCESS', answer });
  });

  it('throws on ERROR response', () => {
    service.getWhatsappSummary().subscribe({ error: e => expect(e).toBeTruthy() });
    const req = http.expectOne(`${environment.apiUrl}/control-dashboard/whatsapp/summary`);
    req.flush({ status: 'ERROR', answer: 'boom' });
  });
});
```

Run: `cd /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app && npm test -- --watch=false --browsers=ChromeHeadless 2>&1 | tail -10`
Expected: FAIL (service no existe).

- [ ] **Step 7.3: Service (patrón DashboardService existente)**

```typescript
// services/control-dashboard.service.ts
import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { catchError, map } from 'rxjs/operators';
import { environment } from '../../environments/environment';
import { ApiResponse } from '../model/response/api-response';
import {
  WhatsappMonitorResponse, WhatsappSummary,
} from '../model/response/whatsapp-monitor-response';

@Injectable({ providedIn: 'root' })
export class ControlDashboardService {
  private apiUrl = `${environment.apiUrl}/control-dashboard`;

  constructor(private http: HttpClient) {}

  getWhatsappMessages(startDate: string, endDate: string, page: number, size: number,
                      status?: string, search?: string): Observable<WhatsappMonitorResponse> {
    let params = new HttpParams()
      .set('startDate', startDate).set('endDate', endDate)
      .set('page', page).set('size', size);
    if (status) params = params.set('status', status);
    if (search) params = params.set('search', search);
    return this.http
      .get<ApiResponse<WhatsappMonitorResponse>>(`${this.apiUrl}/whatsapp`, { params })
      .pipe(map(this.unwrap), catchError(this.fail('whatsapp list')));
  }

  getWhatsappSummary(): Observable<WhatsappSummary> {
    return this.http
      .get<ApiResponse<WhatsappSummary>>(`${this.apiUrl}/whatsapp/summary`)
      .pipe(map(this.unwrap), catchError(this.fail('whatsapp summary')));
  }

  refreshWhatsappStatus(sids: string[]): Observable<Record<string, string>> {
    return this.http
      .post<ApiResponse<Record<string, string>>>(`${this.apiUrl}/whatsapp/refresh-status`, sids)
      .pipe(map(this.unwrap), catchError(this.fail('refresh status')));
  }

  getWhatsappHistoric(from: string, to: string, limit = 200): Observable<Record<string, string>[]> {
    const params = new HttpParams().set('from', from).set('to', to).set('limit', limit);
    return this.http
      .get<ApiResponse<Record<string, string>[]>>(`${this.apiUrl}/whatsapp/historic`, { params })
      .pipe(map(this.unwrap), catchError(this.fail('historic')));
  }

  private unwrap = <T>(response: ApiResponse<T>): T => {
    if (response.status === 'SUCCESS') return response.answer;
    throw new Error('Error response from the API');
  };

  private fail(what: string) {
    return (error: unknown) => {
      console.error(`ControlDashboard ${what} failed:`, error);
      return throwError(() => new Error(`Failed to fetch ${what}`));
    };
  }
}
```

- [ ] **Step 7.4: Verde + commit**

Run: `npm test -- --watch=false --browsers=ChromeHeadless 2>&1 | tail -5` → Expected: los 2 specs nuevos PASS (si la suite preexistente tiene fallas ajenas, correr solo este spec con `--include='**/control-dashboard.service.spec.ts'`).

```bash
git add -A && git commit -m "feat(control): service y modelos del monitor WhatsApp"
```

---

### Task 8: gestion — componente, ruta y sidebar

**Files:**
- Create: `gestion-recetadigital-app/src/app/pages/application/home/control/whatsapp-monitor/whatsapp-monitor.component.ts|.html|.scss`
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/home.module.ts` (declarar componente)
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/home-routing.module.ts` (ruta `control/whatsapp`)
- Modify: `gestion-recetadigital-app/src/app/pages/application/home/components/sidebar/sidebar.component.ts|.html` (sección Control)

- [ ] **Step 8.1: Componente TS**

```typescript
// control/whatsapp-monitor/whatsapp-monitor.component.ts
import { Component, OnInit } from '@angular/core';
import { ControlDashboardService } from '../../../../../services/control-dashboard.service';
import {
  WhatsappMessageRow, WhatsappSummary,
} from '../../../../../model/response/whatsapp-monitor-response';

@Component({
  selector: 'app-whatsapp-monitor',
  standalone: false,
  templateUrl: './whatsapp-monitor.component.html',
  styleUrls: ['./whatsapp-monitor.component.scss'],
})
export class WhatsappMonitorComponent implements OnInit {
  summary?: WhatsappSummary;
  rows: WhatsappMessageRow[] = [];
  totalElements = 0;
  loading = false;
  error = false;

  // filtros
  startDate!: Date;
  endDate!: Date;
  status: string | null = null;
  search = '';
  page = 0;
  size = 25;

  statusOptions = [
    { label: 'Todos', value: null },
    { label: 'En cola', value: 'queued' },
    { label: 'Enviado', value: 'sent' },
    { label: 'Entregado', value: 'delivered' },
    { label: 'Leído', value: 'read' },
    { label: 'Fallido', value: 'failed' },
    { label: 'No entregado', value: 'undelivered' },
  ];

  constructor(private service: ControlDashboardService) {}

  ngOnInit(): void {
    this.endDate = new Date();
    this.startDate = new Date();
    this.startDate.setDate(this.endDate.getDate() - 30);
    this.loadSummary();
    this.load();
  }

  load(): void {
    this.loading = true;
    this.error = false;
    this.service
      .getWhatsappMessages(this.iso(this.startDate), this.iso(this.endDate),
        this.page, this.size, this.status ?? undefined, this.search || undefined)
      .subscribe({
        next: res => {
          this.rows = res.rows;
          this.totalElements = res.totalElements;
          this.loading = false;
        },
        error: () => { this.error = true; this.loading = false; },
      });
  }

  loadSummary(): void {
    this.service.getWhatsappSummary().subscribe({
      next: s => (this.summary = s),
      error: () => (this.summary = undefined),
    });
  }

  refreshStatus(): void {
    const sids = this.rows.map(r => r.twilioSid);
    if (!sids.length) return;
    this.loading = true;
    this.service.refreshWhatsappStatus(sids).subscribe({
      next: updated => {
        this.rows = this.rows.map(r =>
          updated[r.twilioSid] ? { ...r, status: updated[r.twilioSid] } : r);
        this.loading = false;
        this.loadSummary();
      },
      error: () => (this.loading = false),
    });
  }

  onPage(event: { first: number; rows: number }): void {
    this.page = event.first / event.rows;
    this.size = event.rows;
    this.load();
  }

  applyFilters(): void {
    this.page = 0;
    this.load();
  }

  statusClass(status: string): string {
    if (status === 'delivered' || status === 'read') return 'chip chip-ok';
    if (status === 'failed' || status === 'undelivered') return 'chip chip-fail';
    return 'chip chip-pending';
  }

  private iso(d: Date): string {
    return d.toISOString().slice(0, 10);
  }
}
```

- [ ] **Step 8.2: Template**

```html
<!-- control/whatsapp-monitor/whatsapp-monitor.component.html -->
<div class="control-whatsapp">
  <h2>Control — WhatsApp enviados</h2>

  <div class="cards" *ngIf="summary">
    <div class="card"><span class="value">{{ summary.sentToday }}</span><span class="label">Enviados hoy</span></div>
    <div class="card"><span class="value">{{ summary.sentWeek }}</span><span class="label">Últimos 7 días</span></div>
    <div class="card"><span class="value">{{ summary.deliveredPct }}%</span><span class="label">Entregados</span></div>
    <div class="card" [class.card-alert]="summary.failed > 0">
      <span class="value">{{ summary.failed }}</span><span class="label">Fallidos (7 días)</span>
    </div>
  </div>

  <div class="filters">
    <p-calendar [(ngModel)]="startDate" dateFormat="dd/mm/yy" placeholder="Desde"></p-calendar>
    <p-calendar [(ngModel)]="endDate" dateFormat="dd/mm/yy" placeholder="Hasta"></p-calendar>
    <p-dropdown [options]="statusOptions" [(ngModel)]="status" optionLabel="label" optionValue="value"
                placeholder="Status"></p-dropdown>
    <input pInputText [(ngModel)]="search" placeholder="Paciente, teléfono o código"
           (keyup.enter)="applyFilters()" />
    <button pButton label="Filtrar" (click)="applyFilters()"></button>
    <button pButton label="Refrescar status" class="p-button-secondary" icon="pi pi-refresh"
            (click)="refreshStatus()" [disabled]="loading || !rows.length"></button>
  </div>

  <p class="error" *ngIf="error">No se pudieron cargar los mensajes. Reintentá.</p>

  <p-table [value]="rows" [lazy]="true" [paginator]="true" [rows]="size"
           [totalRecords]="totalElements" [loading]="loading" (onLazyLoad)="onPage($event)">
    <ng-template pTemplate="header">
      <tr>
        <th>Fecha</th><th>Paciente</th><th>Teléfono</th><th>Tipo</th>
        <th>Recetas</th><th>Médico</th><th>Status</th><th>Error</th>
      </tr>
    </ng-template>
    <ng-template pTemplate="body" let-row>
      <tr>
        <td>{{ row.sentAt | date: 'dd/MM/yy HH:mm' }}</td>
        <td>{{ row.patientName }}</td>
        <td>{{ row.phone }}</td>
        <td>{{ row.templateType === 'PENDING' ? 'Notificación' : 'Recordatorio' }}</td>
        <td>
          <a *ngFor="let p of row.prescriptions; let last = last"
             [routerLink]="['/prescriptions', p.id]">{{ p.code }}<span *ngIf="!last">, </span></a>
        </td>
        <td>{{ row.medicName }}</td>
        <td><span [class]="statusClass(row.status)">{{ row.status }}</span></td>
        <td>{{ row.errorCode || '—' }}</td>
      </tr>
    </ng-template>
    <ng-template pTemplate="emptymessage">
      <tr><td colspan="8">Sin mensajes en el período.</td></tr>
    </ng-template>
  </p-table>
</div>
```

(⚠️ verificar la ruta real del detalle de receta en el routing de gestión — `grep -n "prescriptions" src/app/pages/application/home/home-routing.module.ts` — y ajustar el `routerLink`.)

- [ ] **Step 8.3: SCSS mínimo**

```scss
// control/whatsapp-monitor/whatsapp-monitor.component.scss
.cards { display: flex; gap: 1rem; margin-bottom: 1rem;
  .card { flex: 1; padding: 1rem; border-radius: 8px; background: #f6f8fa; text-align: center;
    .value { display: block; font-size: 1.8rem; font-weight: 700; }
    .label { color: #667; font-size: .85rem; }
    &.card-alert { background: #fdecea; .value { color: #c0392b; } }
  }
}
.filters { display: flex; gap: .5rem; flex-wrap: wrap; margin-bottom: 1rem; align-items: center; }
.chip { padding: 2px 10px; border-radius: 12px; font-size: .8rem;
  &.chip-ok { background: #e6f7e9; color: #1e7e34; }
  &.chip-fail { background: #fdecea; color: #c0392b; }
  &.chip-pending { background: #fff8e1; color: #8a6d3b; }
}
.error { color: #c0392b; }
```

- [ ] **Step 8.4: Declarar, rutear y agregar al sidebar**

1. `home.module.ts`: agregar `WhatsappMonitorComponent` a `declarations` (imports de PrimeNG `DropdownModule`, `InputTextModule`, `ButtonModule` si no están; `FormsModule` para ngModel).
2. `home-routing.module.ts`: ruta hija (mismo guard/roles que `dashboard` — copiar su `data`):

```typescript
{ path: 'control/whatsapp', component: WhatsappMonitorComponent,
  canActivate: [authGuard], data: { roles: ['ROLE_MANAGEMENT'] } },
```

(⚠️ copiar el valor de `roles` EXACTO de la ruta `dashboard` existente.)

3. `sidebar.component.ts` + `.html`: sección "Control" siguiendo el patrón de secciones existente:

```typescript
controlSectionManualOpen = false;
controlSectionRouteActive = false;
get controlSectionOpen(): boolean {
  return this.controlSectionManualOpen || this.controlSectionRouteActive;
}
toggleControlSection() { this.controlSectionManualOpen = !this.controlSectionManualOpen; }
```

```html
<div class="menu-section">
  <button (click)="toggleControlSection()"><i class="pi pi-shield"></i> Control</button>
  <div *ngIf="controlSectionOpen" class="submenu">
    <a routerLink="/control/whatsapp" routerLinkActive="active">WhatsApp</a>
  </div>
</div>
```

(⚠️ replicar clases CSS/estructura EXACTA de una sección existente del sidebar — mirar el HTML real, el snippet es orientativo.)

- [ ] **Step 8.5: Toggle "ver históricos" (mensajes Twilio previos a la feature, sin vínculo)**

En el componente TS agregar:

```typescript
historicMode = false;
historicRows: Record<string, string>[] = [];

toggleHistoric(): void {
  this.historicMode = !this.historicMode;
  if (this.historicMode) {
    this.loading = true;
    this.service.getWhatsappHistoric(this.iso(this.startDate), this.iso(this.endDate)).subscribe({
      next: rows => { this.historicRows = rows; this.loading = false; },
      error: () => { this.historicRows = []; this.loading = false; this.error = true; },
    });
  }
}
```

En el template, botón junto a los filtros:

```html
<button pButton [label]="historicMode ? 'Ver actuales' : 'Ver históricos (sin receta)'"
        class="p-button-text" (click)="toggleHistoric()"></button>
```

y una tabla alternativa cuando `historicMode` (envolver la p-table actual en `<ng-container *ngIf="!historicMode">`):

```html
<p-table *ngIf="historicMode" [value]="historicRows" [paginator]="true" [rows]="25" [loading]="loading">
  <ng-template pTemplate="header">
    <tr><th>Fecha</th><th>Destinatario</th><th>Status</th><th>Error</th><th>SID</th></tr>
  </ng-template>
  <ng-template pTemplate="body" let-row>
    <tr>
      <td>{{ row['dateSent'] }}</td>
      <td>{{ row['to'] }}</td>
      <td><span [class]="statusClass(row['status'])">{{ row['status'] }}</span></td>
      <td>{{ row['errorCode'] || '—' }}</td>
      <td class="sid">{{ row['sid'] }}</td>
    </tr>
  </ng-template>
  <ng-template pTemplate="emptymessage">
    <tr><td colspan="5">Sin mensajes históricos en el período (en dev Twilio está deshabilitado: se prueba en prod).</td></tr>
  </ng-template>
</p-table>
```

- [ ] **Step 8.6: Build + commit**

Run: `npm run build 2>&1 | tail -5` → Expected: build OK sin errores de template (los warnings de budget preexistentes no cuentan).

```bash
git add -A && git commit -m "feat(control): tab WhatsApp del dashboard de control"
```

---

### Task 9: E2E en dev + cierre

**Files:** ninguno.

- [ ] **Step 9.1: Deploy de gestión dev**

```bash
rsync -az --delete --exclude node_modules --exclude dist --exclude .git --exclude .angular \
  /Users/pablo/iwtg/recetalia-workspace/gestion-recetadigital-app/ recetalia-preprod:/opt/recetalia/gestion-recetadigital-app/
ssh recetalia-preprod 'cd /opt/recetalia/deploy-recetalia && \
  COMPOSE_PROFILES=registry docker compose build gestion-recetadigital-app && \
  COMPOSE_PROFILES=registry docker compose up -d gestion-recetadigital-app'
```

- [ ] **Step 9.2: Validación por browser** en `https://gestionpre.recetalia.com` con `gestion@recetalia.com`:
  - Sidebar muestra "Control" → "WhatsApp".
  - Cards con `1 enviado hoy / 1 fallido` (los seeds) y tabla con 2 filas, códigos de receta clickeables al detalle.
  - Filtro por status `failed` → 1 fila. Búsqueda por teléfono seed → 1 fila.
  - "Refrescar status" no rompe (en dev degrada sin credenciales).
  - Login con usuario de farmacias → la ruta `/control/whatsapp` redirige a login y la API devuelve 403.

- [ ] **Step 9.3: Pushear los 3 branches (SIN merge)**

```bash
for r in transversal-recetalia-api recetalia-api-rest gestion-recetadigital-app; do
  cd /Users/pablo/iwtg/recetalia-workspace/$r && git push -u origin feat/control-dashboard
done
```

- [ ] **Step 9.4: Reporte a Pablo** — checklist de validación + pendientes para prod: DDL en la DB productiva, deploy de 3 imágenes, y primer WhatsApp real verificado con receta vinculada. **El merge y el deploy a prod requieren su OK explícito.**

---

## Notas para el ejecutor

- **Nunca** commitear en `2.x.y` ni pushear imágenes con tag `latest` desde dev (el ambiente dev usa `IMAGE_TAG=dev`).
- El transversal en dev tiene schedulers OFF y Twilio inválido a propósito — NO "arreglarlo": es la protección para que la copia de datos reales no notifique a pacientes.
- Credenciales dev: MySQL `recetalia_dev`/`RecDev98_x7Kq2mVt` (LOCAL :3307), gestión `gestion@recetalia.com`/`1wtg_p4ss`.
- Si un paso revela que un supuesto del plan no aplica (p.ej. paths del adapter, formato del authority), ajustar siguiendo el patrón real del repo y anotarlo en el commit.
