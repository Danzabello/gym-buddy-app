-- M4 (DB audit DB-5): daily_team_checkins has (user_id) and (check_in_date) separately, so "my check-ins on these
-- days" (dashboard heatmap, has-checked-in-today, and the same predicate in submit_checkin, finish_checkin_session,
-- process_stale_sessions, _fulfil_invite_reward) combines two indexes. One (user_id, check_in_date) index serves it,
-- and its leading column covers everything (user_id) served, including the FK to user_profiles, so (user_id) goes.
-- Plain CREATE INDEX (SHARE lock for milliseconds at this size; a concurrent check-in insert waits that long).
-- No policy, grant, function or lock-order change.
CREATE INDEX idx_daily_team_checkins_user_date ON public.daily_team_checkins (user_id, check_in_date);
DROP INDEX public.idx_daily_team_checkins_user;
