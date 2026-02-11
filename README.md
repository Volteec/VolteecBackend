# Volteec Backend

**v1.0.2 (2026-02-09)** — Swift 6.2 / Vapor 4.121.1 — V1 local backend with NUT polling

Local, self-hosted backend for UPS monitoring (NUT). Aligned to the canonical backend document and Task-DevOps-003.

**README language:** English only. All backend text, comments, and commit messages must be English.

## Status

Current version: v1.0.2 (2026-02-09) — Swift 6.2 / Vapor 4.121.1.  
Current content: auth middleware, rate limiting, Postgres models/migrations (ups/devices + NUT fields), REST endpoints, SSE stream, NUT TCP polling with canonical mapping, Relay integration.  
Planned content: SNMP polling (deferred).

### Patch History

**v1.0.2 (2026-02-09) — onboarding + relay diagnostics + docs alignment**  
- Relay: fail-loud config validation (UUID checks) + better logging for non-2xx Relay responses (status + request id + redacted body)  
- Relay: internal-only production target switch (`VOLTEEC_DEPLOYMENT=production`)  
- Docs: removed hard-coded examples; added Operator guide ("What working means"), Cleanup/Uninstall section, and AI Setup Assistant prompt  
- Docs: aligned `AUTH_IMPLEMENTATION.md` with `/v1/*` routes and degraded-mode behavior  
- CI: inject build metadata into Docker images at build time (version/commit/date)  

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
   - Note: `.env.example` starts with a dot, so it may be hidden in Finder. Enable “Show Hidden Files” (Cmd+Shift+.) or copy it from Terminal.
   - Important: `.env` contains secrets (`API_TOKEN`, `DEVICE_TOKEN_KEY`, `RELAY_TENANT_SECRET`). Treat it like a secret and never commit it.
   - Local Docker: keep `DATABASE_TLS_MODE=disable` (the default Postgres container has TLS off).
   - Production: set `DATABASE_TLS_MODE=require` and enable TLS on your Postgres server.
3) Run migrations:
   - First start the database and wait a few seconds:
     - `docker compose up -d db`
   - Then run migrations:
     - `docker compose run --rm migrate`
4) Start backend:
   - `docker compose up app`

This uses the **public GHCR image** (`ghcr.io/volteec/volteec-backend:latest`) by default.

### Public Docker Flow (Recommended)

```bash
git clone https://github.com/Volteec/VolteecBackend
cd VolteecBackend
cp .env.example .env
# edit .env (API_TOKEN, DEVICE_TOKEN_KEY, Relay + optional NUT, DATABASE_TLS_MODE)
docker compose run --rm migrate
docker compose up app
```

Note: On a fresh setup, Postgres may need a few seconds to initialize. If you see
`connection refused` when running migrations, start the DB first:
```bash
docker compose up -d db
docker compose run --rm migrate
```

## AI Setup Assistant (Copy/Paste Prompt)

Use this if you want minimal setup friction. It works on macOS/Windows/Linux and does not assume any specific AI tool.

**Prompt (Simple mode):**

```text
I cloned VolteecBackend and want to run it locally in Docker.

Goal: make it work end-to-end with the Volteec iOS app (URL + Token), and optionally with NUT (UPS polling) and Relay (push).

My inputs:
1) Relay credentials from the app:
   RELAY_TENANT_ID=<uuid>
   RELAY_TENANT_SECRET=<secret>
2) NUT host:
   NUT_HOST=<ip_or_host>
   (Optional) If my NUT server is only reachable via SSH tunnel (upsd listens on 127.0.0.1:3493):
   SSH_TUNNEL=<ssh_user>@<host>

Please do the following (be explicit and safe):
- Generate values I should not invent manually:
  - API_TOKEN (strong random)
  - DEVICE_TOKEN_KEY (base64, 32 bytes)
  - RELAY_SERVER_ID (UUID)
- Produce a complete .env file (no placeholders) that I can paste into VolteecBackend/.env.
- Give me the exact Docker commands to run (db -> migrate -> app).
- Provide verification commands and expected outputs:
  - GET /health, GET /ready
  - GET /v1/status (with Authorization: Bearer <API_TOKEN>)
  - GET /v1/ups (with Authorization)
- If SSH_TUNNEL is provided, output the SSH tunnel command I should run and explain that it must stay running.
- Do NOT suggest any destructive commands by default (docker compose down -v, docker system prune, etc.). If a full reset is needed, ask me to confirm first.
- If any required information is missing or ambiguous, say \"I DON'T KNOW\" and ask specific clarifying questions. Do not guess.
- Do not invent endpoints, environment variables, or commands that are not in this repo's docs. If unsure, ask me to paste the relevant file section.
- If a step fails, stop and ask me for the exact command output (copy/paste). Do not propose new fixes without data.

Output format:
1) .env contents
2) Commands to run (copy/paste)
3) Verification checklist (OK/FAIL)
4) What to paste into the iOS app (Server URL + Token)
```

### Required Environment Values

You must set these in `.env`:

- `API_TOKEN` — any strong random token (used for API auth)
- `DEVICE_TOKEN_KEY` — base64 **32 bytes** (AES‑256 key)
- Relay credentials (required for push):
  - `RELAY_TENANT_ID`
  - `RELAY_TENANT_SECRET`
  - `RELAY_SERVER_ID`

Generate tokens:

```bash
openssl rand -hex 32    # API_TOKEN
openssl rand -base64 32 # DEVICE_TOKEN_KEY
```

### Relay (Push Notifications)

Push notifications require Relay credentials. If Relay credentials are not set, push is disabled.
Relay URL and environment are internal-only and are fixed in code (not configurable via `.env`).

Relay credentials are issued by Volteec. If you do not have them, push notifications will not work.
`RELAY_TENANT_ID` must be a UUID (as provided by the app).
`RELAY_SERVER_ID` must be a stable UUID per backend instance (generate once with `uuidgen`).
Relay credentials are generated in the Volteec app (Settings → Help Center → How to Connect → Resources → Relay Credentials) and must be copied into the backend `.env`.

Internal deployments:
- `VOLTEEC_DEPLOYMENT=production` targets Relay production (`https://api.volteec.com/v1`, `environment=production`).
- If you need sandbox/dev Relay for local testing, unset `VOLTEEC_DEPLOYMENT` (or set any value other than `production`).

Example format (placeholders):
- `RELAY_TENANT_ID=<uuid>`
- `RELAY_TENANT_SECRET=<secret>`
- `RELAY_SERVER_ID=<uuid>`

### Local Development (Build from Source)

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build app
```

Stop the dev stack (keeps DB data):
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml down --remove-orphans
```

Full reset (deletes Postgres data):
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml down -v --remove-orphans
```

## What "Working" Means (Operator Guide)

This backend has three independent parts. It is possible for one to work while the others are misconfigured.

1) Backend is running (network + process):
- `GET /health` returns `ok`.

2) Backend is ready (DB + migrations + API token set):
- `GET /ready` returns `ready`.

3) API auth works (app connection):
- `GET /v1/status` succeeds with `Authorization: Bearer <API_TOKEN>`.

4) UPS data works (NUT configured + reachable):
- `GET /v1/ups` returns at least one UPS and `updatedAt` changes over time.

5) Push works (Relay credentials + connectivity):
- `POST /v1/relay/pair` succeeds.
- `POST /v1/register-device` succeeds (device token + environment from the app).

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

Note: On many NUT installations, `upsd` listens only on `127.0.0.1`. In that case, Docker
cannot connect directly; use port-forwarding (SSH tunnel) or expose `upsd` on `0.0.0.0`.

## Troubleshooting & FAQ

Q: I get `{"reason":"Something went wrong."}` on `GET /v1/ups`.  
A: Database migrations were not run, so tables do not exist. Run:
```bash
docker compose run --rm migrate
```

Q: Backend starts, but NUT times out.  
A: On many NUT installations, `upsd` listens only on `127.0.0.1:3493`, so Docker cannot reach it.
Fastest fix is an SSH tunnel:
```bash
ssh -L 3493:127.0.0.1:3493 user@nut-host
```
Then set:
- `NUT_HOST=host.docker.internal`
- `NUT_PORT=3493`
Keep the SSH session open.

Q: How do I find the UPS name(s) for `NUT_UPS`?  
A:
```bash
upsc -l localhost
```
Example output: `<ups_name_from_upsc>`

Q: UPS stays offline after changing `NUT_UPS`.  
A: The app may cache server/UPS state. Re-add the server or remove and add it again after updating `NUT_UPS`.

Q: `/health` works in Safari, but the app fails to connect.  
A: Common causes:
- Your phone/PC is not on the same LAN/Wi‑Fi as the backend host.
- Firewall blocks inbound access to the backend port (default `8080`).
- You used `localhost` from the phone. Use the backend host's LAN IP instead.
- The app cannot authenticate (invalid token / token format).

LAN connectivity test (from the same network as the backend host):
- `http://<BACKEND_LAN_IP>:8080/health`
- `http://<BACKEND_LAN_IP>:8080/ready`

Q: Push notifications do not work.  
A: Relay credentials (`RELAY_TENANT_ID` and `RELAY_TENANT_SECRET`) are generated in the Volteec app (Settings → Help Center → How to Connect → Resources → Relay Credentials) and cannot be generated locally.
If you do not have them, the backend still works, but push is disabled.

Q: I deleted the Postgres container, but old data is still there.  
A: Docker Compose uses a named volume (`db_data`), so deleting containers does not remove the database.
To reset the database completely (this deletes all data):
```bash
docker compose down -v --remove-orphans
docker compose up -d db
docker compose run --rm migrate
```

## Uninstall / Cleanup

This removes containers, networks, the persistent Postgres volume, and local secrets.

1) Stop the stack (keeps DB data):
```bash
docker compose down --remove-orphans
```

2) Full reset (deletes Postgres data):
```bash
docker compose down -v --remove-orphans
```

3) Remove local secrets file:
```bash
rm -f .env
```

Optional: stop SSH tunnel (if used for NUT):
- The SSH tunnel is a separate process. Stop it manually (Ctrl+C).

Optional: remove images:
```bash
docker image rm ghcr.io/volteec/volteec-backend:latest
```

Optional (aggressive, global): prune Docker resources:
- Warning: this may delete unrelated images/volumes used by other projects.
```bash
docker system prune -af
docker volume prune -f
```

## How to Connect (iOS app)

1. Server URL  
Use the backend host's LAN IP (or hostname) that is reachable from your phone on the same network. Example:
```
http://<BACKEND_LAN_IP>:8080
```
Note: The app normalizes the URL. If you omit `/v1`, the app will add it automatically.

2. API Token  
In the app, enter the **exact** `API_TOKEN` value from your backend `.env` in the Token field (Add Server).
Paste the token only (no `Bearer` prefix). The app adds `Authorization: Bearer ...` automatically.

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
  - Default is `disable` when not set (easier local setup).
  - Production: set `require` and enable TLS on your Postgres server.

### Relay (optional)
If any `RELAY_*` credential is set, all Relay credentials are required:
- `RELAY_TENANT_ID`
- `RELAY_TENANT_SECRET`
- `RELAY_SERVER_ID`
Note: Relay URL and environment are fixed in code (internal-only).

### Backend versioning
Backend version strings are set at build time (not via `.env`).

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

- **Current**: v1.0.2 (2026-02-09)
- **Platform**: Linux (Docker)
- **Swift**: 6.2
- **Vapor**: 4.121.1

## Build Status

Not configured.

## Compatibility
- VolteecShared version is pinned in `Package.swift` (`from: 1.0.0`).
- API versioning is `/v1/*` with response `apiVersion = "1.0"`.

## Support & Contact

- Support (setup/usage issues): support@volteec.com
- General contact: contact@volteec.com
- Security vulnerabilities: security@volteec.com (see `SECURITY.md`)
