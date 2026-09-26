# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working across the Recetalia workspace.

## Workspace Overview

Monorepo de 7 proyectos independientes (cada uno con su propio `.git`) que componen la plataforma Recetalia (receta digital, Chile/Uruguay):

- **4 frontends Angular 18.x SSR** — uno por perfil de usuario.
- **3 APIs Spring Boot 3.x / Java 21** — core business, seguridad, y un servicio transversal WebFlux.

Cada subproyecto tiene su propio [CLAUDE.md](.) con detalle de stack, comandos y arquitectura. Para el mapa entre proyectos ver [doc/architecture-overview.md](doc/architecture-overview.md).

## Proyectos

| Proyecto | Tipo | Rol de usuario | Stack resumido |
|---|---|---|---|
| [farmacias-recetalia-app/](farmacias-recetalia-app/) | Frontend | `ROLE_PHARMACY` | Angular 18.2 SSR + NgModule |
| [medics-recetalia-app/](medics-recetalia-app/) | Frontend | Médico | Angular 18.2 SSR + NgModule |
| [medical-provider-app/](medical-provider-app/) | Frontend | Provider médico | Angular 18.1 SSR + NgModule |
| [gestion-recetadigital-app/](gestion-recetadigital-app/) | Frontend | `ROLE_MANAGEMENT` | Angular 18.2 SSR + NgModule |
| [recetalia-api-rest/](recetalia-api-rest/) | API | — | Spring Boot 3.3.0 + JPA/MySQL |
| [security-api-recetalia/](security-api-recetalia/) | API | — | Spring Boot 3.3.4 + JPA/MySQL (puerto 8091) |
| [transversal-recetalia-api/](transversal-recetalia-api/) | API | — | Spring Boot 3.4.1 + WebFlux + R2DBC (puerto 8093) |

## Cómo trabajar en este workspace

1. Cada proyecto se construye y testea con sus propios comandos — no hay build cross-proyecto.
2. Antes de tocar un proyecto, leer su `CLAUDE.md` y los docs en su `doc/specs/`.
3. Para cambios que afecten el contrato entre apps y APIs, consultar primero [doc/architecture-overview.md](doc/architecture-overview.md).
4. Los planes de implementación multi-proyecto van en [doc/plans/](doc/plans/).
