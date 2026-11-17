-- Rollback for 20261116224000_daily_team_checkins_user_date_index.sql: the 2026-11-16 index set.
CREATE INDEX idx_daily_team_checkins_user ON public.daily_team_checkins USING btree (user_id);
DROP INDEX public.idx_daily_team_checkins_user_date;
