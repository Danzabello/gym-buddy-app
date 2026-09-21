-- Companion to add_check_in_coach_max_rpc: now that check_in_coach_max
-- (SECURITY DEFINER) is the only legitimate writer of
-- coach_max_schedule.has_checked_in/checked_in_at and of Coach Max's
-- daily_team_checkins rows, close the two direct client paths that made the
-- RPC bypassable.
--
-- Deviation from a literal column-level REVOKE: checked live first (same
-- relacl/attacl check used for the team_streaks fix) and found the exact
-- same table-level-grant trap -- coach_max_schedule.relacl already granted
-- authenticated/anon full table-level UPDATE (arwdDxtm), and a column-level
-- REVOKE cannot subtract from a table-level grant in Postgres. Applying the
-- column-level form here would have been a silent no-op, so this revokes
-- UPDATE at the table level instead. No follow-up column GRANT is needed
-- (unlike team_streaks' is_favorite): grepping every Dart write to this
-- table confirms has_checked_in/checked_in_at was the only column the
-- client ever UPDATEd -- nothing legitimate remains to grant back.
REVOKE UPDATE ON public.coach_max_schedule FROM authenticated, anon;

-- "Coach Max check-in for own team" let a client INSERT directly into
-- daily_team_checkins with user_id = coachMaxId for any of their own teams,
-- with no time-window check of its own -- it existed only to let the old
-- direct-write client code bypass the normal user_id = auth.uid() ownership
-- rule. check_in_coach_max() bypasses RLS by function ownership like every
-- other SECURITY DEFINER function in this codebase, so it doesn't need this
-- policy; leaving it in place would remain a live, unrestricted "insert a
-- fake Coach Max check-in for my team, no time check" hole even after the
-- Dart client stops calling it directly.
DROP POLICY "Coach Max check-in for own team" ON public.daily_team_checkins;
