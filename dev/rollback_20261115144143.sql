-- Rollback for 20261115144143_revoke_coach_max_schedule_insert.sql.
-- Gives authenticated its table-level INSERT on coach_max_schedule back, exactly as it was. The INSERT policy
-- (own rows) and the clamp trigger were never removed, so a client insert works again as before.
-- Safe to run twice.
-- After running it: supabase migration repair --status reverted 20261115144143 is NOT the next step (CLAUDE.md:
-- never revert existing versions); ask the owner how the history should record it.
GRANT INSERT ON public.coach_max_schedule TO authenticated;
