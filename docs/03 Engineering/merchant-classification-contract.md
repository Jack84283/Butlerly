# Merchant Classification Contract

Status: Active Butlerly domain/engineering contract

## Purpose

Keep merchant-driven transaction classification simple, deterministic, and scalable while allowing explicit service or business-context variants such as Costco Gas or AT&T Wireless.

## Core classification rule

Butlerly uses one default financial classification per merchant:

**Merchant → Subcategory → Category**

A merchant record does not own multiple simultaneous category mappings. A transaction may still be corrected by the user, but the built-in merchant default remains singular and deterministic.

## Broad merchants remain valid

Broad merchants such as AT&T, Safeway, Costco, CVS, Walmart, Amazon, and Target remain valid merchant identities and must not be replaced merely because more specific variants are introduced.

When only the broad merchant can be identified, Butlerly uses that merchant's broad default classification.

## Specific merchant variants

Create a separate built-in merchant identity when the transaction descriptor represents a materially different and stable financial context with a predictable classification.

Examples:

- AT&T Internet → Utilities → Internet
- AT&T Wireless → Utilities → Mobile Phone
- Safeway Pharmacy → Health → Pharmacy & Prescriptions
- CVS Pharmacy → Health → Pharmacy & Prescriptions
- Costco Pharmacy → Health → Pharmacy & Prescriptions
- Costco Gas → Transportation → Fuel
- Walmart Pharmacy → Health → Pharmacy & Prescriptions

Do not create merchant variants solely for store numbers, locations, terminal identifiers, or inconsequential descriptor formatting.

Examples that should normalize to the same merchant rather than become separate merchants:

- Costco #1234
- COSTCO WHSE 1234
- Costco Wholesale Store 1234

## Matching precedence

When transaction evidence supports more than one merchant identity, use the most specific reliable identity:

1. Specific merchant variant
2. Broad merchant
3. Uncategorized / unresolved merchant

Examples:

- COSTCO GAS #0123 → Costco Gas → Fuel → Transportation
- COSTCO PHARMACY #0123 → Costco Pharmacy → Pharmacy & Prescriptions → Health
- COSTCO WHSE #0123 → Costco → its broad default classification

Specificity must come from source evidence. Butlerly must not invent a specific merchant variant when the descriptor, receipt, or user input does not support it.

## Descriptor aliases and normalization

A merchant identity may have multiple raw statement, receipt, or OCR descriptors. Those strings are aliases or normalized matches, not additional merchant records unless their financial meaning is materially different.

Conceptual pipeline:

**Raw descriptor → normalized merchant identity → subcategory → category**

Examples:

- AT T WIRELESS / ATT MOBILITY → AT&T Wireless
- COSTCO GAS #0123 → Costco Gas
- SAFEWAY PHARMACY 1234 → Safeway Pharmacy

Alias/descriptor matching may be implemented separately from the merchant table. It must preserve the single-default-classification rule above.

## User control

Built-in merchant classifications are defaults, not immutable truth.

- Users may change the merchant or category on a transaction.
- User-created merchants remain supported.
- Butlerly must not silently overwrite user-created master data.
- Broad-but-correct is preferred over precise-but-guessed.

## Built-in catalog ownership and upgrades

The packaged database catalog remains the runtime source of truth for Butlerly-owned built-in merchant records.

Adding a new merchant row is compatible with idempotent seeding. However, changing an existing built-in merchant's name, status, category, or subcategory must not rely on `INSERT OR IGNORE` to update already-installed databases.

Any future change to an existing built-in merchant must use an explicit catalog upgrade or database migration path with production-path migration tests.

## Non-goals

This contract does not introduce:

- many-to-many merchant/category mappings;
- split transactions;
- automatic allocation of one transaction across multiple categories;
- merchant identities for every physical store location;
- a requirement to enumerate every restaurant or small business in the seed catalog.

Long-tail merchants should be learned or created from user data when encountered.
