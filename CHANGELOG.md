# Changelog

All notable changes to this project will be documented in this file.

## v1.0.2 - 2026-02-09
- Relay: fail-loud config validation (UUID checks) + better logging for non-2xx Relay responses (status + request id + redacted body)
- Relay: internal-only production target switch (`VOLTEEC_DEPLOYMENT=production`)
- Docs: removed hard-coded examples; added Operator guide ("What working means"), Cleanup/Uninstall section, and AI Setup Assistant prompt
- Docs: aligned `AUTH_IMPLEMENTATION.md` with `/v1/*` routes and degraded-mode behavior
- CI: inject build metadata into Docker images at build time (version/commit/date)

## v1.0.0 - 2026-01-31
- Initial public backend release (V1)
- NUT polling + canonical mapping, offline handling
- UPS/device models + migrations
- REST API `/v1/*` + SSE `/v1/events`
- Auth middleware + rate limiting
- Relay integration for push fan-out
- Optional APNs support
- Metrics endpoint (`/metrics`)
