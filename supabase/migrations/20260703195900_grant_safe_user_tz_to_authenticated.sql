-- is_on_break_today() is SECURITY INVOKER, so clients need EXECUTE on the
-- safe_user_tz() it calls. Every prior caller was SECURITY DEFINER, which is
-- why this grant was never needed before. safe_user_tz only reads
-- user_profiles.timezone, which authenticated can already SELECT directly.
GRANT EXECUTE ON FUNCTION public.safe_user_tz(uuid) TO authenticated;