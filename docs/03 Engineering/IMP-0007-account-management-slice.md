# IMP-0007 — Account Management

Status: Active local financial payment-source slice

## Scope

- Local financial payment sources only: account, card, cash, wallet, and other
- SQLite-backed save/list/archive lifecycle through application services
- Explicit transaction-to-payment-source assignment
- Local payment-source filtering after payment-source management is available

## Explicit exclusions

- User identity, sign-in, cloud accounts, synchronization, device trust, and pairing
- Binary evidence ownership remains with IMP-0009

## Verification

- Application-service coverage for save/list/archive, transaction assignment, and query filtering
- Flutter analysis and widget suite

## Next non-UI work

Add failure-path coverage for payment-source lifecycle and transaction assignment before expanding UI behavior.
