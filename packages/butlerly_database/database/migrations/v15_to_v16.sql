-- Store payment network/provider separately from the issuing institution.
ALTER TABLE payment_sources ADD COLUMN network TEXT;
