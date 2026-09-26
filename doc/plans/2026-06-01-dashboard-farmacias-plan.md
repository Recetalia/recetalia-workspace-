# Dashboard en app de Farmacias (scopeado) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar un dashboard centrado en dispensaciones al app de farmacias, scopeado por rol (admin → su cadena con desglose por sucursal; farmacia → su sucursal), reutilizando las agregaciones del dashboard de Gestión.

**Architecture:** Backend: endpoint nuevo `GET /api/dashboard/pharmacy-summary` con queries nativas scopeadas por `pharmacyId`/`franchiseId`, reutilizando helpers existentes (`buildTopMedicines` DNMA+AMPP, `buildTrend`, `nz`) y DTOs (`MedicineCountRow`, `PharmacyCountRow`, `ActivityTrendRow`). Frontend (farmacias-app): `DashboardComponent` que detecta el rol y consume el endpoint, + landing por-rol.

**Tech Stack:** Java 21 / Spring Boot 3.3 / Gradle · Angular 18.2 / PrimeNG 17 / chart.js.

**Diseño de referencia:** `doc/plans/2026-06-01-dashboard-farmacias-design.md`

---

## Mapa de archivos

### Backend — recetalia-api-rest
- Create `dto/response/PharmacySummaryResponse.java`.
- Modify `domain/repository/DashboardRepository.java` — 4 queries scopeadas.
- Modify `service/DashboardService.java` — `getPharmacySummary(...)`.
- Modify `service/impl/DashboardServiceImpl.java` — impl (reusa `buildTopMedicines`, `buildTrend`, `nz`).
- Modify `controller/DashboardController.java` — `GET /api/dashboard/pharmacy-summary`.
- Test `src/test/java/com/recetalia/api/application/service/impl/DashboardPharmacySummaryTest.java`.

### Frontend — farmacias-recetalia-app
- Modify `package.json` — `chart.js`.
- Create `src/app/model/response/pharmacy-summary-response.ts`.
- Create `src/app/services/dashboard.service.ts`.
- Create `src/app/pages/application/home/dashboard/dashboard.component.{ts,html,scss}`.
- Create `src/app/pages/application/home/landing-redirect/landing-redirect.component.ts`.
- Modify `home.module.ts` (declarar + ChartModule), `home-routing.module.ts` (ruta dashboard + landing), `components/sidebar/sidebar.component.html` (ítem Dashboard).

### Comandos
- Backend: `cd recetalia-api-rest && ./gradlew test --tests DashboardPharmacySummaryTest` · `./gradlew build`
- Frontend: `cd farmacias-recetalia-app && npx ng build`

### Columnas (MySQL, ya verificadas)
- `dispensation`(createdAt, deletedAt, status='DISPENSED', pharmacyId, productId, productType); `pharmacy`(id, name, franchiseId).
- Rango: `col >= CAST(:fromTs AS DATETIME(6)) AND col < CAST(:toTs AS DATETIME(6))`.

---

## FASE 1 — Backend (recetalia-api-rest)

### Task 1: DTO + queries scopeadas

**Files:**
- Create `dto/response/PharmacySummaryResponse.java`
- Modify `domain/repository/DashboardRepository.java`

Reutiliza projections existentes: `DailyCountProjection {day,total}`, `MedicineCountProjection {productId,productType,total}`, `PharmacyCountProjection {pharmacyId,pharmacyName,total}`. Reutiliza DTOs `ActivityTrendRow {date,prescriptions,dispensations}`, `MedicineCountRow {medicineId,medicineName,count}`, `PharmacyCountRow {pharmacyId,pharmacyName,count}`.

- [ ] **Step 1: DTO** `PharmacySummaryResponse.java`:
```java
package com.recetalia.api.application.dto.response;
import lombok.*;
import java.util.List;
@Getter @Setter @NoArgsConstructor @AllArgsConstructor
public class PharmacySummaryResponse {
    private long dispensations;
    private long previousDispensations;
    private List<ActivityTrendRow> trend;
    private List<MedicineCountRow> topMedicines;
    private List<PharmacyCountRow> byBranch;
}
```

- [ ] **Step 2: Repository** — agregar al final de `DashboardRepository` (antes del `}` de cierre). Todas excluyen soft-deleted y filtran `status='DISPENSED'`; el JOIN a `pharmacy` permite filtrar por `franchiseId`:
```java
    @Query(value = """
        SELECT COUNT(*)
        FROM dispensation d
        JOIN pharmacy ph ON ph.id = d.pharmacyId
        WHERE d.deletedAt IS NULL AND d.status = 'DISPENSED'
          AND d.createdAt >= CAST(:fromTs AS DATETIME(6))
          AND d.createdAt <  CAST(:toTs   AS DATETIME(6))
          AND (:pharmacyId IS NULL OR d.pharmacyId = :pharmacyId)
          AND (:franchiseId IS NULL OR ph.franchiseId = :franchiseId)
        """, nativeQuery = true)
    Long countDispensationsScoped(@Param("fromTs") Instant fromTs, @Param("toTs") Instant toTs,
                                  @Param("pharmacyId") String pharmacyId, @Param("franchiseId") String franchiseId);

    @Query(value = """
        SELECT DATE(d.createdAt) AS day, COUNT(*) AS total
        FROM dispensation d
        JOIN pharmacy ph ON ph.id = d.pharmacyId
        WHERE d.deletedAt IS NULL AND d.status = 'DISPENSED'
          AND d.createdAt >= CAST(:fromTs AS DATETIME(6))
          AND d.createdAt <  CAST(:toTs   AS DATETIME(6))
          AND (:pharmacyId IS NULL OR d.pharmacyId = :pharmacyId)
          AND (:franchiseId IS NULL OR ph.franchiseId = :franchiseId)
        GROUP BY DATE(d.createdAt)
        """, nativeQuery = true)
    List<DailyCountProjection> getDispensationDailyCountsScoped(@Param("fromTs") Instant fromTs, @Param("toTs") Instant toTs,
                                  @Param("pharmacyId") String pharmacyId, @Param("franchiseId") String franchiseId);

    @Query(value = """
        SELECT d.productId AS productId, d.productType AS productType, COUNT(*) AS total
        FROM dispensation d
        JOIN pharmacy ph ON ph.id = d.pharmacyId
        WHERE d.deletedAt IS NULL AND d.status = 'DISPENSED'
          AND d.createdAt >= CAST(:fromTs AS DATETIME(6))
          AND d.createdAt <  CAST(:toTs   AS DATETIME(6))
          AND (:pharmacyId IS NULL OR d.pharmacyId = :pharmacyId)
          AND (:franchiseId IS NULL OR ph.franchiseId = :franchiseId)
        GROUP BY d.productId, d.productType
        ORDER BY total DESC
        LIMIT :limit
        """, nativeQuery = true)
    List<MedicineCountProjection> getTopMedicinesScoped(@Param("fromTs") Instant fromTs, @Param("toTs") Instant toTs,
                                  @Param("limit") int limit, @Param("pharmacyId") String pharmacyId, @Param("franchiseId") String franchiseId);

    @Query(value = """
        SELECT ph.id AS pharmacyId, ph.name AS pharmacyName, COUNT(*) AS total
        FROM dispensation d
        JOIN pharmacy ph ON ph.id = d.pharmacyId
        WHERE d.deletedAt IS NULL AND d.status = 'DISPENSED'
          AND d.createdAt >= CAST(:fromTs AS DATETIME(6))
          AND d.createdAt <  CAST(:toTs   AS DATETIME(6))
          AND ph.franchiseId = :franchiseId
        GROUP BY ph.id, ph.name
        ORDER BY total DESC
        """, nativeQuery = true)
    List<PharmacyCountProjection> getDispensationsByBranch(@Param("fromTs") Instant fromTs, @Param("toTs") Instant toTs,
                                  @Param("franchiseId") String franchiseId);
```

- [ ] **Step 3: Compilar** — Run: `./gradlew compileJava` · Expected: BUILD SUCCESSFUL.
- [ ] **Step 4: Commit**
```bash
git add src/main/java/com/recetalia/api/application/dto/response/PharmacySummaryResponse.java \
        src/main/java/com/recetalia/api/application/domain/repository/DashboardRepository.java
git commit -m "feat(dashboard-farmacia): DTO + queries scopeadas de dispensaciones"
```

---

### Task 2: Service (TDD) + endpoint

**Files:**
- Modify `service/DashboardService.java`
- Modify `service/impl/DashboardServiceImpl.java`
- Modify `controller/DashboardController.java`
- Test `src/test/java/com/recetalia/api/application/service/impl/DashboardPharmacySummaryTest.java`

`DashboardServiceImpl` ya tiene los helpers `buildTopMedicines(List<MedicineCountProjection>)`, `buildTrend(LocalDate,LocalDate,List<DailyCountProjection>,List<DailyCountProjection>)` y `nz(Long)`, y el repo `repo` + `dnma` inyectados por constructor.

- [ ] **Step 1: Interface** — agregar a `DashboardService`:
```java
    com.recetalia.api.application.dto.response.PharmacySummaryResponse getPharmacySummary(
        String pharmacyId, String franchiseId, java.time.LocalDate startDate, java.time.LocalDate endDate);
```

- [ ] **Step 2: Test que falla** `DashboardPharmacySummaryTest.java`:
```java
package com.recetalia.api.application.service.impl;

import com.recetalia.api.application.domain.repository.DashboardRepository;
import com.recetalia.api.application.dto.response.PharmacySummaryResponse;
import com.recetalia.api.application.dto.response.projection.*;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.when;

class DashboardPharmacySummaryTest {

    private DailyCountProjection daily(String day, long total) {
        return new DailyCountProjection() {
            public String getDay() { return day; }
            public Long getTotal() { return total; }
        };
    }
    private PharmacyCountProjection branch(String id, String name, long total) {
        return new PharmacyCountProjection() {
            public String getPharmacyId() { return id; }
            public String getPharmacyName() { return name; }
            public Long getTotal() { return total; }
        };
    }

    private DashboardServiceImpl serviceWith(DashboardRepository repo) {
        DnmaDatabaseServiceImpl dnma = Mockito.mock(DnmaDatabaseServiceImpl.class);
        when(repo.getTopMedicinesScoped(any(), any(), anyInt(), any(), any())).thenReturn(List.of());
        when(repo.getDispensationDailyCountsScoped(any(), any(), any(), any())).thenReturn(List.of());
        return new DashboardServiceImpl(repo, dnma);
    }

    @Test
    void scopesByPharmacyAndComputesDelta() {
        DashboardRepository repo = Mockito.mock(DashboardRepository.class);
        // primera llamada = período actual; segunda = período anterior
        when(repo.countDispensationsScoped(any(), any(), eq("ph1"), isNull())).thenReturn(20L, 10L);

        PharmacySummaryResponse r = serviceWith(repo)
                .getPharmacySummary("ph1", null, LocalDate.of(2026,5,10), LocalDate.of(2026,5,10));

        assertThat(r.getDispensations()).isEqualTo(20);
        assertThat(r.getPreviousDispensations()).isEqualTo(10);
        assertThat(r.getByBranch()).isEmpty(); // sin franchiseId
    }

    @Test
    void byBranchOnlyWhenFranchise() {
        DashboardRepository repo = Mockito.mock(DashboardRepository.class);
        when(repo.countDispensationsScoped(any(), any(), isNull(), eq("fr1"))).thenReturn(13L, 5L);
        when(repo.getDispensationsByBranch(any(), any(), eq("fr1")))
                .thenReturn(List.of(branch("p1","PIGALLE Canadá", 9), branch("p2","PIGALLE Massone", 4)));

        PharmacySummaryResponse r = serviceWith(repo)
                .getPharmacySummary(null, "fr1", LocalDate.of(2026,5,1), LocalDate.of(2026,5,1));

        assertThat(r.getDispensations()).isEqualTo(13);
        assertThat(r.getByBranch()).hasSize(2);
        assertThat(r.getByBranch().get(0).getPharmacyName()).isEqualTo("PIGALLE Canadá");
    }

    @Test
    void fillsTrendZeroDays() {
        DashboardRepository repo = Mockito.mock(DashboardRepository.class);
        when(repo.countDispensationsScoped(any(), any(), any(), any())).thenReturn(3L, 0L);
        when(repo.getDispensationDailyCountsScoped(any(), any(), any(), any()))
                .thenReturn(List.of(daily("2026-05-01", 2), daily("2026-05-03", 1)));

        PharmacySummaryResponse r = serviceWith(repo)
                .getPharmacySummary("ph1", null, LocalDate.of(2026,5,1), LocalDate.of(2026,5,3));

        assertThat(r.getTrend()).hasSize(3);
        assertThat(r.getTrend().get(0).getDispensations()).isEqualTo(2);
        assertThat(r.getTrend().get(1).getDispensations()).isEqualTo(0);
        assertThat(r.getTrend().get(2).getDispensations()).isEqualTo(1);
    }
}
```
> En estos tests `getDispensationsByBranch` no se stubea cuando `franchiseId` es null (no se llama); cuando hay franchiseId, se stubea. `serviceWith` deja vacíos los métodos comunes.

- [ ] **Step 3: Correr — debe fallar** — Run: `./gradlew test --tests DashboardPharmacySummaryTest` · Expected: FAIL (método inexistente).

- [ ] **Step 4: Implementar** en `DashboardServiceImpl` (agregar imports `PharmacySummaryResponse`, `PharmacyCountRow` si faltan; reusa helpers existentes):
```java
  @Override
  public com.recetalia.api.application.dto.response.PharmacySummaryResponse getPharmacySummary(
      String pharmacyId, String franchiseId, java.time.LocalDate startDate, java.time.LocalDate endDate) {
    String pid = (pharmacyId != null && pharmacyId.isBlank()) ? null : pharmacyId;
    String fid = (franchiseId != null && franchiseId.isBlank()) ? null : franchiseId;

    java.time.ZoneId zone = java.time.ZoneId.systemDefault();
    java.time.Instant fromTs = startDate.atStartOfDay(zone).toInstant();
    java.time.Instant toTs = endDate.plusDays(1).atStartOfDay(zone).toInstant();
    long durationDays = java.time.temporal.ChronoUnit.DAYS.between(startDate, endDate) + 1;
    java.time.LocalDate prevEnd = startDate.minusDays(1);
    java.time.LocalDate prevStart = prevEnd.minusDays(durationDays - 1);
    java.time.Instant prevFromTs = prevStart.atStartOfDay(zone).toInstant();
    java.time.Instant prevToTs = prevEnd.plusDays(1).atStartOfDay(zone).toInstant();

    long dispensations = nz(repo.countDispensationsScoped(fromTs, toTs, pid, fid));
    long previous = nz(repo.countDispensationsScoped(prevFromTs, prevToTs, pid, fid));

    java.util.List<ActivityTrendRow> trend = buildTrend(startDate, endDate,
        java.util.List.of(), repo.getDispensationDailyCountsScoped(fromTs, toTs, pid, fid));

    java.util.List<MedicineCountRow> topMedicines =
        buildTopMedicines(repo.getTopMedicinesScoped(fromTs, toTs, 10, pid, fid));

    java.util.List<PharmacyCountRow> byBranch = fid == null ? new java.util.ArrayList<>() :
        repo.getDispensationsByBranch(fromTs, toTs, fid).stream()
            .map(p -> new PharmacyCountRow(p.getPharmacyId(), p.getPharmacyName(), nz(p.getTotal())))
            .collect(java.util.stream.Collectors.toList());

    return new com.recetalia.api.application.dto.response.PharmacySummaryResponse(
        dispensations, previous, trend, topMedicines, byBranch);
  }
```
> `buildTrend(start, end, pres, disp)` rellena días en cero; con `pres = List.of()` el campo `prescriptions` de cada `ActivityTrendRow` queda en 0 y `dispensations` toma el conteo scopeado. El front usa solo `dispensations`.

- [ ] **Step 5: Correr — debe pasar** — Run: `./gradlew test --tests DashboardPharmacySummaryTest` · Expected: PASS (3 tests).

- [ ] **Step 6: Controller** — agregar a `DashboardController` (reusa `@DateTimeFormat`, `GenericResponse`, `ResponseStatus` ya importados):
```java
  @GetMapping("/pharmacy-summary")
  public ResponseEntity<GenericResponse<com.recetalia.api.application.dto.response.PharmacySummaryResponse>> pharmacySummary(
      @RequestParam(required = false) String pharmacyId,
      @RequestParam(required = false) String franchiseId,
      @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate startDate,
      @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate endDate) {
    com.recetalia.api.application.dto.response.PharmacySummaryResponse data =
        dashboardService.getPharmacySummary(pharmacyId, franchiseId, startDate, endDate);
    return ResponseEntity.ok(new GenericResponse<>(ResponseStatus.SUCCESS, data));
  }
```

- [ ] **Step 7: Build** — Run: `./gradlew build` · Expected: BUILD SUCCESSFUL. (Si falla solo por DB en contextLoads, reportar y correr `./gradlew compileJava test --tests DashboardPharmacySummaryTest`.)
- [ ] **Step 8: Commit**
```bash
git add src/main/java/com/recetalia/api/application/service/DashboardService.java \
        src/main/java/com/recetalia/api/application/service/impl/DashboardServiceImpl.java \
        src/main/java/com/recetalia/api/application/controller/DashboardController.java \
        src/test/java/com/recetalia/api/application/service/impl/DashboardPharmacySummaryTest.java
git commit -m "feat(dashboard-farmacia): getPharmacySummary + endpoint /api/dashboard/pharmacy-summary (TDD)"
```

---

## FASE 2 — Frontend (farmacias-recetalia-app)

### Task 3: chart.js + modelo + service

**Files:**
- Modify `package.json`
- Create `src/app/model/response/pharmacy-summary-response.ts`
- Create `src/app/services/dashboard.service.ts`

- [ ] **Step 1: chart.js** — Run: `cd farmacias-recetalia-app && npm install chart.js@4 --legacy-peer-deps`
- [ ] **Step 2: Modelo** `pharmacy-summary-response.ts`:
```typescript
export interface TrendRow { date: string; prescriptions: number; dispensations: number; }
export interface MedicineCountRow { medicineId: string; medicineName: string; count: number; }
export interface BranchCountRow { pharmacyId: string; pharmacyName: string; count: number; }
export interface PharmacySummaryResponse {
  dispensations: number;
  previousDispensations: number;
  trend: TrendRow[];
  topMedicines: MedicineCountRow[];
  byBranch: BranchCountRow[];
}
```
- [ ] **Step 3: Service** `dashboard.service.ts`:
```typescript
import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { map, catchError } from 'rxjs/operators';
import { environment } from '../../environments/environment';
import { ApiResponse } from '../model/response/api-response';
import { PharmacySummaryResponse } from '../model/response/pharmacy-summary-response';

@Injectable({ providedIn: 'root' })
export class DashboardService {
  private apiUrl = `${environment.apiUrl}/dashboard`;
  constructor(private http: HttpClient) {}

  getPharmacySummary(scope: { pharmacyId?: string; franchiseId?: string }, startDate: string, endDate: string): Observable<PharmacySummaryResponse> {
    let params = new HttpParams().set('startDate', startDate).set('endDate', endDate);
    if (scope.pharmacyId) params = params.set('pharmacyId', scope.pharmacyId);
    if (scope.franchiseId) params = params.set('franchiseId', scope.franchiseId);
    return this.http.get<ApiResponse<PharmacySummaryResponse>>(`${this.apiUrl}/pharmacy-summary`, { params }).pipe(
      map(r => { if (r.status === 'SUCCESS') return r.answer; throw new Error('API error: ' + r.applicationProvider); }),
      catchError(err => { console.error('dashboard failed', err); return throwError(() => new Error('Failed to fetch dashboard')); })
    );
  }
}
```
- [ ] **Step 4: Commit**
```bash
git add package.json package-lock.json src/app/model/response/pharmacy-summary-response.ts src/app/services/dashboard.service.ts
git commit -m "feat(dashboard-farmacia): chart.js + modelo + DashboardService"
```

---

### Task 4: DashboardComponent

**Files:**
- Create `src/app/pages/application/home/dashboard/dashboard.component.{ts,html,scss}`

- [ ] **Step 1: Componente** (detecta rol → scope; barra de período; tarjeta+delta; tendencia; top medicamentos; por sucursal solo admin):
```typescript
import { Component, OnInit } from '@angular/core';
import { filter, take } from 'rxjs/operators';
import { AuthService } from '../../../../services/auth.service';
import { DashboardService } from '../../../../services/dashboard.service';
import { PharmacySummaryResponse } from '../../../../model/response/pharmacy-summary-response';

type Preset = 'today' | '7d' | '30d' | 'month' | 'custom';

@Component({
  selector: 'app-dashboard',
  templateUrl: './dashboard.component.html',
  styleUrls: ['./dashboard.component.scss'],
})
export class DashboardComponent implements OnInit {
  loading = true;
  error = false;
  data?: PharmacySummaryResponse;
  isAdmin = false;
  private scope: { pharmacyId?: string; franchiseId?: string } = {};

  preset: Preset = '30d';
  startDate!: Date;
  endDate!: Date;

  trendChart: any; trendOpts: any;
  topMedsChart: any; barHOpts: any;
  branchChart: any; pieOpts: any;
  private palette = ['#3b82f6', '#22a06b', '#f59e0b', '#ef4444', '#8b5cf6', '#14b8a6', '#ec4899', '#64748b'];

  constructor(private authService: AuthService, private dashboardService: DashboardService) {}

  ngOnInit(): void {
    this.authService.getCurrentUser().pipe(filter(u => !!u), take(1)).subscribe({
      next: (user: any) => {
        this.isAdmin = user.role === 'ROLE_PHARMACY_ADMIN';
        this.scope = this.isAdmin ? { franchiseId: user.franchiseId } : { pharmacyId: user.pharmacyId };
        if (this.isAdmin && !user.franchiseId) { this.error = true; this.loading = false; return; }
        this.applyPreset('30d');
      },
      error: () => { this.error = true; this.loading = false; },
    });
  }

  applyPreset(p: Preset): void {
    this.preset = p;
    const end = new Date(); const start = new Date();
    if (p === '7d') start.setDate(end.getDate() - 6);
    else if (p === '30d') start.setDate(end.getDate() - 29);
    else if (p === 'month') start.setDate(1);
    if (p !== 'custom') { this.startDate = start; this.endDate = end; this.load(); }
  }
  onCustomChange(): void { if (this.startDate && this.endDate) { this.preset = 'custom'; this.load(); } }

  private iso(d: Date): string {
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }

  get deltaPct(): number | null {
    if (!this.data) return null;
    const prev = this.data.previousDispensations;
    if (prev === 0) return this.data.dispensations === 0 ? 0 : null;
    return Math.round(((this.data.dispensations - prev) / prev) * 1000) / 10;
  }
  get deltaLabel(): string { const d = this.deltaPct; return d == null ? '' : (d > 0 ? '+' : '') + d + '%'; }
  get deltaClass(): string { const d = this.deltaPct; if (d == null || d === 0) return 'flat'; return d > 0 ? 'up' : 'down'; }

  load(): void {
    this.loading = true; this.error = false;
    this.dashboardService.getPharmacySummary(this.scope, this.iso(this.startDate), this.iso(this.endDate)).subscribe({
      next: data => { this.data = data; this.buildCharts(data); this.loading = false; },
      error: () => { this.error = true; this.loading = false; },
    });
  }

  private buildCharts(d: PharmacySummaryResponse): void {
    this.trendChart = {
      labels: d.trend.map(r => r.date),
      datasets: [{ label: 'Dispensaciones', data: d.trend.map(r => r.dispensations), borderColor: '#22a06b', tension: .3 }],
    };
    this.trendOpts = { maintainAspectRatio: false, plugins: { legend: { display: false } } };

    this.topMedsChart = {
      labels: d.topMedicines.map(m => m.medicineName),
      datasets: [{ label: 'Dispensaciones', data: d.topMedicines.map(m => m.count), backgroundColor: '#3b82f6' }],
    };
    this.barHOpts = { maintainAspectRatio: false, indexAxis: 'y', plugins: { legend: { display: false } } };

    this.branchChart = {
      labels: d.byBranch.map(b => b.pharmacyName),
      datasets: [{ data: d.byBranch.map(b => b.count), backgroundColor: this.palette }],
    };
    this.pieOpts = { maintainAspectRatio: false, plugins: { legend: { position: 'right' } } };
  }
}
```
- [ ] **Step 2: Template**:
```html
<div class="dashboard">
  <div class="period-bar">
    <button class="preset" [class.on]="preset==='today'" (click)="applyPreset('today')">Hoy</button>
    <button class="preset" [class.on]="preset==='7d'" (click)="applyPreset('7d')">7 días</button>
    <button class="preset" [class.on]="preset==='30d'" (click)="applyPreset('30d')">30 días</button>
    <button class="preset" [class.on]="preset==='month'" (click)="applyPreset('month')">Mes actual</button>
    <span class="custom">
      <p-calendar [(ngModel)]="startDate" dateFormat="dd/mm/yy" (onSelect)="onCustomChange()" placeholder="Desde"></p-calendar>
      <p-calendar [(ngModel)]="endDate" dateFormat="dd/mm/yy" (onSelect)="onCustomChange()" placeholder="Hasta"></p-calendar>
    </span>
  </div>

  <div *ngIf="loading" class="state">Cargando…</div>
  <div *ngIf="error" class="state error">No se pudo cargar el dashboard.</div>

  <ng-container *ngIf="data && !loading && !error">
    <div class="kpi-card">
      <div class="kpi-value">{{ data.dispensations }}</div>
      <div class="kpi-label">Dispensaciones</div>
      <div class="kpi-delta" [ngClass]="deltaClass" *ngIf="deltaLabel">{{ deltaLabel }} <span class="ref">vs. período anterior</span></div>
    </div>

    <div class="chart-wide"><h3>Tendencia de dispensaciones</h3><p-chart type="line" [data]="trendChart" [options]="trendOpts"></p-chart></div>

    <div class="chart-row">
      <div class="chart-box"><h3>Top medicamentos</h3><p-chart type="bar" [data]="topMedsChart" [options]="barHOpts"></p-chart></div>
      <div class="chart-box" *ngIf="isAdmin"><h3>Dispensaciones por sucursal</h3><p-chart type="doughnut" [data]="branchChart" [options]="pieOpts"></p-chart></div>
    </div>
  </ng-container>
</div>
```
- [ ] **Step 3: SCSS** (responsive, sin scroll horizontal — mismo criterio que el de Gestión):
```scss
:host { display:block; max-width:100%; }
.dashboard { padding:16px; box-sizing:border-box; overflow-x:hidden; }
.dashboard *, .dashboard *::before, .dashboard *::after { box-sizing:border-box; }
.period-bar { display:flex; gap:8px; align-items:center; flex-wrap:wrap; margin-bottom:16px; }
.period-bar .preset { border:1px solid #cfd8e3; background:#fff; border-radius:6px; padding:6px 12px; cursor:pointer; }
.period-bar .preset.on { background:#22a06b; color:#fff; border-color:#22a06b; }
.period-bar .custom { display:flex; gap:8px; flex-wrap:wrap; }
.kpi-card { display:inline-block; min-width:200px; background:#fff; border:1px solid #e5e9ef; border-radius:8px; padding:16px; margin-bottom:16px; }
.kpi-value { font-size:28px; font-weight:700; color:#243; } .kpi-label { font-size:12px; color:#789; }
.kpi-delta { font-size:12px; font-weight:600; margin-top:6px; } .kpi-delta.up{color:#1a8f5a} .kpi-delta.down{color:#c0392b} .kpi-delta.flat{color:#94a3b8}
.kpi-delta .ref { color:#a0aab5; font-weight:400; }
.chart-wide, .chart-box { background:#fff; border:1px solid #e5e9ef; border-radius:8px; padding:12px; margin-bottom:16px; min-width:0; overflow:hidden; display:flex; flex-direction:column; }
.chart-wide h3, .chart-box h3 { margin:0 0 8px; font-size:14px; }
.chart-wide { height:300px; } .chart-box { height:320px; }
.chart-row { display:grid; grid-template-columns:repeat(auto-fit, minmax(320px,1fr)); gap:16px; }
.chart-wide ::ng-deep p-chart, .chart-box ::ng-deep p-chart { display:block; position:relative; flex:1 1 auto; min-height:0; width:100%; }
.dashboard ::ng-deep canvas { max-width:100% !important; }
.state { padding:24px; text-align:center; color:#789; } .state.error { color:#c0392b; }
```
- [ ] **Step 4: Commit** (compila al declararlo en Task 5)
```bash
git add src/app/pages/application/home/dashboard
git commit -m "feat(dashboard-farmacia): DashboardComponent (dispensaciones, scope por rol)"
```

---

### Task 5: Landing por-rol + wiring

**Files:**
- Create `src/app/pages/application/home/landing-redirect/landing-redirect.component.ts`
- Modify `home.module.ts`, `home-routing.module.ts`, `components/sidebar/sidebar.component.html`

- [ ] **Step 1: LandingRedirectComponent** (sin template; redirige por rol):
```typescript
import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { filter, take } from 'rxjs/operators';
import { AuthService } from '../../../../services/auth.service';

@Component({ selector: 'app-landing-redirect', template: '' })
export class LandingRedirectComponent implements OnInit {
  constructor(private authService: AuthService, private router: Router) {}
  ngOnInit(): void {
    this.authService.getCurrentUser().pipe(filter(u => !!u), take(1)).subscribe({
      next: (user: any) => {
        const target = user.role === 'ROLE_PHARMACY_ADMIN' ? ['dashboard'] : ['prescriptions/search'];
        this.router.navigate(target);
      },
      error: () => this.router.navigate(['prescriptions/search']),
    });
  }
}
```

- [ ] **Step 2: home.module.ts** — importar `ChartModule` y declarar los componentes:
```typescript
import { ChartModule } from 'primeng/chart';
import { DashboardComponent } from './dashboard/dashboard.component';
import { LandingRedirectComponent } from './landing-redirect/landing-redirect.component';
```
Agregar `DashboardComponent, LandingRedirectComponent` a `declarations` y `ChartModule` a `imports`.

- [ ] **Step 3: home-routing.module.ts** — importar los componentes; cambiar el child de path vacío de `redirectTo: 'prescriptions/search'` a `component: LandingRedirectComponent` (quitar `pathMatch: 'full'` ya que ahora es un componente, o dejar `pathMatch: 'full'` con component — mantener `path: ''` y `component: LandingRedirectComponent`); agregar la ruta `{ path: 'dashboard', component: DashboardComponent }`.
```typescript
import { DashboardComponent } from './dashboard/dashboard.component';
import { LandingRedirectComponent } from './landing-redirect/landing-redirect.component';
```
Reemplazar el child vacío:
```typescript
      { path: '', component: LandingRedirectComponent, pathMatch: 'full' },
      { path: 'dashboard', component: DashboardComponent },
```

- [ ] **Step 4: sidebar.component.html** — agregar ítem "Dashboard" (visible para ambos roles; `userRole` ya existe en el componente desde A1):
```html
        <li class="nav-item" *ngIf="userRole === 'ROLE_PHARMACY' || userRole === 'ROLE_PHARMACY_ADMIN'">
            <a class="nav-link" routerLink="dashboard" routerLinkActive="active" (click)="closeSidebar()">
                <i class="fas fa-chart-line"></i> <span>Dashboard</span>
            </a>
        </li>
```

- [ ] **Step 5: Build** — Run: `npx ng build` · Expected: build OK.
- [ ] **Step 6: Verificación manual** — login admin → cae en dashboard (consolidado de cadena + por sucursal); login farmacia normal → landing actual, "Dashboard" en menú con datos de su sucursal (sin "por sucursal").
- [ ] **Step 7: Commit**
```bash
git add src/app/pages/application/home/landing-redirect \
        src/app/pages/application/home/home.module.ts \
        src/app/pages/application/home/home-routing.module.ts \
        src/app/pages/application/home/components/sidebar/sidebar.component.html
git commit -m "feat(dashboard-farmacia): landing por-rol + ruta + menú + ChartModule"
```

---

## Smoke test end-to-end (post-deploy)

- [ ] `GET /api/dashboard/pharmacy-summary?pharmacyId=<id>&startDate&endDate` (JWT farmacia) → dispensations+delta, trend, topMedicines, byBranch vacío.
- [ ] `GET /api/dashboard/pharmacy-summary?franchiseId=<id>&startDate&endDate` (JWT admin) → byBranch con sucursales.
- [ ] Admin entra → dashboard por defecto; farmacia normal → dashboard por menú.

## Criterios de éxito (del spec)

- [ ] Endpoint devuelve dispensaciones+delta, tendencia, top medicamentos y (con franchiseId) por sucursal.
- [ ] Admin cae por defecto en el dashboard de su cadena con desglose por sucursal.
- [ ] Farmacia normal ve su dashboard por menú (sin "por sucursal").
- [ ] Nombres de medicamento resueltos (incl. AMPP).
- [ ] `./gradlew build` y `ng build` en verde; `DashboardPharmacySummaryTest` en verde.

## Self-review (hecho)

- **Cobertura del spec:** endpoint scopeado (Tasks 1-2), KPIs dispensaciones+delta/tendencia/top/por-sucursal (Task 2 + Task 4), landing por-rol (Task 5), reuso DNMA/buildTrend/buildTopMedicines (Task 2). ✅
- **Sin placeholders:** código completo; reusos (`buildTopMedicines`, `buildTrend`, `nz`, DTOs) referencian símbolos existentes verificados. ✅
- **Consistencia:** `getPharmacySummary(String,String,LocalDate,LocalDate)` igual en interface/impl/controller/test; `PharmacySummaryResponse` campos = modelo TS; scope `{pharmacyId|franchiseId}` consistente front↔back. ✅
- **Fuera de alcance respetado:** sin KPIs de prescripciones, sin export, sin tocar `/summary`. ✅
