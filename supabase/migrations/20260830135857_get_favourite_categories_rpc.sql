-- Top-3 workout categories by all-time check-in count, for the profile
-- page's "Favourite Categories" stat card. Mirrors get_user_streaks'
-- shape (p_user_id in, SECURITY DEFINER, search_path pinned) since this
-- is the same class of per-user stat lookup.
CREATE OR REPLACE FUNCTION public.get_favourite_categories(p_user_id uuid)
 RETURNS TABLE(workout_category text, category_count bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT workout_category, COUNT(*) AS category_count
  FROM workout_logs
  WHERE user_id = p_user_id
  GROUP BY workout_category
  ORDER BY category_count DESC, workout_category ASC
  LIMIT 3;
$function$;

REVOKE ALL ON FUNCTION public.get_favourite_categories(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_favourite_categories(uuid) TO authenticated;
