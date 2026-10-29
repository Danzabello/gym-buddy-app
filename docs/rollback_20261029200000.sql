-- Rollback for 20261029200000_search_request_rate. Restores search_usernames as dumped from live on 2026-10-29
-- (docs/hygiene/13_backup/search_usernames.sql, md5 5c5f653edbf52d3306099748fd2187dc) with its grants, then drops
-- the friendships trigger, its function and both meter tables.
-- Pre-change ACL: search_usernames {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}, SET search_path=public.

DROP TRIGGER IF EXISTS meter_friend_request ON public.friendships;
DROP FUNCTION IF EXISTS public._meter_friend_request();
DROP TABLE IF EXISTS public.friend_request_attempts;

CREATE OR REPLACE FUNCTION public.search_usernames(q text)
 RETURNS TABLE(id uuid, username text, display_name text, avatar_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
REVOKE EXECUTE ON FUNCTION public.search_usernames(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.search_usernames(text) TO authenticated;
DROP TABLE IF EXISTS public.username_search_attempts;
