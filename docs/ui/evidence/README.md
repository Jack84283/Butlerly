# Issue #386 evidence notes

This directory documents the visual evidence boundary for the audit.

Checked-in rendered PNG anchors (not currently wired through `matchesGoldenFile`):

- [Home dark, 390×844](../../../apps/butlerly/test/app/goldens/home_dark_390x844.png)
- [Analysis empty, 390×844](../../../apps/butlerly/test/features/analysis/goldens/analysis_empty_390x844.png)

The live Flutter inspection used DTD/widget inspection and reached `ButlerlyLaunchSurface` with a `CircularProgressIndicator`; no runtime error was reported. The iPhone simulator did not reach the main shell during the capture window, and its screenshot was black. That output is intentionally not committed or used as visual proof. A follow-up capture harness should seed a deterministic local state, navigate to known routes, wait for a bounded readiness signal, and capture both themes across iPhone, iPad, and desktop.
