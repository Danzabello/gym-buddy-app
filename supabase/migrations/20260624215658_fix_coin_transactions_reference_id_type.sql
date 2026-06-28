-- coin_transactions.reference_id was uuid while xp_transactions.reference_id
-- is text. The new reward RPCs pass composite/non-UUID reference strings
-- (e.g. 'streak_id:date', 'achievement_first_rep'), which broke every
-- award_coins() call inside a transaction, rolling back the XP award
-- alongside it. Align the column type with xp_transactions (text).
-- Existing data is all valid UUIDs or null, so this is a lossless cast.
ALTER TABLE public.coin_transactions ALTER COLUMN reference_id TYPE text USING reference_id::text;
