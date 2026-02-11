# Changelog

All notable changes to this project will be documented in this file.

## v1.0.4 - 2026-02-11
- CI: added workflow `concurrency` with `cancel-in-progress` to deduplicate long runs for the same SHA/ref
- CI: added `timeout-minutes` to build job for safer multi-arch execution
- CI: enabled Buildx cache (`cache-from` / `cache-to`) for GH Actions
- CI: upgraded `docker/build-push-action` from `v5` to `v6`
- Docker: removed `dist-upgrade`; switched apt installs to `--no-install-recommends` in build/runtime stages
- Docker context: expanded `.dockerignore` to reduce CI build context noise
- Relay logs: on successful `/event` responses, parse `sentCount` and log semantic outcome for `fan-out > 0` vs `fan-out = 0` with event metadata

## v1.0.3 - 2026-02-11
- Database: added `AddUpsAliasToDevice` migration to align `devices` schema with `Device` model
- Tests: updated `test-auth.sh` to use `/v1/*` routes and include `apiVersion` for register-device
- Docs: fixed `VolteecShared` pin in README (`from: 1.0.2`)
- Docker: pinned public compose image from `latest` to explicit release tag (`v1.0.3`)
- CI: added smoke workflow for fresh DB setup (`db -> migrate -> app -> register-device`)

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
