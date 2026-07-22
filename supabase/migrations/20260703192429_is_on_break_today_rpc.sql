-- is_on_break_today: is this user on an uncancelled break for THEIR OWN
-- local today (safe_user_tz frame, same as all streak/economy RPCs)?
-- SECURITY INVOKER on purpose: break_day_usage RLS already grants partners
-- read access, so teammates get a true answer and anyone else gets false.
CREATE OR REPLACE FUNCTION public.is_on_break_today(p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM break_day_usage
    WHERE user_id = p_user_id
      AND cancelled_at IS NULL
      AND break_date = (now() AT TIME ZONE safe_user_tz(p_user_id))::date
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_on_break_today(uuid) TO authenticated;