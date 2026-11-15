-- Rollback for 20261115140911_are_on_break_today.sql.
-- Drops the one function the migration added. Nothing is lost: it stores no data. A build that calls it shows no
-- break badges on buddies until it is back (the client treats a failed call as "nobody on a break").
-- Safe to run twice and on a database that never had the function.
-- After running it: supabase migration repair --status reverted 20261115140911 is NOT the next step (CLAUDE.md:
-- never revert existing versions); ask the owner how the history should record it.
DROP FUNCTION IF EXISTS public.are_on_break_today(uuid[]);
