# QF — Registro propio y entidad del Químico Farmacéutico — Plan 1: Backend

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convertir al Químico Farmacéutico en una entidad de primera clase con el CJP como clave única, para que la farmacia lo dé de alta o lo seleccione si ya existe, y para que el propio QF complete su registro y defina su clave.

**Architecture:** Tabla nueva `pharmaceutical_director` en `recetali_receta`, vinculada desde `pharmacy` por FK. Los campos `pharmacy.manager*` se conservan como copia derivada para no romper el Excel ni las consultas existentes. Se agregan además las tres columnas de receta en papel (`origin`, `paperNumber`, `paperIssuedAt`) para desbloquear el Plan 4. Se reemplaza `PharmacyServiceImpl.ensurePharmaceuticalDirectorUser(cjp)` por un `resolvePharmaceuticalDirector(request)` que crea o reusa el QF.

**Tech Stack:** Java 21, Spring Boot 3.3.0 (Web MVC), Spring Data JPA / Hibernate, MySQL, Lombok, MapStruct, JUnit 5 + Mockito + AssertJ, Gradle.

**Spec:** [2026-07-31-qf-registro-y-libro-negro-papel-design.md](2026-07-31-qf-registro-y-libro-negro-papel-design.md)

---

## Contexto imprescindible antes de empezar

**Rama base.** `recetalia-api-rest` está hoy en `feat/qf-control-recetas-verdes`, que **no está mergeada**. Todo el módulo QF vive ahí. Este plan se ramifica de esa rama, no de `2.x.y` ni de `main`:

```bash
cd recetalia-api-rest
git checkout feat/qf-control-recetas-verdes
git checkout -b feat/qf-registro-y-papel
```

**No hay Flyway en este proyecto.** `spring.jpa.hibernate.ddl-auto: none`. Hibernate no crea ni altera nada: todo cambio de schema se aplica a mano en cada ambiente. Si la columna no está en la DB, la query falla en runtime aunque el código compile.

**Los tests de este proyecto no levantan Spring ni una DB.** Son unitarios puros: se instancia el `*Impl` con `new`, se le inyectan mocks por *test seams* package-private (ver `PharmacyServiceQfUserTest`), y se verifica con Mockito + AssertJ. No escribas tests de repositorio: los repos se ejercitan a través de los tests de servicio con el repo mockeado.

**Quirk del doble prefijo.** El converter de JWT agrega `ROLE_` a un claim que ya lo trae, así que el matcher de seguridad del QF es `hasAuthority("ROLE_ROLE_PHARMACEUTICAL_DIRECTOR")`. No es un typo.

**Comandos:**

| Qué | Comando |
|---|---|
| Compilar | `./gradlew build` |
| Un test | `./gradlew test --tests "*PharmaceuticalDirectorRegistrationTest*"` |
| Todos | `./gradlew test` |

---

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `doc/migrations/2026-07-31-qf-entity.sql` | DDL + backfill idempotente. Se corre a mano por ambiente |
| `domain/model/entities/PharmaceuticalDirector.java` | Entidad JPA del QF |
| `domain/repository/PharmaceuticalDirectorRepository.java` | Acceso por CJP |
| `domain/model/entities/Pharmacy.java` | +relación `pharmaceuticalDirector` |
| `domain/model/entities/Prescription.java` | +`origin`, `paperNumber`, `paperIssuedAt` |
| `dto/request/PharmacyRequest.java` | +`managerPassword` |
| `dto/response/PharmaceuticalDirectorLookupResponse.java` | Respuesta pública del lookup: solo nombre y apellido |
| `dto/response/PharmaceuticalDirectorMeResponse.java` | Datos del QF + sus farmacias |
| `dto/request/PharmaceuticalDirectorRegisterRequest.java` | Payload del registro |
| `service/PharmaceuticalDirectorRegistrationService.java` + `impl/` | Resolve desde farmacia, `me`, `register` |
| `service/impl/PharmacyServiceImpl.java` | Usa el resolve en vez de `ensurePharmaceuticalDirectorUser` |
| `service/impl/PharmaceuticalDirectorServiceImpl.java` | `buildQfName` desde la entidad |
| `controller/PharmacyController.java` | +lookup público |
| `controller/PharmaceuticalDirectorController.java` | +`/me`, +`/register` |
| `infrastructure/config/SecurityConfiguration.java` | +`permitAll` del lookup |

El servicio de registro va **separado** de `PharmaceuticalDirectorServiceImpl` (que resuelve farmacias y firma dispensaciones) a propósito: son dos responsabilidades distintas y esa clase ya tiene cinco dependencias.

---

### Task 1: Migración SQL — tabla, FK, columnas de papel y backfill

**Files:**
- Create: `recetalia-api-rest/doc/migrations/2026-07-31-qf-entity.sql`

> **Esta task fue reabierta tras el code review.** La primera versión asumía que el CJP identifica
> unívocamente a un QF. Los datos reales lo desmienten: 20 CJPs están compartidos por personas con
> nombres distintos (65 de 337 farmacias), hay CJPs no numéricos (`fdsfsdf`, `asfsd`) y uno con
> espacio inicial que sin `TRIM` genera dos QFs para la misma persona. La versión de abajo normaliza
> con `TRIM` y marca los CJPs colisionados como `NEEDS_REVIEW` en vez de dejar que el `ROW_NUMBER`
> elija un nombre en silencio. También se le sacó `deletedAt` a la tabla (soft delete + `UNIQUE`
> hace que un CJP borrado no se pueda volver a registrar nunca) y se agregaron las protecciones de
> lock para poder correrla en producción.

- [ ] **Step 1: Escribir el script**

Archivo `doc/migrations/2026-07-31-qf-entity.sql` (reemplaza por completo la versión anterior):

```sql
-- 2026-07-31 — QF como entidad + columnas de receta en papel.
-- Este proyecto NO usa Flyway (ddl-auto: none): correr a mano en cada ambiente.
-- Idempotente: se puede correr dos veces sin duplicar ni fallar.
--
-- PRE-FLIGHT antes de correr en PROD:
--   SELECT VERSION();                         -- >= 8.0.12 (ADD COLUMN instant)
--   SELECT @@binlog_format;                   -- ROW (por el UUID() del backfill)
--   SELECT ROW_FORMAT FROM information_schema.INNODB_TABLES
--     WHERE NAME='recetali_receta/prescription';  -- != Compressed
--   -- y verificar que no haya transacciones largas abiertas sobre prescription.

USE recetali_receta;

-- Fallar rápido en vez de encolar tráfico detrás de un metadata lock: el default de MySQL
-- es un año, y un ALTER esperando bloquea toda query posterior sobre la misma tabla.
SET SESSION lock_wait_timeout = 5;

-- 1) Tabla del Químico Farmacéutico. El CJP es la clave.
--    SIN deletedAt a propósito: soft delete + UNIQUE(cjp) haría que un CJP dado de baja
--    no se pueda volver a registrar nunca. La baja se expresa con status = 'INACTIVE'.
CREATE TABLE IF NOT EXISTS pharmaceutical_director (
  id            VARCHAR(36)  NOT NULL,
  cjp           VARCHAR(150) NOT NULL,
  name          VARCHAR(150) NOT NULL,
  lastname      VARCHAR(150) NOT NULL,
  document      TEXT         NULL,
  email         VARCHAR(200) NULL,
  phone         TEXT         NULL,
  status        VARCHAR(255) NOT NULL DEFAULT 'ACTIVE',
  registeredAt  TIMESTAMP(6) NULL,
  createdAt     TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updatedAt     TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  UNIQUE KEY uk_pharmaceutical_director_cjp (cjp)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- 2) Vínculo desde la farmacia. Nullable: hay farmacias sin CJP cargado.
--    MySQL 8 no soporta ADD COLUMN IF NOT EXISTS → se chequea antes.
SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy'
               AND COLUMN_NAME = 'pharmaceuticalDirectorId');
SET @sql := IF(@col = 0,
  'ALTER TABLE pharmacy ADD COLUMN pharmaceuticalDirectorId VARCHAR(36) NULL',
  'SELECT "pharmacy.pharmaceuticalDirectorId ya existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Agregar una FK obliga a ALGORITHM=COPY con foreign_key_checks activo: reconstruye pharmacy.
-- Es chica y la columna está toda en NULL (no hay nada que validar), así que se desactiva
-- la verificación para que sea INPLACE y no bloquee escrituras.
SET @fk := (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy'
              AND CONSTRAINT_NAME = 'fk_pharmacy_pharmaceutical_director');
SET @sql := IF(@fk = 0,
  'ALTER TABLE pharmacy ADD CONSTRAINT fk_pharmacy_pharmaceutical_director
     FOREIGN KEY (pharmaceuticalDirectorId) REFERENCES pharmaceutical_director(id),
     ALGORITHM=INPLACE, LOCK=NONE',
  'SELECT "FK ya existe"');
SET SESSION foreign_key_checks = 0;
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
SET SESSION foreign_key_checks = 1;

-- 3) Columnas de receta en papel (las consume el Plan 4).
--    ALGORITHM=INSTANT explícito: si por lo que sea no puede ser instantáneo, que FALLE
--    en vez de degradarse en silencio a COPY y reconstruir la tabla más caliente del sistema.
SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'prescription'
               AND COLUMN_NAME = 'origin');
SET @sql := IF(@col = 0,
  'ALTER TABLE prescription
     ADD COLUMN origin        VARCHAR(10) NOT NULL DEFAULT ''DIGITAL'',
     ADD COLUMN paperNumber   VARCHAR(50) NULL,
     ADD COLUMN paperIssuedAt DATETIME    NULL,
     ALGORITHM=INSTANT',
  'SELECT "prescription.origin ya existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 4) Backfill: un QF por cada CJP normalizado (TRIM), con los datos de la farmacia
--    modificada más recientemente. registeredAt queda NULL → al entrar cae en el registro.
--
--    Los CJPs compartidos por personas con nombres distintos NO son identidades confiables
--    (en DEV: 20 CJPs, 65 farmacias; el CJP '1' tiene 7 farmacias y 6 personas). Se crean
--    igual para no dejar farmacias huérfanas, pero marcados NEEDS_REVIEW: la app no los deja
--    registrarse ni firmar hasta que alguien cure el dato.
--    Nota: MySQL 8 no admite COUNT(DISTINCT ...) como window function, de ahí el LEFT JOIN.
INSERT INTO pharmaceutical_director (id, cjp, name, lastname, document, status)
SELECT UUID(), t.cjp, t.managerName, t.managerLastname, t.managerDocument,
       IF(c.cjp IS NULL, 'ACTIVE', 'NEEDS_REVIEW')
FROM (
  SELECT TRIM(p.managerCJP) AS cjp, p.managerName, p.managerLastname, p.managerDocument,
         ROW_NUMBER() OVER (PARTITION BY TRIM(p.managerCJP) ORDER BY p.updatedAt DESC) AS rn
  FROM pharmacy p
  WHERE p.deletedAt IS NULL
    AND p.managerCJP IS NOT NULL AND TRIM(p.managerCJP) <> ''
) t
LEFT JOIN (
  SELECT TRIM(managerCJP) AS cjp
  FROM pharmacy
  WHERE deletedAt IS NULL AND managerCJP IS NOT NULL AND TRIM(managerCJP) <> ''
  GROUP BY TRIM(managerCJP)
  HAVING COUNT(DISTINCT CONCAT(TRIM(managerName), '|', TRIM(managerLastname))) > 1
) c ON c.cjp = t.cjp
WHERE t.rn = 1
  AND NOT EXISTS (SELECT 1 FROM pharmaceutical_director d WHERE d.cjp = t.cjp);

UPDATE pharmacy p
  JOIN pharmaceutical_director d ON d.cjp = TRIM(p.managerCJP)
SET p.pharmaceuticalDirectorId = d.id
WHERE p.pharmaceuticalDirectorId IS NULL
  AND p.deletedAt IS NULL;
```

- [ ] **Step 1b: Escribir el reset de DEV**

DEV ya tiene materializado el backfill viejo (221 QFs, uno duplicado por el `TRIM` faltante y ~20
agrupando personas distintas como si fueran una). El script es idempotente, y **por eso mismo no
va a corregir las filas que ya insertó**: hay que limpiarlas antes de volver a correrlo.

Archivo `doc/migrations/2026-07-31-qf-entity-RESET-dev-only.sql`:

```sql
-- ⛔ SOLO DEV. NO CORRER EN PRODUCCIÓN.
--
-- DEV corrió una versión anterior de la migración: tabla con `deletedAt`, `registeredAt`
-- sin precisión, y un backfill sin TRIM y sin NEEDS_REVIEW. Este script deshace eso por
-- completo para que la migración nueva la recree con el schema correcto.
-- No alcanza con un DELETE: el CREATE TABLE IF NOT EXISTS no toca una tabla que ya existe,
-- así que hay que dropearla.
-- Producción nunca corrió aquella versión, así que allá este script no tiene sentido.
USE recetali_receta;
SET SESSION lock_wait_timeout = 5;

UPDATE pharmacy SET pharmaceuticalDirectorId = NULL WHERE pharmaceuticalDirectorId IS NOT NULL;
ALTER TABLE pharmacy DROP FOREIGN KEY fk_pharmacy_pharmaceutical_director;
DROP TABLE IF EXISTS pharmaceutical_director;
```

La columna `pharmacy.pharmaceuticalDirectorId` **no** se dropea: es idéntica en las dos versiones,
y el guard de la migración la detecta y la saltea.

- [ ] **Step 1c: Escribir el rollback**

Archivo `doc/migrations/2026-07-31-qf-entity-rollback.sql`:

```sql
-- Rollback de 2026-07-31-qf-entity.sql
--
-- ⚠️ Las tres columnas de `prescription` NO se revierten, a propósito. DROP COLUMN es
-- instantáneo recién desde MySQL 8.0.29; por debajo de esa versión reconstruye la tabla
-- entera con las escrituras bloqueadas — o sea, el rollback provocaría exactamente el
-- downtime que el forward evita. Son columnas aditivas, con default, y completamente
-- inertes para la versión anterior de la app. Si hay que volver atrás: se revierte el
-- deploy y las columnas se quedan donde están.
USE recetali_receta;
SET SESSION lock_wait_timeout = 5;

UPDATE pharmacy SET pharmaceuticalDirectorId = NULL WHERE pharmaceuticalDirectorId IS NOT NULL;
ALTER TABLE pharmacy DROP FOREIGN KEY fk_pharmacy_pharmaceutical_director;
ALTER TABLE pharmacy DROP COLUMN pharmaceuticalDirectorId;
DROP TABLE pharmaceutical_director;
```

- [ ] **Step 2: Resetear DEV y correr el script**

```bash
cd /Users/pablo/iwtg/recetalia-workspace/recetalia-api-rest
scp doc/migrations/2026-07-31-qf-entity-RESET-dev-only.sql \
    doc/migrations/2026-07-31-qf-entity.sql root@138.197.150.98:/tmp/
ssh root@138.197.150.98 \
  "docker exec -i recetalia-mysql mysql -uroot -pRootDev98_p3Wn8sLzQ < /tmp/2026-07-31-qf-entity-RESET-dev-only.sql"
ssh root@138.197.150.98 \
  "docker exec -i recetalia-mysql mysql -uroot -pRootDev98_p3Wn8sLzQ < /tmp/2026-07-31-qf-entity.sql"
```

Esperado: sin errores en ninguno de los dos. El reset tiene que correr **antes** que la migración.

- [ ] **Step 3: Verificar que el backfill cierra**

```bash
scp recetalia-api-rest/doc/migrations/2026-07-31-qf-entity.sql root@138.197.150.98:/tmp/
ssh root@138.197.150.98 \
  "docker exec -i recetalia-mysql mysql -uroot -pRootDev98_p3Wn8sLzQ recetali_receta < /tmp/2026-07-31-qf-entity.sql"
```

Esperado: sin errores. Los `SELECT "... ya existe"` solo aparecen si se corre por segunda vez.

- [ ] **Step 3: Verificar que el backfill cierra**

```bash
ssh root@138.197.150.98 "docker exec recetalia-mysql mysql -uroot -pRootDev98_p3Wn8sLzQ -N -e \"
  SELECT (SELECT COUNT(DISTINCT TRIM(managerCJP)) FROM recetali_receta.pharmacy
           WHERE deletedAt IS NULL AND managerCJP IS NOT NULL AND TRIM(managerCJP)<>'') AS cjps_distintos,
         (SELECT COUNT(*) FROM recetali_receta.pharmaceutical_director) AS qfs_creados,
         (SELECT COUNT(*) FROM recetali_receta.pharmacy
           WHERE deletedAt IS NULL AND managerCJP IS NOT NULL AND TRIM(managerCJP)<>''
             AND pharmaceuticalDirectorId IS NULL) AS sin_vincular,
         (SELECT COUNT(*) FROM recetali_receta.pharmaceutical_director
           WHERE status='NEEDS_REVIEW') AS marcados,
         (SELECT COUNT(*) FROM (SELECT TRIM(managerCJP) c FROM recetali_receta.pharmacy
             WHERE deletedAt IS NULL AND managerCJP IS NOT NULL AND TRIM(managerCJP)<>''
             GROUP BY TRIM(managerCJP)
             HAVING COUNT(DISTINCT CONCAT(TRIM(managerName),'|',TRIM(managerLastname)))>1) x)
           AS colisionados_esperados;\""
```

Esperado: `cjps_distintos` == `qfs_creados` (**220**, no 221: el `TRIM` fusiona ` 108908` con
`108908`), `sin_vincular` == `0`, y `marcados` == `colisionados_esperados` (**20**).

- [ ] **Step 4: Correr la migración una segunda vez y re-verificar**

Solo la migración, **no** el reset. Mismo comando de verificación del Step 3: los cinco números
tienen que dar **idénticos**. Eso prueba la idempotencia.

- [ ] **Step 5: Verificar que ningún QF marcado quedó sin farmacias, y ver la lista para curar**

```bash
ssh root@138.197.150.98 "docker exec recetalia-mysql mysql -uroot -pRootDev98_p3Wn8sLzQ -e \"
  SELECT d.cjp, d.name, d.lastname, COUNT(p.id) AS farmacias
  FROM recetali_receta.pharmaceutical_director d
  LEFT JOIN recetali_receta.pharmacy p ON p.pharmaceuticalDirectorId = d.id
  WHERE d.status='NEEDS_REVIEW' GROUP BY d.id ORDER BY farmacias DESC;\""
```

Esperado: 20 filas, ninguna con `farmacias = 0`. Guardá la salida: es la lista que hay que mandar a
curar.

- [ ] **Step 6: Commit**

```bash
git add doc/migrations/2026-07-31-qf-entity.sql \
        doc/migrations/2026-07-31-qf-entity-RESET-dev-only.sql \
        doc/migrations/2026-07-31-qf-entity-rollback.sql
git commit -m "feat(qf): migracion de entidad QF con CJP normalizado y colisiones marcadas"
```

---

### Task 2: Entidad y repositorio del QF

**Files:**
- Create: `src/main/java/com/recetalia/api/application/domain/model/entities/PharmaceuticalDirector.java`
- Create: `src/main/java/com/recetalia/api/application/domain/repository/PharmaceuticalDirectorRepository.java`

- [ ] **Step 1: Crear la entidad**

```java
package com.recetalia.api.application.domain.model.entities;

import com.recetalia.api.application.domain.model.Document;
import com.recetalia.api.application.domain.model.Phone;
import com.recetalia.api.application.infrastructure.converter.DocumentConverter;
import com.recetalia.api.application.infrastructure.converter.PhoneConverter;
import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import org.hibernate.annotations.ColumnDefault;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.Instant;
import java.util.UUID;

/**
 * Químico Farmacéutico (regente / director técnico). La identidad es el CJP, no el email:
 * el mismo QF puede ser D.T. de varias farmacias y antes sus datos vivían duplicados en
 * pharmacy.manager*, lo que permitía que divergieran entre sucursales.
 */
@Getter
@Setter
@Entity
@Table(name = "pharmaceutical_director")
public class PharmaceuticalDirector {

  public PharmaceuticalDirector() {
  }

  public PharmaceuticalDirector(String id) {
    this.id = id;
  }

  @Id
  @Column(name = "id", nullable = false, length = 36)
  private String id;

  @Column(name = "cjp", nullable = false, unique = true, length = 150)
  private String cjp;

  @Column(name = "name", nullable = false, length = 150)
  private String name;

  @Column(name = "lastname", nullable = false, length = 150)
  private String lastname;

  @Lob
  @Column(name = "document")
  @Convert(converter = DocumentConverter.class)
  private Document document;

  @Column(name = "email", length = 200)
  private String email;

  @Lob
  @Column(name = "phone")
  @Convert(converter = PhoneConverter.class)
  private Phone phone;

  /**
   * ACTIVE | INACTIVE | NEEDS_REVIEW.
   * NEEDS_REVIEW = el CJP está compartido por varias personas en `pharmacy`, así que esta
   * identidad no es confiable: no puede registrarse ni firmar hasta que alguien cure el dato.
   */
  @ColumnDefault("'ACTIVE'")
  @Column(name = "status", nullable = false, length = 255)
  private String status = "ACTIVE";

  public static final String STATUS_ACTIVE = "ACTIVE";
  public static final String STATUS_NEEDS_REVIEW = "NEEDS_REVIEW";

  /** NULL mientras el QF no haya completado su registro. */
  @Column(name = "registeredAt")
  private Instant registeredAt;

  @CreationTimestamp
  @Column(name = "createdAt", nullable = false, updatable = false)
  private Instant createdAt;

  @UpdateTimestamp
  @Column(name = "updatedAt", nullable = false)
  private Instant updatedAt;

  // Sin deletedAt a propósito: el CJP es un identificador permanente con UNIQUE encima, y
  // soft delete + UNIQUE haría que un CJP dado de baja no se pueda volver a registrar nunca.
  // La baja se expresa con status = 'INACTIVE'.

  @PrePersist
  public void prePersist() {
    if (this.id == null) {
      this.id = UUID.randomUUID().toString();
    }
  }
}
```

- [ ] **Step 2: Crear el repositorio**

```java
package com.recetalia.api.application.domain.repository;

import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface PharmaceuticalDirectorRepository extends JpaRepository<PharmaceuticalDirector, String> {

  /** El CJP es único: no hace falta filtrar por borrado lógico, la tabla no lo tiene. */
  Optional<PharmaceuticalDirector> findByCjp(String cjp);
}
```

- [ ] **Step 3: Compilar**

Run: `./gradlew build -x test`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: Commit**

```bash
git add src/main/java/com/recetalia/api/application/domain/model/entities/PharmaceuticalDirector.java \
        src/main/java/com/recetalia/api/application/domain/repository/PharmaceuticalDirectorRepository.java
git commit -m "feat(qf): entidad y repositorio de PharmaceuticalDirector"
```

---

### Task 3: Vincular la farmacia con el QF y agregar los campos de papel a Prescription

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/domain/model/entities/Pharmacy.java`
- Modify: `src/main/java/com/recetalia/api/application/domain/model/entities/Prescription.java`

- [ ] **Step 1: Agregar la relación en `Pharmacy`**

Justo después del campo `managerDocument`, agregar:

```java
  /**
   * QF (director técnico) de la farmacia. Los campos manager* de arriba son una copia derivada
   * que se conserva porque la usan el Excel y varias consultas; la fuente de verdad es esta.
   */
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "pharmaceuticalDirectorId")
  private PharmaceuticalDirector pharmaceuticalDirector;
```

- [ ] **Step 2: Agregar los campos de papel en `Prescription`**

Justo después del campo `condvtaId`, agregar:

```java
  /** DIGITAL = emitida por Recetalia; PAPER = transcripta por la farmacia desde una receta en papel. */
  @ColumnDefault("'DIGITAL'")
  @Column(name = "origin", nullable = false, length = 10)
  private String origin = "DIGITAL";

  /** Nº de talonario que trae la receta en papel. NULL para las digitales. */
  @Column(name = "paperNumber", length = 50)
  private String paperNumber;

  /** Fecha que dice el papel (distinta de createdAt, que es cuándo se cargó al sistema). */
  @Column(name = "paperIssuedAt")
  private Instant paperIssuedAt;
```

Si `Prescription.java` no importa `org.hibernate.annotations.ColumnDefault`, agregarlo.

- [ ] **Step 3: Compilar**

Run: `./gradlew build -x test`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: Commit**

```bash
git add src/main/java/com/recetalia/api/application/domain/model/entities/Pharmacy.java \
        src/main/java/com/recetalia/api/application/domain/model/entities/Prescription.java
git commit -m "feat(qf): relacion pharmacy->QF y campos de receta en papel"
```

---

### Task 4: Servicio de registro — resolve del QF desde la farmacia

Esta es la pieza central: decide si el QF se crea o se reusa. La regla que no se puede violar es que **un QF que ya existe no se pisa nunca**, ni sus datos ni su clave.

**Files:**
- Create: `src/main/java/com/recetalia/api/application/service/PharmaceuticalDirectorRegistrationService.java`
- Create: `src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorResolveTest.java`

- [ ] **Step 1: Escribir el test que falla**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.domain.repository.PharmaceuticalDirectorRepository;
import com.recetalia.api.application.dto.request.PharmacyRequest;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.SecurityApiRecetaliaPort;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.dto.UserRequestSecurityApiRecetalia;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class PharmaceuticalDirectorResolveTest {

    private PharmaceuticalDirectorRegistrationServiceImpl newSvc(
            PharmaceuticalDirectorRepository repo, SecurityApiRecetaliaPort port) {
        PharmaceuticalDirectorRegistrationServiceImpl svc = new PharmaceuticalDirectorRegistrationServiceImpl();
        svc.setDepsForTest(repo, port, null);
        svc.setQfConfigForTest("qf.recetalia.com");
        return svc;
    }

    private PharmacyRequest requestWith(String cjp, String name, String lastname, String password) {
        PharmacyRequest r = new PharmacyRequest();
        r.setManagerCJP(cjp);
        r.setManagerName(name);
        r.setManagerLastname(lastname);
        r.setManagerPassword(password);
        r.setInfo("abc1234567");
        return r;
    }

    @Test
    void qfNuevo_seCreaYSeRegistraElUsuarioDeLogin() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        when(repo.findByCjp("51697")).thenReturn(Optional.empty());
        when(repo.save(any(PharmaceuticalDirector.class))).thenAnswer(i -> i.getArgument(0));

        PharmaceuticalDirector qf = newSvc(repo, port)
                .resolveForPharmacy(requestWith("  51697 ", "JUAN", "PEREZ", "Clave2026"));

        assertThat(qf.getCjp()).isEqualTo("51697");
        assertThat(qf.getName()).isEqualTo("JUAN");
        assertThat(qf.getRegisteredAt()).isNull();

        ArgumentCaptor<UserRequestSecurityApiRecetalia> cap =
                ArgumentCaptor.forClass(UserRequestSecurityApiRecetalia.class);
        // registerUser (NO registerUserBack): la clave viene cifrada AES desde el front,
        // y solo /register la descifra usando el `info`.
        verify(port).registerUser(cap.capture());
        assertThat(cap.getValue().getEmail()).isEqualTo("51697@qf.recetalia.com");
        assertThat(cap.getValue().getPassword()).isEqualTo("Clave2026");
        assertThat(cap.getValue().getInfo()).isEqualTo("abc1234567");
        assertThat(cap.getValue().getRole()).isEqualTo("ROLE_PHARMACEUTICAL_DIRECTOR");
        assertThat(cap.getValue().getApplicationApiKey()).isEqualTo("qf-recetalia-app");
        assertThat(cap.getValue().getMustChangePassword()).isTrue();
    }

    @Test
    void siElUsuarioDeLoginYaExiste_seConservaElQf() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        when(repo.findByCjp("51697")).thenReturn(Optional.empty());
        when(repo.save(any(PharmaceuticalDirector.class))).thenAnswer(i -> i.getArgument(0));
        when(port.registerUser(any())).thenThrow(new RuntimeException("Email already exists."));

        // El usuario de login ya estaba (alta vieja, previa a la entidad): no es un error.
        PharmaceuticalDirector qf = newSvc(repo, port)
                .resolveForPharmacy(requestWith("51697", "JUAN", "PEREZ", "Clave2026"));

        assertThat(qf.getCjp()).isEqualTo("51697");
        verify(repo, never()).delete(any(PharmaceuticalDirector.class));
    }

    @Test
    void qfExistente_seReusaYNoSePisaNadaNiSeTocaElUsuario() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmaceuticalDirector existente = new PharmaceuticalDirector("qf-1");
        existente.setCjp("51697");
        existente.setName("JUAN");
        existente.setLastname("PEREZ");
        when(repo.findByCjp("51697")).thenReturn(Optional.of(existente));

        PharmaceuticalDirector qf = newSvc(repo, port)
                .resolveForPharmacy(requestWith("51697", "OTRO NOMBRE", "OTRO APELLIDO", "OtraClave"));

        assertThat(qf.getId()).isEqualTo("qf-1");
        assertThat(qf.getName()).isEqualTo("JUAN");          // no se pisó
        assertThat(qf.getLastname()).isEqualTo("PEREZ");     // no se pisó
        verify(repo, never()).save(any());
        verifyNoInteractions(port);                          // no se toca su clave
    }

    @Test
    void sinCjp_devuelveNull() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);

        assertThat(newSvc(repo, port).resolveForPharmacy(requestWith("   ", "X", "Y", "z"))).isNull();
        assertThat(newSvc(repo, port).resolveForPharmacy(requestWith(null, "X", "Y", "z"))).isNull();
        verifyNoInteractions(port);
    }

    @Test
    void siFallaElSecurityApi_seRevierteElQfCreado() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        when(repo.findByCjp("51697")).thenReturn(Optional.empty());
        when(repo.save(any(PharmaceuticalDirector.class))).thenAnswer(i -> i.getArgument(0));
        when(port.registerUser(any())).thenThrow(new RuntimeException("boom"));

        assertThatThrownBy(() -> newSvc(repo, port)
                .resolveForPharmacy(requestWith("51697", "JUAN", "PEREZ", "Clave2026")))
                .isInstanceOf(RuntimeException.class);

        verify(repo).delete(any(PharmaceuticalDirector.class));
    }
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `./gradlew test --tests "*PharmaceuticalDirectorResolveTest*"`
Expected: FAIL — no compila, `PharmaceuticalDirectorRegistrationServiceImpl` no existe.

- [ ] **Step 3: Crear la interfaz del servicio**

```java
package com.recetalia.api.application.service;

import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.dto.request.PharmacyRequest;
import com.recetalia.api.application.dto.request.PharmaceuticalDirectorRegisterRequest;
import com.recetalia.api.application.dto.response.PharmaceuticalDirectorLookupResponse;
import com.recetalia.api.application.dto.response.PharmaceuticalDirectorMeResponse;
import com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;

public interface PharmaceuticalDirectorRegistrationService {

  /** Crea el QF si no existe para ese CJP, o devuelve el existente sin tocarlo. null si no hay CJP. */
  PharmaceuticalDirector resolveForPharmacy(PharmacyRequest request);

  /** Lookup público por CJP: solo nombre y apellido. */
  PharmaceuticalDirectorLookupResponse lookupByCjp(String cjp) throws ResourceNotFoundException;

  /** Datos del QF autenticado + las farmacias que lo asociaron. */
  PharmaceuticalDirectorMeResponse getMe() throws ResourceNotFoundException;

  /** Completa el registro: datos personales, clave nueva y sello de registeredAt. */
  PharmaceuticalDirectorMeResponse register(PharmaceuticalDirectorRegisterRequest request)
      throws ResourceNotFoundException;
}
```

- [ ] **Step 4: Agregar `managerPassword` a `PharmacyRequest`**

En `dto/request/PharmacyRequest.java`, después del campo `managerCJP`:

```java
  /**
   * Clave inicial del QF, definida por la farmacia y entregada al QF en mano.
   * Solo se usa cuando el CJP no existe todavía; si el QF ya existe se ignora.
   * Viaja cifrada AES junto con el resto del alta (mismo `info`).
   */
  private String managerPassword;
```

- [ ] **Step 5: Implementar el servicio (solo `resolveForPharmacy`; el resto se completa en las tasks 6 y 7)**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.domain.repository.PharmaceuticalDirectorRepository;
import com.recetalia.api.application.domain.repository.PharmacyRepository;
import com.recetalia.api.application.dto.request.PharmaceuticalDirectorRegisterRequest;
import com.recetalia.api.application.dto.request.PharmacyRequest;
import com.recetalia.api.application.dto.response.PharmaceuticalDirectorLookupResponse;
import com.recetalia.api.application.dto.response.PharmaceuticalDirectorMeResponse;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.SecurityApiRecetaliaPort;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.dto.UserRequestSecurityApiRecetalia;
import com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;
import com.recetalia.api.application.service.PharmaceuticalDirectorRegistrationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.Optional;

@Service
public class PharmaceuticalDirectorRegistrationServiceImpl implements PharmaceuticalDirectorRegistrationService {

  private static final Logger logger =
      LoggerFactory.getLogger(PharmaceuticalDirectorRegistrationServiceImpl.class);

  @Value("${qf.email-domain}")
  private String qfEmailDomain;

  @Autowired private PharmaceuticalDirectorRepository qfRepository;
  @Autowired private SecurityApiRecetaliaPort securityApiRecetaliaPort;
  @Autowired private PharmacyRepository pharmacyRepository;

  @Override
  public PharmaceuticalDirector resolveForPharmacy(PharmacyRequest request) {
    String cjp = trimToNull(request.getManagerCJP());
    if (cjp == null) return null;

    Optional<PharmaceuticalDirector> existing = qfRepository.findByCjp(cjp);
    if (existing.isPresent()) {
      // El QF ya fue dado de alta por otra farmacia: se reusa TAL CUAL.
      // No se pisan sus datos ni se toca su clave.
      return existing.get();
    }

    PharmaceuticalDirector qf = new PharmaceuticalDirector();
    qf.setCjp(cjp);
    qf.setName(trimToNull(request.getManagerName()));
    qf.setLastname(trimToNull(request.getManagerLastname()));
    qf.setDocument(request.getManagerDocument());
    qf.setStatus("ACTIVE");
    qf = qfRepository.save(qf);

    String email = cjp + "@" + qfEmailDomain;
    try {
      // registerUser, NO registerUserBack: la clave llega cifrada AES desde el front del alta
      // de farmacia, y solo /register la descifra con el `info`. registerUserBack la esperaría
      // en claro y guardaría el ciphertext como password.
      securityApiRecetaliaPort.registerUser(new UserRequestSecurityApiRecetalia(
          email, email, request.getManagerPassword(),
          "ROLE_PHARMACEUTICAL_DIRECTOR", "qf-recetalia-app", request.getInfo(), true));
      logger.info("QF creado para CJP {}", cjp);
    } catch (RuntimeException e) {
      String msg = e.getMessage();
      if (msg != null && msg.contains("already exists")) {
        // El usuario de login ya existía (alta vieja, previa a esta entidad). No es un error:
        // se conserva la fila del QF y el QF entra con la clave que ya tenía.
        logger.info("El usuario de login del QF {} ya existía; se conserva", cjp);
        return qf;
      }
      // El usuario de login no se creó → no dejar el QF huérfano.
      qfRepository.delete(qf);
      logger.error("No se pudo crear el usuario de login del QF {}: {}", cjp, msg);
      throw e;
    }
    return qf;
  }

  @Override
  public PharmaceuticalDirectorLookupResponse lookupByCjp(String cjp) throws ResourceNotFoundException {
    throw new UnsupportedOperationException("Task 5");
  }

  @Override
  public PharmaceuticalDirectorMeResponse getMe() throws ResourceNotFoundException {
    throw new UnsupportedOperationException("Task 6");
  }

  @Override
  public PharmaceuticalDirectorMeResponse register(PharmaceuticalDirectorRegisterRequest request)
      throws ResourceNotFoundException {
    throw new UnsupportedOperationException("Task 7");
  }

  private String trimToNull(String s) {
    if (s == null) return null;
    String t = s.trim();
    return t.isEmpty() ? null : t;
  }

  /* Test seams: unit tests sin contexto de Spring (mismo patrón que PharmacyServiceQfUserTest). */
  void setDepsForTest(PharmaceuticalDirectorRepository repo, SecurityApiRecetaliaPort port,
                      PharmacyRepository pharmacies) {
    this.qfRepository = repo;
    this.securityApiRecetaliaPort = port;
    this.pharmacyRepository = pharmacies;
  }

  void setQfConfigForTest(String domain) {
    this.qfEmailDomain = domain;
  }
}
```

Los tres `UnsupportedOperationException` son andamios temporales de este plan, no placeholders: se reemplazan por implementación real en las tasks 5, 6 y 7. Ningún test ni endpoint los toca antes.

- [ ] **Step 6: Crear los DTOs vacíos que la interfaz referencia**

`dto/response/PharmaceuticalDirectorLookupResponse.java`:

```java
package com.recetalia.api.application.dto.response;

import lombok.AllArgsConstructor;
import lombok.Data;

/** Respuesta del lookup PÚBLICO por CJP: deliberadamente sin documento, email ni teléfono. */
@Data
@AllArgsConstructor
public class PharmaceuticalDirectorLookupResponse {
  private String cjp;
  private String name;
  private String lastname;
}
```

`dto/response/PharmaceuticalDirectorMeResponse.java`:

```java
package com.recetalia.api.application.dto.response;

import com.recetalia.api.application.domain.model.Document;
import com.recetalia.api.application.domain.model.Phone;
import lombok.Data;

import java.time.Instant;
import java.util.List;

@Data
public class PharmaceuticalDirectorMeResponse {
  private String id;
  private String cjp;
  private String name;
  private String lastname;
  private Document document;
  private String email;
  private Phone phone;
  /** ACTIVE | INACTIVE | NEEDS_REVIEW. El front muestra el cartel de revisión con esto. */
  private String status;
  private Instant registeredAt;
  private List<PharmacyResponse> pharmacies;
}
```

`dto/request/PharmaceuticalDirectorRegisterRequest.java`:

```java
package com.recetalia.api.application.dto.request;

import com.recetalia.api.application.domain.model.Document;
import com.recetalia.api.application.domain.model.Phone;
import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class PharmaceuticalDirectorRegisterRequest {
  @NotBlank private String name;
  @NotBlank private String lastname;
  private Document document;
  private String email;
  private Phone phone;

  /** Clave nueva, cifrada AES en el front. Se reenvía tal cual a /renew-password. */
  @NotBlank private String password;

  /** Sufijo dinámico de la clave AES. */
  @NotBlank private String info;
}
```

- [ ] **Step 7: Correr el test y verificar que pasa**

Run: `./gradlew test --tests "*PharmaceuticalDirectorResolveTest*"`
Expected: PASS, 4 tests.

- [ ] **Step 8: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/PharmaceuticalDirectorRegistrationService.java \
        src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java \
        src/main/java/com/recetalia/api/application/dto/request/PharmaceuticalDirectorRegisterRequest.java \
        src/main/java/com/recetalia/api/application/dto/request/PharmacyRequest.java \
        src/main/java/com/recetalia/api/application/dto/response/PharmaceuticalDirectorLookupResponse.java \
        src/main/java/com/recetalia/api/application/dto/response/PharmaceuticalDirectorMeResponse.java \
        src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorResolveTest.java
git commit -m "feat(qf): resolve de QF desde el alta de farmacia (crea o reusa por CJP)"
```

---

### Task 5: Lookup público por CJP

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java`
- Modify: `src/main/java/com/recetalia/api/application/controller/PharmacyController.java`
- Modify: `src/main/java/com/recetalia/api/application/infrastructure/config/SecurityConfiguration.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorLookupTest.java`

- [ ] **Step 1: Escribir el test que falla**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.Document;
import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.domain.repository.PharmaceuticalDirectorRepository;
import com.recetalia.api.application.dto.response.PharmaceuticalDirectorLookupResponse;
import com.recetalia.api.application.infrastructure.exception.ResourceNotFoundException;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PharmaceuticalDirectorLookupTest {

    @Test
    void existente_devuelveSoloNombreYApellido() throws Exception {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("51697");
        qf.setName("JUAN");
        qf.setLastname("PEREZ");
        qf.setEmail("juan@example.com");
        qf.setDocument(new Document());
        when(repo.findByCjp("51697")).thenReturn(Optional.of(qf));

        PharmaceuticalDirectorRegistrationServiceImpl svc = new PharmaceuticalDirectorRegistrationServiceImpl();
        svc.setDepsForTest(repo, null, null);

        PharmaceuticalDirectorLookupResponse res = svc.lookupByCjp("  51697 ");

        assertThat(res.getCjp()).isEqualTo("51697");
        assertThat(res.getName()).isEqualTo("JUAN");
        assertThat(res.getLastname()).isEqualTo("PEREZ");
        // El DTO no expone email/documento/telefono: el endpoint es publico.
        assertThat(PharmaceuticalDirectorLookupResponse.class.getDeclaredFields()).hasSize(3);
    }

    @Test
    void inexistente_tira404() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        when(repo.findByCjp("99999")).thenReturn(Optional.empty());

        PharmaceuticalDirectorRegistrationServiceImpl svc = new PharmaceuticalDirectorRegistrationServiceImpl();
        svc.setDepsForTest(repo, null, null);

        assertThatThrownBy(() -> svc.lookupByCjp("99999"))
                .isInstanceOf(ResourceNotFoundException.class);
    }
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `./gradlew test --tests "*PharmaceuticalDirectorLookupTest*"`
Expected: FAIL con `UnsupportedOperationException: Task 5`

- [ ] **Step 3: Implementar `lookupByCjp`**

Reemplazar el cuerpo del método en `PharmaceuticalDirectorRegistrationServiceImpl`:

```java
  @Override
  public PharmaceuticalDirectorLookupResponse lookupByCjp(String cjp) throws ResourceNotFoundException {
    String normalized = trimToNull(cjp);
    if (normalized == null) {
      throw new ResourceNotFoundException("CJP vacío");
    }
    PharmaceuticalDirector qf = qfRepository.findByCjp(normalized)
        .orElseThrow(() -> new ResourceNotFoundException("No hay QF con CJP :: " + normalized));
    return new PharmaceuticalDirectorLookupResponse(qf.getCjp(), qf.getName(), qf.getLastname());
  }
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `./gradlew test --tests "*PharmaceuticalDirectorLookupTest*"`
Expected: PASS, 2 tests.

- [ ] **Step 5: Exponer el endpoint en `PharmacyController`**

Agregar el import y el método:

```java
  @Autowired
  private PharmaceuticalDirectorRegistrationService pharmaceuticalDirectorRegistrationService;

  /**
   * Lookup PÚBLICO del QF por CJP, para el alta de farmacia.
   * Vive bajo /api/pharmacies a propósito: /api/pharmaceutical-director/** está reservado
   * para el QF autenticado y no conviene tener un path público pegado a uno protegido.
   */
  @GetMapping("/pharmaceutical-director-lookup/{cjp}")
  public ResponseEntity<GenericResponse<PharmaceuticalDirectorLookupResponse>> lookupPharmaceuticalDirector(
      @PathVariable String cjp) throws ResourceNotFoundException {
    return ResponseEntity.ok(new GenericResponse<>(
        ResponseStatus.SUCCESS, pharmaceuticalDirectorRegistrationService.lookupByCjp(cjp)));
  }
```

- [ ] **Step 6: Abrir el endpoint en `SecurityConfiguration`**

Junto a los otros `permitAll` (después de la línea de `/api/pharmacies`):

```java
                        .requestMatchers(HttpMethod.GET, "/api/pharmacies/pharmaceutical-director-lookup/**").permitAll()
```

- [ ] **Step 7: Compilar y correr todos los tests**

Run: `./gradlew build`
Expected: `BUILD SUCCESSFUL`, sin tests rojos.

- [ ] **Step 8: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java \
        src/main/java/com/recetalia/api/application/controller/PharmacyController.java \
        src/main/java/com/recetalia/api/application/infrastructure/config/SecurityConfiguration.java \
        src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorLookupTest.java
git commit -m "feat(qf): lookup publico de QF por CJP para el alta de farmacia"
```

---

### Task 6: `GET /api/pharmaceutical-director/me`

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java`
- Modify: `src/main/java/com/recetalia/api/application/controller/PharmaceuticalDirectorController.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorMeTest.java`

- [ ] **Step 1: Escribir el test que falla**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.domain.model.entities.Pharmacy;
import com.recetalia.api.application.domain.repository.PharmaceuticalDirectorRepository;
import com.recetalia.api.application.domain.repository.PharmacyRepository;
import com.recetalia.api.application.dto.response.PharmaceuticalDirectorMeResponse;
import com.recetalia.api.application.service.CurrentUserAuthenticatedService;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PharmaceuticalDirectorMeTest {

    @Test
    void devuelveLosDatosDelQfYSusFarmacias() throws Exception {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        PharmacyRepository pharmacies = mock(PharmacyRepository.class);
        CurrentUserAuthenticatedService currentUser = mock(CurrentUserAuthenticatedService.class);

        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("51697");
        qf.setName("JUAN");
        qf.setLastname("PEREZ");

        Pharmacy p1 = new Pharmacy("ph-1"); p1.setName("EL TUNEL POCITOS");
        Pharmacy p2 = new Pharmacy("ph-2"); p2.setName("FARMACIA ARIES");

        when(currentUser.getCurrentPharmaceuticalDirectorCjp()).thenReturn("51697");
        when(repo.findByCjp("51697")).thenReturn(Optional.of(qf));
        when(pharmacies.findAllByManagerCJPAndDeletedAtIsNull("51697")).thenReturn(List.of(p1, p2));

        PharmaceuticalDirectorRegistrationServiceImpl svc = new PharmaceuticalDirectorRegistrationServiceImpl();
        svc.setDepsForTest(repo, null, pharmacies);
        svc.setCurrentUserForTest(currentUser);

        PharmaceuticalDirectorMeResponse me = svc.getMe();

        assertThat(me.getCjp()).isEqualTo("51697");
        assertThat(me.getName()).isEqualTo("JUAN");
        assertThat(me.getRegisteredAt()).isNull();
        assertThat(me.getPharmacies()).hasSize(2);
        assertThat(me.getPharmacies()).extracting("name")
                .containsExactly("EL TUNEL POCITOS", "FARMACIA ARIES");
    }
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `./gradlew test --tests "*PharmaceuticalDirectorMeTest*"`
Expected: FAIL con `UnsupportedOperationException: Task 6` (o error de compilación por `setCurrentUserForTest`).

- [ ] **Step 3: Agregar las dependencias que faltan al servicio**

En `PharmaceuticalDirectorRegistrationServiceImpl`, agregar los imports
`com.recetalia.api.application.service.CurrentUserAuthenticatedService` y
`com.recetalia.api.application.dto.mapper.response.PharmacyResponseMapper`, y los campos:

```java
  @Autowired private CurrentUserAuthenticatedService currentUser;
  @Autowired private PharmacyResponseMapper pharmacyResponseMapper;
```

Y el test seam:

```java
  void setCurrentUserForTest(CurrentUserAuthenticatedService cu) {
    this.currentUser = cu;
    this.pharmacyResponseMapper = org.mapstruct.factory.Mappers.getMapper(PharmacyResponseMapper.class);
  }
```

- [ ] **Step 4: Implementar `getMe`**

```java
  /**
   * A diferencia del resto de los endpoints del QF, este NO bloquea a los NEEDS_REVIEW:
   * es justamente el que le permite a la app mostrarle por qué no puede hacer nada.
   */
  @Override
  public PharmaceuticalDirectorMeResponse getMe() throws ResourceNotFoundException {
    String cjp = currentUser.getCurrentPharmaceuticalDirectorCjp();
    PharmaceuticalDirector qf = qfRepository.findByCjp(cjp)
        .orElseThrow(() -> new ResourceNotFoundException("No hay QF con CJP :: " + cjp));
    return toMeResponse(qf);
  }

  private PharmaceuticalDirectorMeResponse toMeResponse(PharmaceuticalDirector qf) {
    PharmaceuticalDirectorMeResponse res = new PharmaceuticalDirectorMeResponse();
    res.setId(qf.getId());
    res.setCjp(qf.getCjp());
    res.setName(qf.getName());
    res.setLastname(qf.getLastname());
    res.setDocument(qf.getDocument());
    res.setEmail(qf.getEmail());
    res.setPhone(qf.getPhone());
    res.setStatus(qf.getStatus());
    res.setRegisteredAt(qf.getRegisteredAt());
    res.setPharmacies(pharmacyRepository.findAllByManagerCJPAndDeletedAtIsNull(qf.getCjp())
        .stream().map(pharmacyResponseMapper::toDto).toList());
    return res;
  }
```

- [ ] **Step 5: Correr el test y verificar que pasa**

Run: `./gradlew test --tests "*PharmaceuticalDirectorMeTest*"`
Expected: PASS, 1 test.

- [ ] **Step 6: Exponer el endpoint**

En `PharmaceuticalDirectorController`:

```java
  @Autowired
  private PharmaceuticalDirectorRegistrationService registrationService;

  @GetMapping("/me")
  public ResponseEntity<GenericResponse<PharmaceuticalDirectorMeResponse>> me() throws ResourceNotFoundException {
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, registrationService.getMe()));
  }
```

Queda cubierto por el matcher existente `/api/pharmaceutical-director/**` → `ROLE_ROLE_PHARMACEUTICAL_DIRECTOR`. No tocar `SecurityConfiguration`.

- [ ] **Step 7: Compilar**

Run: `./gradlew build`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 8: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java \
        src/main/java/com/recetalia/api/application/controller/PharmaceuticalDirectorController.java \
        src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorMeTest.java
git commit -m "feat(qf): endpoint /me con datos del QF y sus farmacias"
```

---

### Task 7: `POST /api/pharmaceutical-director/register`

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java`
- Modify: `src/main/java/com/recetalia/api/application/controller/PharmaceuticalDirectorController.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegisterTest.java`

- [ ] **Step 1: Escribir el test que falla**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.domain.model.entities.Pharmacy;
import com.recetalia.api.application.domain.repository.PharmaceuticalDirectorRepository;
import com.recetalia.api.application.domain.repository.PharmacyRepository;
import com.recetalia.api.application.dto.request.PharmaceuticalDirectorRegisterRequest;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.SecurityApiRecetaliaPort;
import com.recetalia.api.application.infrastructure.adapter.restsecurityapirecetalia.dto.UserRequestSecurityApiRecetalia;
import com.recetalia.api.application.service.CurrentUserAuthenticatedService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class PharmaceuticalDirectorRegisterTest {

    private PharmaceuticalDirectorRegisterRequest req() {
        PharmaceuticalDirectorRegisterRequest r = new PharmaceuticalDirectorRegisterRequest();
        r.setName("JUAN CARLOS");
        r.setLastname("PEREZ");
        r.setEmail("juan@example.com");
        r.setPassword("cifrada==");
        r.setInfo("abc1234567");
        return r;
    }

    private PharmaceuticalDirectorRegistrationServiceImpl svc(
            PharmaceuticalDirectorRepository repo, SecurityApiRecetaliaPort port,
            PharmacyRepository pharmacies, CurrentUserAuthenticatedService currentUser) {
        PharmaceuticalDirectorRegistrationServiceImpl s = new PharmaceuticalDirectorRegistrationServiceImpl();
        s.setDepsForTest(repo, port, pharmacies);
        s.setCurrentUserForTest(currentUser);
        s.setQfConfigForTest("qf.recetalia.com");
        return s;
    }

    @Test
    void sellaRegisteredAt_propagaAFarmaciasYRenuevaLaClave() throws Exception {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmacyRepository pharmacies = mock(PharmacyRepository.class);
        CurrentUserAuthenticatedService currentUser = mock(CurrentUserAuthenticatedService.class);

        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("51697");
        qf.setName("JUAN");
        qf.setLastname("PEREZ");

        Pharmacy p1 = new Pharmacy("ph-1");
        p1.setManagerName("VIEJO");
        p1.setManagerLastname("NOMBRE");

        when(currentUser.getCurrentPharmaceuticalDirectorCjp()).thenReturn("51697");
        when(repo.findByCjp("51697")).thenReturn(Optional.of(qf));
        when(repo.save(any(PharmaceuticalDirector.class))).thenAnswer(i -> i.getArgument(0));
        when(pharmacies.findAllByManagerCJPAndDeletedAtIsNull("51697")).thenReturn(List.of(p1));

        svc(repo, port, pharmacies, currentUser).register(req());

        assertThat(qf.getName()).isEqualTo("JUAN CARLOS");
        assertThat(qf.getEmail()).isEqualTo("juan@example.com");
        assertThat(qf.getRegisteredAt()).isNotNull();

        // Se propagan los datos verificados a la copia derivada de cada farmacia.
        assertThat(p1.getManagerName()).isEqualTo("JUAN CARLOS");
        assertThat(p1.getManagerLastname()).isEqualTo("PEREZ");
        verify(pharmacies).save(p1);

        ArgumentCaptor<UserRequestSecurityApiRecetalia> cap =
                ArgumentCaptor.forClass(UserRequestSecurityApiRecetalia.class);
        verify(port).renewPassword(cap.capture());
        assertThat(cap.getValue().getEmail()).isEqualTo("51697@qf.recetalia.com");
        assertThat(cap.getValue().getPassword()).isEqualTo("cifrada==");
        assertThat(cap.getValue().getInfo()).isEqualTo("abc1234567");
    }

    @Test
    void siFallaRenewPassword_noSellaRegisteredAt() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmacyRepository pharmacies = mock(PharmacyRepository.class);
        CurrentUserAuthenticatedService currentUser = mock(CurrentUserAuthenticatedService.class);

        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("51697");

        when(currentUser.getCurrentPharmaceuticalDirectorCjp()).thenReturn("51697");
        when(repo.findByCjp("51697")).thenReturn(Optional.of(qf));
        when(pharmacies.findAllByManagerCJPAndDeletedAtIsNull("51697")).thenReturn(List.of());
        when(port.renewPassword(any())).thenThrow(new RuntimeException("security-api caído"));

        assertThatThrownBy(() -> svc(repo, port, pharmacies, currentUser).register(req()))
                .isInstanceOf(RuntimeException.class);

        assertThat(qf.getRegisteredAt()).isNull();
        verify(repo, never()).save(any());
    }

    @Test
    void qfEnRevision_noPuedeRegistrarse() {
        PharmaceuticalDirectorRepository repo = mock(PharmaceuticalDirectorRepository.class);
        SecurityApiRecetaliaPort port = mock(SecurityApiRecetaliaPort.class);
        PharmacyRepository pharmacies = mock(PharmacyRepository.class);
        CurrentUserAuthenticatedService currentUser = mock(CurrentUserAuthenticatedService.class);

        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("1");
        qf.setStatus(PharmaceuticalDirector.STATUS_NEEDS_REVIEW);

        when(currentUser.getCurrentPharmaceuticalDirectorCjp()).thenReturn("1");
        when(repo.findByCjp("1")).thenReturn(Optional.of(qf));

        assertThatThrownBy(() -> svc(repo, port, pharmacies, currentUser).register(req()))
                .isInstanceOf(BusinessRuleException.class)
                .hasMessageContaining("revisión");

        verifyNoInteractions(port);
        verify(repo, never()).save(any());
        assertThat(qf.getRegisteredAt()).isNull();
    }
}
```

Agregar el import de `com.recetalia.api.application.infrastructure.exception.BusinessRuleException`.

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `./gradlew test --tests "*PharmaceuticalDirectorRegisterTest*"`
Expected: FAIL con `UnsupportedOperationException: Task 7`

- [ ] **Step 3: Implementar `register`**

El orden importa: primero se renueva la clave, y solo si eso salió bien se sella `registeredAt`. Si el security-api está caído, el QF tiene que poder reintentar.

```java
  @Override
  @org.springframework.transaction.annotation.Transactional
  public PharmaceuticalDirectorMeResponse register(PharmaceuticalDirectorRegisterRequest request)
      throws ResourceNotFoundException {
    String cjp = currentUser.getCurrentPharmaceuticalDirectorCjp();
    PharmaceuticalDirector qf = qfRepository.findByCjp(cjp)
        .orElseThrow(() -> new ResourceNotFoundException("No hay QF con CJP :: " + cjp));

    // Un CJP compartido por varias personas no es una identidad: no se puede registrar
    // hasta que alguien cure el dato.
    if (PharmaceuticalDirector.STATUS_NEEDS_REVIEW.equals(qf.getStatus())) {
      throw new BusinessRuleException(
          "Tu registro está en revisión. Contactate con Recetalia para habilitarlo.");
    }

    // 1) Clave nueva PRIMERO: si el security-api falla, no se sella el registro y puede reintentar.
    String email = cjp + "@" + qfEmailDomain;
    securityApiRecetaliaPort.renewPassword(new UserRequestSecurityApiRecetalia(
        email, email, request.getPassword(),
        "ROLE_PHARMACEUTICAL_DIRECTOR", "qf-recetalia-app", request.getInfo()));

    // 2) Datos verificados por el QF.
    qf.setName(trimToNull(request.getName()));
    qf.setLastname(trimToNull(request.getLastname()));
    if (request.getDocument() != null) qf.setDocument(request.getDocument());
    if (request.getEmail() != null) qf.setEmail(trimToNull(request.getEmail()));
    if (request.getPhone() != null) qf.setPhone(request.getPhone());
    qf.setRegisteredAt(java.time.Instant.now());
    qf = qfRepository.save(qf);

    // 3) Propagar a la copia derivada de cada farmacia, que es lo que leen el Excel y las consultas viejas.
    for (Pharmacy ph : pharmacyRepository.findAllByManagerCJPAndDeletedAtIsNull(cjp)) {
      ph.setManagerName(qf.getName());
      ph.setManagerLastname(qf.getLastname());
      if (qf.getDocument() != null) ph.setManagerDocument(qf.getDocument());
      ph.setPharmaceuticalDirector(qf);
      pharmacyRepository.save(ph);
    }

    return toMeResponse(qf);
  }
```

Agregar el import de `com.recetalia.api.application.domain.model.entities.Pharmacy`.

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `./gradlew test --tests "*PharmaceuticalDirectorRegisterTest*"`
Expected: PASS, 2 tests.

- [ ] **Step 5: Exponer el endpoint**

En `PharmaceuticalDirectorController`:

```java
  @PostMapping("/register")
  public ResponseEntity<GenericResponse<PharmaceuticalDirectorMeResponse>> register(
      @jakarta.validation.Valid @RequestBody PharmaceuticalDirectorRegisterRequest request)
      throws ResourceNotFoundException {
    return ResponseEntity.ok(new GenericResponse<>(
        ResponseStatus.SUCCESS, registrationService.register(request)));
  }
```

- [ ] **Step 6: Compilar y correr todo**

Run: `./gradlew build`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 7: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegistrationServiceImpl.java \
        src/main/java/com/recetalia/api/application/controller/PharmaceuticalDirectorController.java \
        src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorRegisterTest.java
git commit -m "feat(qf): endpoint de registro del QF (datos, clave y propagacion a farmacias)"
```

---

### Task 8: Enganchar el resolve en el alta/edición de farmacia y borrar el camino viejo

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PharmacyServiceImpl.java`
- Modify: `src/main/resources/application.yml`
- Delete: `src/test/java/com/recetalia/api/application/service/impl/PharmacyServiceQfUserTest.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PharmacyQfLinkTest.java`

- [ ] **Step 1: Escribir el test que falla**

```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.model.entities.PharmaceuticalDirector;
import com.recetalia.api.application.domain.model.entities.Pharmacy;
import com.recetalia.api.application.dto.request.PharmacyRequest;
import com.recetalia.api.application.service.PharmaceuticalDirectorRegistrationService;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PharmacyQfLinkTest {

    @Test
    void alResolverElQf_seVinculaYSeSincronizanLosManagerFields() {
        PharmaceuticalDirectorRegistrationService reg = mock(PharmaceuticalDirectorRegistrationService.class);
        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("51697");
        qf.setName("JUAN");
        qf.setLastname("PEREZ");
        when(reg.resolveForPharmacy(any(PharmacyRequest.class))).thenReturn(qf);

        PharmacyServiceImpl svc = new PharmacyServiceImpl();
        svc.setQfRegistrationForTest(reg);

        Pharmacy pharmacy = new Pharmacy("ph-1");
        PharmacyRequest request = new PharmacyRequest();
        request.setManagerCJP("51697");

        svc.linkPharmaceuticalDirector(pharmacy, request);

        assertThat(pharmacy.getPharmaceuticalDirector()).isSameAs(qf);
        assertThat(pharmacy.getManagerName()).isEqualTo("JUAN");
        assertThat(pharmacy.getManagerLastname()).isEqualTo("PEREZ");
        assertThat(pharmacy.getManagerCJP()).isEqualTo("51697");
    }

    @Test
    void sinQf_noTocaLaFarmacia() {
        PharmaceuticalDirectorRegistrationService reg = mock(PharmaceuticalDirectorRegistrationService.class);
        when(reg.resolveForPharmacy(any(PharmacyRequest.class))).thenReturn(null);

        PharmacyServiceImpl svc = new PharmacyServiceImpl();
        svc.setQfRegistrationForTest(reg);

        Pharmacy pharmacy = new Pharmacy("ph-1");
        pharmacy.setManagerName("ORIGINAL");

        svc.linkPharmaceuticalDirector(pharmacy, new PharmacyRequest());

        assertThat(pharmacy.getPharmaceuticalDirector()).isNull();
        assertThat(pharmacy.getManagerName()).isEqualTo("ORIGINAL");
    }
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `./gradlew test --tests "*PharmacyQfLinkTest*"`
Expected: FAIL — `linkPharmaceuticalDirector` no existe.

- [ ] **Step 3: Reemplazar `ensurePharmaceuticalDirectorUser` por `linkPharmaceuticalDirector`**

En `PharmacyServiceImpl`, borrar el método `ensurePharmaceuticalDirectorUser` completo (líneas 234-255), los `@Value` de `qfDefaultPassword` y `qfEmailDomain` (líneas 52-56) y los dos test seams `securityApiRecetaliaPortForTest` / `setQfConfigForTest` (líneas 258-259). Agregar:

```java
  @Autowired
  private PharmaceuticalDirectorRegistrationService qfRegistrationService;

  /**
   * Resuelve el QF del request (lo crea si el CJP es nuevo, lo reusa si ya existe) y lo vincula
   * a la farmacia, sincronizando la copia derivada manager*. No-op si el request no trae CJP.
   */
  public void linkPharmaceuticalDirector(Pharmacy pharmacy, PharmacyRequest request) {
    PharmaceuticalDirector qf = qfRegistrationService.resolveForPharmacy(request);
    if (qf == null) return;
    pharmacy.setPharmaceuticalDirector(qf);
    pharmacy.setManagerName(qf.getName());
    pharmacy.setManagerLastname(qf.getLastname());
    pharmacy.setManagerCJP(qf.getCjp());
    if (qf.getDocument() != null) {
      pharmacy.setManagerDocument(qf.getDocument());
    }
  }

  /* Test seam. */
  void setQfRegistrationForTest(PharmaceuticalDirectorRegistrationService s) {
    this.qfRegistrationService = s;
  }
```

Agregar los imports de `PharmaceuticalDirector` y `PharmaceuticalDirectorRegistrationService`.

- [ ] **Step 4: Llamarlo desde `create` y `update`**

En `create`, reemplazar la línea `ensurePharmaceuticalDirectorUser(request.getManagerCJP());` (línea 109) por:

```java
    // Alta o reuso del QF. Si falla, el alta de la farmacia ya está hecha: se loguea y sigue,
    // igual que el email de bienvenida. La farmacia puede reintentar desde su perfil.
    try {
      linkPharmaceuticalDirector(pharmacy, request);
      pharmacy = pharmacyRepository.save(pharmacy);
    } catch (RuntimeException e) {
      logger.error("Farmacia {} creada, pero falló el alta del QF: {}", request.getEmail(), e.getMessage());
    }
```

En `update`, reemplazar `ensurePharmaceuticalDirectorUser(saved.getManagerCJP());` (línea 206) por:

```java
    if (role.equals("ROLE_MANAGEMENT") && request.getManagerCJP() != null) {
      linkPharmaceuticalDirector(saved, request);
      saved = pharmacyRepository.save(saved);
    }
```

- [ ] **Step 5: Borrar el test viejo**

```bash
git rm src/test/java/com/recetalia/api/application/service/impl/PharmacyServiceQfUserTest.java
```

Cubría `ensurePharmaceuticalDirectorUser`, que ya no existe. Su reemplazo son `PharmaceuticalDirectorResolveTest` (Task 4) y `PharmacyQfLinkTest`.

- [ ] **Step 6: Sacar la clave por defecto de `application.yml`**

Borrar la línea `default-password: ${QF_DEFAULT_PASSWORD:Recetalia2026}` del bloque `qf:` (queda solo `email-domain`). Ya no hay clave fija: la define la farmacia.

- [ ] **Step 7: Correr todos los tests**

Run: `./gradlew build`
Expected: `BUILD SUCCESSFUL`. Si algún test referencia `setQfConfigForTest` de `PharmacyServiceImpl`, es que quedó sin borrar del Step 5.

- [ ] **Step 8: Commit**

```bash
git add -A src/main/java/com/recetalia/api/application/service/impl/PharmacyServiceImpl.java \
           src/main/resources/application.yml \
           src/test/java/com/recetalia/api/application/service/impl/
git commit -m "feat(qf): el alta de farmacia crea o reusa el QF por CJP; baja de la clave por defecto"
```

---

### Task 9: El firmante sale de la entidad QF, y los CJP en revisión no acceden a nada

Dos cambios en la misma clase, por el mismo motivo de fondo: el servicio del QF hoy confía en
`pharmacy.manager*` y en el CJP crudo.

1. `buildQfName` lee `pharmacy.managerName` de la farmacia de esa dispensación, así que el mismo QF
   podía firmar con nombres distintos según la sucursal.
2. **Más grave:** `getMyPharmacies`, `getGreenDispensations` y `controlDispensation` autorizan por
   `managerCJP` sin más. Con los 20 CJPs compartidos que hay en los datos, quien entra con el CJP
   `1` ve las recetas verdes —medicamentos controlados— de siete farmacias ajenas. El agujero es
   anterior a este trabajo; se cierra acá, antes de que el módulo pase a producción.

**Files:**
- Modify: `src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorServiceImpl.java`
- Test: `src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorServiceImplTest.java`

- [ ] **Step 1: Agregar el test que falla al archivo existente**

```java
    @Test
    void elNombreDelFirmanteSaleDeLaEntidadQfNoDeLaFarmacia() throws Exception {
        PharmaceuticalDirectorRepository qfRepo = mock(PharmaceuticalDirectorRepository.class);
        PharmacyRepository pharmacyRepository = mock(PharmacyRepository.class);
        DispensationRepository dispensationRepository = mock(DispensationRepository.class);
        CurrentUserAuthenticatedService currentUser = mock(CurrentUserAuthenticatedService.class);

        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("51697");
        qf.setName("JUAN CARLOS");
        qf.setLastname("PEREZ");

        Pharmacy ph = new Pharmacy("ph-1");
        ph.setManagerCJP("51697");
        ph.setManagerName("NOMBRE VIEJO");        // dato divergente en la sucursal
        ph.setManagerLastname("APELLIDO VIEJO");

        Dispensation d = new Dispensation();
        d.setId("disp-1");
        d.setPharmacy(ph);

        when(currentUser.getCurrentPharmaceuticalDirectorCjp()).thenReturn("51697");
        when(dispensationRepository.findWithGraphByIdAndDeletedAtIsNull("disp-1")).thenReturn(Optional.of(d));
        when(qfRepo.findByCjp("51697")).thenReturn(Optional.of(qf));
        when(dispensationRepository.applyDtControl(eq("disp-1"), anyString(), eq("51697"))).thenReturn(1);

        PharmaceuticalDirectorServiceImpl svc = new PharmaceuticalDirectorServiceImpl();
        svc.setDepsForTest(pharmacyRepository, dispensationRepository, currentUser, qfRepo);

        assertThat(svc.controlDispensation("disp-1")).isTrue();
        verify(dispensationRepository).applyDtControl("disp-1", "JUAN CARLOS PEREZ", "51697");
    }

    @Test
    void qfEnRevision_noVeFarmaciasNiDispensacionesNiPuedeFirmar() {
        PharmaceuticalDirectorRepository qfRepo = mock(PharmaceuticalDirectorRepository.class);
        PharmacyRepository pharmacyRepository = mock(PharmacyRepository.class);
        DispensationRepository dispensationRepository = mock(DispensationRepository.class);
        DispensationService dispensationService = mock(DispensationService.class);
        CurrentUserAuthenticatedService currentUser = mock(CurrentUserAuthenticatedService.class);

        // CJP '1': compartido por 7 farmacias y 6 personas distintas. No es una identidad.
        PharmaceuticalDirector qf = new PharmaceuticalDirector("qf-1");
        qf.setCjp("1");
        qf.setStatus(PharmaceuticalDirector.STATUS_NEEDS_REVIEW);

        when(currentUser.getCurrentPharmaceuticalDirectorCjp()).thenReturn("1");
        when(qfRepo.findByCjp("1")).thenReturn(Optional.of(qf));

        PharmaceuticalDirectorServiceImpl svc = new PharmaceuticalDirectorServiceImpl();
        svc.setDepsForTest(pharmacyRepository, dispensationRepository, currentUser, qfRepo);

        assertThatThrownBy(svc::getMyPharmacies).isInstanceOf(BusinessRuleException.class);
        assertThatThrownBy(() -> svc.getGreenDispensations("ph-1", null, null, Pageable.unpaged()))
                .isInstanceOf(BusinessRuleException.class);
        assertThatThrownBy(() -> svc.controlDispensation("disp-1"))
                .isInstanceOf(BusinessRuleException.class);

        // No llegó a tocar ni las farmacias ni las dispensaciones.
        verifyNoInteractions(pharmacyRepository, dispensationRepository, dispensationService);
    }
```

Los imports que haga falta agregar: `PharmaceuticalDirector`, `PharmaceuticalDirectorRepository`, `Dispensation`, `Pharmacy`, `Optional`, y los matchers `eq`/`anyString` de Mockito.

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `./gradlew test --tests "*PharmaceuticalDirectorServiceImplTest*"`
Expected: FAIL — `setDepsForTest` no existe con esa firma, y el nombre sigue saliendo de la farmacia.

- [ ] **Step 3: Cambiar `buildQfName` para que lea de la entidad**

En `PharmaceuticalDirectorServiceImpl`, agregar la dependencia y el test seam, y reemplazar `buildQfName`:

```java
    @Autowired private PharmaceuticalDirectorRepository qfRepository;

    /**
     * Resuelve el QF autenticado y verifica que su identidad sea confiable.
     * Un CJP compartido por varias personas queda marcado NEEDS_REVIEW en el backfill: hasta que
     * alguien cure el dato no puede ver ni firmar nada, porque "las farmacias de ese CJP" son en
     * realidad las farmacias de varias personas distintas.
     */
    private PharmaceuticalDirector currentQf() throws ResourceNotFoundException {
        String cjp = currentUser.getCurrentPharmaceuticalDirectorCjp();
        PharmaceuticalDirector qf = qfRepository.findByCjp(cjp)
                .orElseThrow(() -> new ResourceNotFoundException("No hay QF con CJP :: " + cjp));
        if (PharmaceuticalDirector.STATUS_NEEDS_REVIEW.equals(qf.getStatus())) {
            throw new BusinessRuleException(
                    "Tu registro está en revisión. Contactate con Recetalia para habilitarlo.");
        }
        return qf;
    }

    /** Nombre del firmante: sale de la entidad QF, no de la copia manager* de la sucursal. */
    private String buildQfName(PharmaceuticalDirector qf) {
        return ((qf.getName() == null ? "" : qf.getName().trim()) + " "
              + (qf.getLastname() == null ? "" : qf.getLastname().trim())).trim();
    }

    /* Test seam. */
    void setDepsForTest(PharmacyRepository pharmacies, DispensationRepository dispensations,
                        CurrentUserAuthenticatedService cu, PharmaceuticalDirectorRepository qfs) {
        this.pharmacyRepository = pharmacies;
        this.dispensationRepository = dispensations;
        this.currentUser = cu;
        this.qfRepository = qfs;
    }
```

Y reemplazar en los tres métodos públicos la resolución cruda del CJP por `currentQf()`:

```java
    @Override
    public List<PharmacyResponse> getMyPharmacies() throws ResourceNotFoundException {
        PharmaceuticalDirector qf = currentQf();
        return pharmacyRepository.findAllByManagerCJPAndDeletedAtIsNull(qf.getCjp()).stream()
                .map(pharmacyResponseMapper::toDto)
                .collect(Collectors.toList());
    }
```

En `getGreenDispensations`, `assertPharmacyBelongsToCurrentQf(pharmacyId)` pasa a arrancar con
`PharmaceuticalDirector qf = currentQf();` y comparar contra `qf.getCjp()` en lugar de contra el
CJP crudo del token.

En `controlDispensation`, reemplazar las dos primeras líneas por `PharmaceuticalDirector qf =
currentQf();` + `String cjp = qf.getCjp();`, y `String name = buildQfName(ph);` por
`String name = buildQfName(qf);`.

Agregar el import de `BusinessRuleException`.

- [ ] **Step 4: Correr los tests y verificar que pasan**

Run: `./gradlew test --tests "*PharmaceuticalDirectorServiceImplTest*"`
Expected: PASS, incluidos los tests que ya existían.

- [ ] **Step 5: Compilar y correr todo**

Run: `./gradlew build`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 6: Commit**

```bash
git add src/main/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorServiceImpl.java \
        src/test/java/com/recetalia/api/application/service/impl/PharmaceuticalDirectorServiceImplTest.java
git commit -m "fix(qf): el nombre del firmante sale de la entidad QF y no de la sucursal"
```

---

### Task 10: Validación manual contra DEV (.98)

Los tests unitarios no tocan la DB ni el security-api. Este paso verifica el circuito real.

**Files:** ninguno — es verificación.

- [ ] **Step 1: Deployar api-rest en el .98**

```bash
rsync -az --delete --exclude .git --exclude build --exclude .gradle \
  recetalia-api-rest/ root@138.197.150.98:/opt/recetalia/recetalia-api-rest/
ssh root@138.197.150.98 "cd /opt/recetalia/deploy-recetalia && \
  docker compose build recetalia-api-rest && docker compose up -d --no-deps recetalia-api-rest"
```

⚠️ **No recrear nginx** (`docker compose up -d` a secas activa `40-doctorconsultas.conf` y rompe PRE).

- [ ] **Step 2: Lookup de un CJP que existe**

```bash
curl -s "https://apipre.recetalia.com/recetalia-api-rest/api/pharmacies/pharmaceutical-director-lookup/999999"
```

Esperado: `{"status":"SUCCESS","answer":{"cjp":"999999","name":"...","lastname":"..."}}` **sin token**, y sin campos de email/documento/teléfono.

- [ ] **Step 3: Lookup de un CJP que no existe**

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmacies/pharmaceutical-director-lookup/000000"
```

Esperado: `404`

- [ ] **Step 4: `/me` con el token del QF**

```bash
TOKEN=$(curl -s -X POST "https://apipre.recetalia.com/security-api-recetalia/api/auth/loginBack" \
  -H "Content-Type: application/json" \
  -d '{"email":"999999@qf.recetalia.com","password":"Recetalia2026!","info":"000"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmaceutical-director/me" \
  | python3 -m json.tool
```

Esperado: los datos del QF y un array `pharmacies` con las 3 farmacias de prueba (ARIES, MINAS, Test).

- [ ] **Step 5: `/me` sin token debe rechazar**

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  "https://apipre.recetalia.com/recetalia-api-rest/api/pharmaceutical-director/me"
```

Esperado: `401`

- [ ] **Step 6: Verificar que el backfill vinculó las farmacias del QF de prueba**

```bash
ssh root@138.197.150.98 "docker exec recetalia-mysql mysql -uroot -pRootDev98_p3Wn8sLzQ -N -e \"
  SELECT p.name, d.cjp, d.name, d.lastname, d.registeredAt
  FROM recetali_receta.pharmacy p
  JOIN recetali_receta.pharmaceutical_director d ON d.id = p.pharmaceuticalDirectorId
  WHERE d.cjp = '999999';\""
```

Esperado: 3 filas, todas con el mismo nombre de QF (ya no divergente) y `registeredAt` en NULL.

- [ ] **Step 7: Commit del registro de validación**

Anotar el resultado en `WORK-STATUS.md` de la raíz del workspace. No hay commit: la raíz no es un repo git.

---

## Resumen de lo que queda listo para los planes siguientes

| Consumidor | Qué le deja este plan |
|---|---|
| Plan 2 (fronts de alta del D.T.) | `GET /api/pharmacies/pharmaceutical-director-lookup/{cjp}` y el campo `managerPassword` de `PharmacyRequest` |
| Plan 3 (app QF) | `GET /api/pharmaceutical-director/me` y `POST /api/pharmaceutical-director/register` |
| Plan 4 (recetas en papel) | Columnas `origin`, `paperNumber` y `paperIssuedAt` en `prescription`, ya mapeadas en la entidad |

**Dependencia que el Plan 2 no puede pasar por alto:** `managerPassword` viaja **cifrada AES**, igual
que el resto de las claves del alta, y el backend la manda a `/register` del security-api, que la
descifra usando el `info` del mismo request. Las cuatro pantallas tienen que cifrar la clave del QF
con **el mismo `info`** que ya usan para la clave de la farmacia. Gestión hoy no manda `info` en la
edición: hay que agregarlo.

**Queda para el Plan 4, no se pierde:** endurecer por rol el endpoint
`/api/dispensations/controlled-medications/excel`, que quedó en `authenticated()` desde julio. Va
ahí porque el Plan 4 ya toca ese Excel para sumarle la columna del Nº.
