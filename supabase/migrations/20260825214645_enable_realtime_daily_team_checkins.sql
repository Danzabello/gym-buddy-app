-- Enables Postgres Changes (Realtime) for daily_team_checkins so the
-- dashboard's check-in ring can update live without a manual refresh.
-- RLS ("Users can view check-ins for their teams and friends") already
-- scopes visibility to own rows + shared team_streak + accepted friends,
-- and Realtime enforces RLS per-subscriber, so no additional filtering
-- is needed here to keep this scoped rather than global.
ALTER PUBLICATION supabase_realtime ADD TABLE public.daily_team_checkins;
