# Volteec Backend

**v1.0.0 (2026-01-31)** — Swift 6.2 / Vapor 4.121.1 — V1 local backend with NUT polling

Local, self-hosted backend for UPS monitoring (NUT). Aligned to the canonical backend document and Task-DevOps-003.

**README language:** English only. All backend text, comments, and commit messages must be English.

## Status

Current version: v1.0.0 (2026-01-31) — Swift 6.2 / Vapor 4.121.1.  
Current content: auth middleware, rate limiting, Postgres models/migrations (ups/devices + NUT fields), REST endpoints, SSE stream, NUT TCP polling with canonical mapping, Relay integration.  
Planned content: SNMP polling (deferred).

### Patch History

**v1.0.0 (2026-01-31) — V1 backend release**  
- NUT TCP client + poller, env config, canonical mapping, offline handling, extended metrics persisted  
- Auth middleware + rate limiting  
- SSE stream + /metrics  
- Relay integration for push fan-out  

**v0.0.1 (2026-01-06) — initial skeleton**  
- Placeholder structure only (no business logic)

---

## Principles

- **Canonical-first**: scope and API follow `Volteec Backend/Volteec-Backend-Canonical.md`.
- **Docker-first**: backend runs in Docker; local development uses docker-compose.
- **Postgres for V1**: minimal DB for `ups` and `devices`.
- **Phase 1 (NUT-only)**: NUT TCP polling enabled; SNMP deferred.
- **English-only backend**: text, comments, and commits must be in English.

## Setup

This backend runs locally/self-hosted and is intended for single-instance deployment.

### Requirements
- Docker + Docker Compose (Docker Desktop on macOS/Windows)
- Postgres (via docker-compose)

### Quick Start (Docker)
1) Clone the repo.
2) Copy `.env.example` to `.env` and fill required values.
3) Run migrations:
   - `docker compose run --rm migrate`
4) Start backend:
   - `docker compose up app`

This uses the **public GHCR image** (`ghcr.io/volteec/volteec-backend:latest`) by default.

### Public Docker Flow (Recommended)

```bash
git clone https://github.com/Volteec/VolteecBackend
cd VolteecBackend
cp .env.example .env
# edit .env (API_TOKEN, DEVICE_TOKEN_KEY, optional NUT/RELAY)
docker compose run --rm migrate
docker compose up app
```

### Local Development (Build from Source)

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build app
```

### Health & Readiness
- `GET /health` — liveness (always available)
- `GET /ready` — readiness (returns `not_ready` if API_TOKEN is missing or DB is unavailable)

### Auth behavior
- If `API_TOKEN` is missing, the server runs in **degraded mode**:
  - `/health` and `/ready` still work
  - `/v1/*` routes are disabled
  - logs a critical warning at boot

### Rate limiting
- `/v1/*` routes are rate limited per IP (default: 60 requests/minute).  
  V1 uses in-memory limits (single-instance). If you deploy behind a reverse proxy, add external rate limiting there too.

### CORS Policy
- Explicitly configured with `allowedOrigin = .none` (no cross-origin access).

### Metrics & Request IDs
- `GET /metrics` — Prometheus text format.
- `X-Request-ID` propagated on all responses when provided or generated.

### Verification (manual)
- Metrics: `curl -s http://localhost:8080/metrics | head`
- Request ID: `curl -s -H "X-Request-ID: test-123" http://localhost:8080/health -i` (expect `X-Request-ID: test-123`)

### NUT over SSH Tunnel (macOS/Windows Docker)

If you run Docker on macOS/Windows and use an SSH tunnel to a NUT host:
- Start tunnel on the host machine:
  - `ssh -L 3493:127.0.0.1:3493 user@nut-host`
- Set in `.env`:
  - `NUT_HOST=host.docker.internal`
  - `NUT_PORT=3493`

## Usage

Minimal usage (local):
- Configure env vars (see below).
- Run backend; NUT polling starts if `NUT_HOST` is set.
- REST endpoints (all under `/v1`, protected by `API_TOKEN`):
  - `GET /v1/ups`
  - `GET /v1/ups/{upsId}/status`
  - `POST /v1/register-device`
  - `POST /v1/unregister-device`
  - `POST /v1/relay/pair`
  - `GET /v1/events?rate=1s|3s|5s`
  - `GET /v1/status`
- Public endpoints:
  - `GET /health`
  - `GET /ready`
  - `GET /metrics`

Note: `POST /v1/status/simulate-push` is available only when `ENVIRONMENT != production`.

Note: API responses currently expose the minimal fields (battery/runtime/load/input/output). Extended NUT fields are stored in the DB for future expansion.

## Configuration

### Core (required)
- `API_TOKEN` (required for `/v1/*` routes)
- `DEVICE_TOKEN_KEY` (required; AES-256 key, base64, 32 bytes)

### Database
- `DATABASE_HOST`
- `DATABASE_PORT`
- `DATABASE_USERNAME`
- `DATABASE_PASSWORD`
- `DATABASE_NAME`
- `DATABASE_TLS_MODE` (optional; `require` | `prefer` | `disable`)

### Relay (optional)
If `RELAY_URL` is set, all other `RELAY_*` variables are required:
- `RELAY_URL`
- `RELAY_TENANT_ID`
- `RELAY_TENANT_SECRET`
- `RELAY_SERVER_ID`
- `RELAY_ENVIRONMENT` (`sandbox` | `production`, optional)

### Backend versioning (optional)
- `BACKEND_PROTOCOL_VERSION` (default: `1.1`)
- `BACKEND_SOFTWARE_VERSION` (default: `1.1.0`)

### NUT (optional; enables polling)
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

## Operations (Production)

### Retention
- Backend telemetry retention is controlled by the backend operator (self-hosted).
- If you store UPS telemetry long-term, document your retention period in your own policy.

### Backups
- Use regular Postgres backups (daily recommended).
- Store backups encrypted and off-host.
- Test restore procedures periodically.

### TLS + Firewall
- TLS should be enforced at the reverse proxy or load balancer.
- Restrict database access to the backend host only.
- Expose only the backend HTTP port (default 8080) to trusted networks.

## Implemented Structure

```
Sources/VolteecBackend/
├── Controllers/
├── DTOs/
├── Models/
├── Migrations/
├── Services/
│   ├── Compatibility/
│   ├── Events/
│   ├── Metrics/
│   ├── NUT/
│   ├── Relay/
│   ├── SSE/
│   └── SNMP/ (reserved; not implemented in V1)
├── Storage/
├── Utilities/
└── Config/
```

## Sources

- Canonical backend reference: `Volteec Backend/Volteec-Backend-Canonical.md`

## Version

- **Current**: v1.0.0 (2026-01-31)
- **Platform**: Linux (Docker)
- **Swift**: 6.2
- **Vapor**: 4.121.1

## Build Status

Not configured.

## Compatibility
- VolteecShared version is pinned in `Package.swift` (`from: 1.0.0`).
- API versioning is `/v1/*` with response `apiVersion = "1.0"`.
