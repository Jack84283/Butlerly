-- Optional transaction save success sound. Enabled by default for upgrades.
ALTER TABLE user_preferences ADD COLUMN transaction_save_sound_enabled INTEGER NOT NULL DEFAULT 1 CHECK(transaction_save_sound_enabled IN (0, 1));
