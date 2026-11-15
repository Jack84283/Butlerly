# Butlerly Alpha — legal publication checklist (internal)

Status: **NOT APPROVED FOR EXTERNAL DISTRIBUTION**. The in-app LEG-0001–0004 texts are concise v1.2 review previews, not effective legal agreements. This checklist is for the repository/release team and must not be bundled in the in-app Legal & Licenses reader.

## Decision: private testing versus release

- Personal development and testing on an owner's own device: no external counsel sign-off is inherently required just to continue this testing. Keep privacy and data security in mind.
- Invitation-only external Alpha: identify the actual tester audience and distribution process, decide whether separate tester terms or consent are needed, and consider counsel review. No universal lawyer-approval claim is made.
- Public distribution: obtain responsible human sign-off. Qualified legal advice is recommended for Terms, privacy compliance and unusual licenses. Comply with rules in each distribution region; a generic template is insufficient.

## Publication blockers (Issue #380)

- [ ] Confirm publisher/rightsholder identity and legal contact channel; use only real verified information. Confirm any postal contact requirements and public support contact.
- [ ] Decide release regions, age eligibility, distribution channels, effective date, and the scope of any additional Alpha tester conditions.
- [ ] Approve enforceable Terms and any liability, governing-law or dispute provisions *only after* jurisdiction-specific review. Do not silently add arbitration, waiver, indemnity, age promises or a monetary cap.
- [ ] Review full exact release binaries and permissions for actual network traffic, crash reporting, third-party SDKs, OCR/AI, currency rates, OS/cloud backup behavior, data sharing, and any unexpected remote features.
- [ ] Update the Privacy Policy to accurately identify actual processors/recipient categories, purposes, retention/deletion, security practices, user rights/contact methods and any applicable regional requirements. Do not claim zero collection or zero transmission without evidence.
- [ ] If distributing through the App Store or Google Play, publish a stable, public, accessible HTTPS Privacy Policy webpage, link it in store metadata and the app, and provide accurate privacy/data-safety disclosures and support information.
- [ ] Produce a verified license and attribution inventory from the *frozen exact build*: resolved Dart/Flutter packages, Android/iOS/macOS native dependencies, icons, sounds, fonts, images, models, bundled assets and tooling included in the binary.
- [ ] Preserve all required original third-party copyright texts, licenses, attribution, source offers and modification notices; summaries or translations are not substitutes for those obligations. Resolve any restricted licenses before distribution.
- [ ] Review all four documents for factual and legal accuracy in English, Simplified Chinese and Spanish, including native-language proofreading.
- [ ] Confirm the final version/build SHA, in-app offline accessibility, copy/layout, device readers, privacy screens, local backup/export warnings and any required release consent.
- [ ] Approve final published text, remove review banners, insert verified publication details, document sign-off and release version; do not treat a merged documentation PR as publication authorization.

## Editorial decisions for v1.2

Keep in the user-facing drafts:
- What Butlerly currently does; offline-first/local import limits
- Accurate categories of data and purposes
- User-controlled export, plain-text exposure, backup/restore and deletion limits
- Potential extraction/analysis errors and informational nature of insights
- Third-party license rights and status of incomplete inventory

Remove from the user-facing drafts (track here instead):
- Repeated internal instructions to engineers and legal counsel
- Unapproved future monetization, online sync, external AI services and unrelated hypothetical features
- Placeholder governing-law, arbitration, liability-cap, indemnity and eligibility clauses
- Duplicate long descriptions of the same local-first data flow
- Unverified guarantees about privacy, processing, backups or security

References:
- https://github.com/Jack84283/Butlerly/issues/380
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- https://support.google.com/googleplay/android-developer/answer/10144311

The v1.1 Git history preserves the earlier editorial review drafts. No legal sign-off is implied by simplification.
