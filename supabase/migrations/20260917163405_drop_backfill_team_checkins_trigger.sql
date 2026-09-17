-- LIVE-15 fix: backfill_team_checkins_on_creation() (AFTER INSERT ON
-- buddy_teams) did the exact same "both members already checked in today ->
-- backfill daily_team_checkins + set current_streak=1, longest_streak=1" job
-- as friend_service.dart's _backfillTodaysCheckIns, from a completely
-- independent, uncoordinated code path, gated only by its own internal
-- PERFORM pg_sleep(0.5) (its own comment: "hacky ... necessary due to
-- transaction timing"). The two raced each other on every accept-friend-
-- request team creation. Confirmed via a separate investigation:
-- _backfillTodaysCheckIns inserts its own daily_team_checkins rows and does
-- not depend on this trigger having run; the trigger explicitly no-ops for
-- Coach Max teams (its own IF NEW.is_coach_max_team = false guard), and
-- Coach Max team creation never calls _backfillTodaysCheckIns either, so
-- dropping this trigger removes no coverage anywhere -- the Dart-side path
-- was always sufficient on its own, just racing an unnecessary duplicate.
--
-- Confirmed this is the only trigger referencing the function before
-- dropping both.
DROP TRIGGER trigger_backfill_checkins_on_team_creation ON public.buddy_teams;
DROP FUNCTION public.backfill_team_checkins_on_creation();
