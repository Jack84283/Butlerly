# Butlerly Flutter app

This directory contains the Butlerly local-first Flutter application.

For repository setup, SDK versions, testing, and validation, start with
[the repository README](../../README.md) and [the contributor/agent guide](../../AGENTS.md).

The Flutter UI is implemented under `lib/`. Local-only financial data and business
behavior are implemented through the shared finance domain, application, and
database packages in `../../packages/`.

The application supports phone, tablet, and desktop layouts, and local English,
Spanish, and Simplified Chinese interfaces. Core functions run without an
account or cloud service.

For the current UI, consult the application theme and shared components in
`lib/design_system/`, together with approved, current versioned task
references. Historical design-board screenshots and older QA reports must not
override subsequently approved implementation decisions.
