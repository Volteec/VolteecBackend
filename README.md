# Volteec Backend

**v0.1.0 (2026-01-06)** — Swift 6.1 / Vapor 4.115.0 — V1.1 local backend with NUT polling (phase 1)

Local, self-hosted backend for UPS monitoring (NUT/SNMP). Aligned to the canonical backend document and Task-DevOps-003.

**README language:** English only. All backend text, comments, and commit messages must be English.

## Status

Current version: v0.1.0 (2026-01-06) — Swift 6.1 / Vapor 4.115.0.  
Current content: auth middleware, Postgres models/migrations (ups/devices + NUT fields), REST endpoints, SSE stream, NUT TCP polling with canonical mapping.  
Planned content: SNMP polling, APNs push (owner-only tests in V1.1; public builds disabled), SSE updates tied to real-time polling.

### Patch History

**v0.1.0 (2026-01-06) — NUT polling (phase 1)**  
- NUT TCP client + poller, env config, canonical mapping, offline handling, extended metrics persisted

**v0.0.1 (2026-01-06) — initial skeleton**  
- Placeholder structure only (no business logic)

---

## Principles

- **Canonical-first**: scope and API follow `Volteec Backend/Volteec-Backend-Canonical.md`.
- **Docker-first**: backend runs in Docker; local development uses docker-compose.
- **Postgres for V1.1**: minimal DB for `ups` and `devices`.
- **Phase 1 (NUT-only)**: NUT TCP polling enabled; SNMP deferred.
- **English-only backend**: text, comments, and commits must be in English.

## Setup

This backend runs locally/self-hosted and is intended for single-instance deployment.

### Requirements
- Docker + Docker Compose
- Postgres (via docker-compose)

### Quick Start (Docker)
1) Copy `.env.example` to `.env` and fill required values.
2) Run migrations:
   - `docker compose run migrate`
3) Start backend:
   - `docker compose up app`

### Health & Readiness
- `GET /health` — liveness (always available)
- `GET /ready` — readiness (returns `not_ready` if API_TOKEN is missing or DB is unavailable)

### Auth behavior
- If `API_TOKEN` is missing, the server runs in **degraded mode**:
  - `/health` and `/ready` still work
  - `/v1/*` routes are disabled
  - logs a critical warning at boot

### CORS Policy
- Explicitly configured with `allowedOrigin = .none` (no cross-origin access).

### Metrics & Request IDs
- `GET /metrics` — Prometheus text format.
- `X-Request-ID` propagated on all responses when provided or generated.

### Verification (manual)
- Metrics: `curl -s http://localhost:8080/metrics | head`
- Request ID: `curl -s -H "X-Request-ID: test-123" http://localhost:8080/health -i` (expect `X-Request-ID: test-123`)

## Usage

Minimal usage (local):
- Configure NUT env vars (see below).
- Run backend; NUT polling starts if `NUT_HOST` is set.
- REST endpoints: `GET /ups`, `GET /ups/{upsId}/status`.
- SSE stream: `GET /events?rate=1s|3s|5s`.

Note: API responses currently expose the minimal fields (battery/runtime/load/input/output). Extended NUT fields are stored in the DB for future expansion.

## Configuration (NUT)

Required:
- `NUT_HOST` (host/IP)
- `NUT_UPS` (CSV list, e.g. `ups1,ups2`)

Optional:
- `NUT_PORT` (default: 3493)
- `NUT_USERNAME`
- `NUT_PASSWORD`
- `NUT_POLL_INTERVAL` (seconds, default: 1.0)

Behavior:
- UPS IDs are lowercased NUT names.
- Offline after 3 consecutive failures; metrics are cleared (null).

## Implemented Structure

```
Sources/VolteecBackend/
├── Controllers/
├── DTOs/
├── Models/
├── Migrations/
├── Services/
│   ├── NUT/
│   ├── SNMP/
│   ├── SSE/
│   └── Push/
├── Storage/
├── Utilities/
└── Config/
```

## Sources

- Canonical backend reference: `Volteec Backend/Volteec-Backend-Canonical.md`

## Version

- **Current**: v0.0.1
- **Platform**: Linux (Docker)
- **Swift**: 6.1

## Build Status

TBD

## Compatibility
- VolteecShared version is pinned in `Package.swift`.
- API versioning is `/v1/*` with response `apiVersion = "1.0"`.
