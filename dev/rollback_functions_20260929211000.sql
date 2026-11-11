-- ROLLBACK for supabase/migrations/20260929211000_lock_down_workout_functions.sql
-- NOT a migration: lives in docs/ on purpose so `supabase db push` never runs it.
--
-- Restores the state captured from the live project on 2026-09-29:
--   * all three functions: EXECUTE granted to PUBLIC, anon and authenticated
--     (proacl {=X/postgres,postgres=X/postgres,anon=X/postgres,
--              authenticated=X/postgres,service_role=X/postgres}; postgres and
--     service_role were never revoked, so they need no statement here)
--   * get_workouts_awaiting_creator_join: SECURITY DEFINER, no search_path
--     setting (proconfig NULL)
--   * create_buddy_workout_sessions keeps its own search_path=public; the
--     migration never changed it.
-- Run as postgres. Idempotent.
BEGIN;

GRANT EXECUTE ON FUNCTION public.create_buddy_workout_sessions(uuid, uuid, uuid, timestamp with time zone, text, text, integer)
  TO PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.is_user_in_active_workout(uuid)
  TO PUBLIC, anon, authenticated;

ALTER FUNCTION public.get_workouts_awaiting_creator_join(uuid) SECURITY DEFINER;
ALTER FUNCTION public.get_workouts_awaiting_creator_join(uuid) RESET search_path;
GRANT EXECUTE ON FUNCTION public.get_workouts_awaiting_creator_join(uuid)
  TO PUBLIC, anon, authenticated;

-- Verify: each row should show proacl with =X/postgres, anon and authenticated,
-- and get_workouts_awaiting_creator_join should show prosecdef = true, proconfig = null.
--   select proname, prosecdef, proconfig, proacl::text from pg_proc
--   where pronamespace = 'public'::regnamespace
--     and proname in ('create_buddy_workout_sessions','is_user_in_active_workout',
--                     'get_workouts_awaiting_creator_join');
COMMIT;
