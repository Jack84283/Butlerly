# Analysis Implementation Source Manifest

**Version:** 1.0  
**Purpose:** Fixed handoff manifest for the Butlerly Finance V1 Analysis implementation work.

## Repository implementation snapshot

- `docs/implementation/IMP-0007-Rule-Based-Analysis-Engine-and-Insights-v1.0.md` — IMP-0007 v1.0 — Source status: Ready for implementation planning.

## Governing source chain

The editable source documents remain in Google Drive. Before an implementation issue is labeled `codex-ready`, their repository-approved status must satisfy `AGENTS.md`.

- PRD-0003 — Finance MVP v1.0 — product authority for Finance V1 scope and behavior.
- PRD-0004 — Domain Model — product/domain authority for canonical financial concepts.
- ARC-0405 — Rule-Based Analysis Engine Architecture — architecture authority for the deterministic declarative Analysis engine.
- ANL-0001 — Analysis Principles & Rule Model — currently marked **Draft for V1 implementation**.
- ANL-0002 — Built-in Financial Analysis Rule Catalog — currently marked **Draft for V1 implementation**.
- ANL-0003 — Analysis Dataset & Calculation Semantics — calculation semantics authority once approved.
- ANL-0004 — Analysis Experience & Interaction Contract — Analysis behavior/presentation contract once approved.
- ANL-0005 — Declarative Analysis Rule Schema — declarative YAML/schema contract referenced by IMP-0007.

## UX presentation chain

The Analysis UX documentation has been aligned through the presentation and validation layers:

- UX-0003 — Analysis information architecture and navigation relationship.
- UX-0004 — Analysis flows F19–F23.
- UX-0005 — Analysis screen/state inventory S-ANL-001 through S-ANL-007.
- UX-0010 — Analysis low-fidelity wireframe specification.
- UX-0011 — Analysis reusable presentation components and patterns.
- UX-0012 — Analysis usability/comprehension validation and release gates.
- BDS-0000 — concrete design-system implementation authority.

## Current implementation gate

Do **not** apply `codex-ready` while a governing Analysis document required for financial meaning remains Draft. The immediate blocker is the source status of ANL-0001 and ANL-0002. This is a governance/approval gate, not an invitation for Codex to infer or silently select financial semantics.

Once the governing Analysis source set is formally approved, update this manifest or create a reviewed successor version, then move the implementation issue to `codex-ready`.