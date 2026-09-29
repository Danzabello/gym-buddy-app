-- Onboarding value-props slide 1 ("Find your buddy") searches user_profiles
-- by username before the visitor signs up, i.e. as the anon role. Live's
-- only SELECT policies on public.user_profiles require auth.uid() IS NOT
-- NULL, so the pre-signup search always returned zero rows (verified
-- 2026-09-24: searching "roki" showed "No users found" despite a matching
-- username existing). The pre-signup search is intentional product
-- behaviour, not the bug -- this RPC gives it a narrow, safe read path
-- instead of opening user_profiles itself to anon.
CREATE OR REPLACE FUNCTION public.search_usernames(q text)
RETURNS TABLE (id uuid, username text, display_name text, avatar_id text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_escaped text;
BEGIN
  IF q IS NULL OR length(q) < 3 THEN
    RETURN;
  END IF;

  -- Escape % and _ so they're treated as literal characters, not SQL LIKE
  -- wildcards (same convention as the client-side escape this replaces).
  v_escaped := replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_');

  RETURN QUERY
  SELECT up.id, up.username, up.display_name, up.avatar_id
  FROM public.user_profiles up
  WHERE up.username IS NOT NULL
    AND up.username ILIKE '%' || v_escaped || '%'
  LIMIT 10;
END;
$$;

-- anon needs this pre-signup -- that's intentional, not an oversight.
REVOKE EXECUTE ON FUNCTION public.search_usernames(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_usernames(text) TO anon, authenticated;
