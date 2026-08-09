# IMP-0001 — Project initialization and foundation

Status: Implemented locally

## Scope

This milestone establishes the Butlerly application foundation without finance workflows, authentication, cloud synchronization, or live AI integration.

## Foundation delivered

- Cross-platform Flutter application shell
- Clean separation between app composition, cross-cutting core services, and feature presentation
- Riverpod state foundation, GetIt composition root, and GoRouter navigation
- Adaptive phone, tablet, and desktop navigation
- Material 3 light, dark, and system themes
- Localization delegate infrastructure
- Local SQLite initialization with schema metadata and a web-safe unavailable state
- Structured local logging and uncaught-error handling
- Widget and database tests
- GitHub Actions validation for formatting, analysis, tests, and web build

## Intentional limits

- No finance domain objects or workflows
- No account or authentication requirement
- No remote services, synchronization, or telemetry
- No AI implementation beyond preserving room for a future optional provider boundary
- No shared packages until a real reusable capability requires one

## Next milestone

IMP-0002 — Finance Domain Foundation
