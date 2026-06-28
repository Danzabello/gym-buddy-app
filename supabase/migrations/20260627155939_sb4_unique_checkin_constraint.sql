-- SB-4 / DI-2: DB-level backstop against double check-ins. The
-- client-side dedup (DI-2's _isCheckingIn flag) only stops same-device
-- double-taps; this stops the race at the actual data layer regardless
-- of source (client bug, retry, concurrent devices).
--
-- Note: the audit's other SB-4 suggestion (a coin_transactions
-- uniqueness constraint on user_id/transaction_type/date) is now
-- superseded by tonight's S2/S3 redesign -- coin dedup is handled via
-- reference_id checks inside the SECURITY DEFINER reward functions,
-- which correctly allow multiple 'daily_checkin' entries per day
-- (one per team/streak). A blanket per-day-per-type constraint would
-- incorrectly block that legitimate multi-team scenario, so skipping it.
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_team_checkins_unique
ON public.daily_team_checkins (team_streak_id, user_id, check_in_date);
