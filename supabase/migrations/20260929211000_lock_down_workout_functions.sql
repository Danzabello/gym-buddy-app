-- Close the unauthenticated / cross-user exposure on three workout functions
-- found by the security advisors (anon_security_definer_function_executable).
-- All three were SECURITY DEFINER with EXECUTE granted to PUBLIC, anon and
-- authenticated, and none checked auth.uid() against its arguments.
--
--   * create_buddy_workout_sessions(...): upserts active_checkin_sessions for
--     ANY two user ids the caller names (ON CONFLICT (user_id) DO UPDATE, so it
--     overwrites a victim's live session). No caller anywhere (lib/, Edge
--     Functions, or any DB function/policy/trigger); created before version
--     control. Revoked from every client role.
--   * is_user_in_active_workout(uuid): reads workouts + active_checkin_sessions
--     with RLS bypassed and returns whether ANY user is mid-workout (an
--     activity oracle). No caller anywhere. Revoked from every client role.
--   * get_workouts_awaiting_creator_join(uuid): returned another user's running
--     buddy workouts (workout id, type, buddy display name, timings) for any
--     creator_id. Its one caller (workout_service.dart) always passes the
--     signed-in user's own id, so it is kept for authenticated but made
--     SECURITY INVOKER: the workouts SELECT policy (own rows or rows where the
--     caller is the buddy) then bounds what it can return. search_path is
--     pinned (function_search_path_mutable advisor). anon and PUBLIC lose
--     EXECUTE.
--
-- service_role and postgres keep EXECUTE on all three (not touched here).
-- Grants are restated explicitly per the repo rule for client-facing functions.
-- Rollback (restores grants and SECURITY DEFINER exactly): docs/rollback_functions_20260929211000.sql

REVOKE EXECUTE ON FUNCTION public.create_buddy_workout_sessions(uuid, uuid, uuid, timestamp with time zone, text, text, integer)
  FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.is_user_in_active_workout(uuid)
  FROM PUBLIC, anon, authenticated;

ALTER FUNCTION public.get_workouts_awaiting_creator_join(uuid)
  SECURITY INVOKER
  SET search_path = public;
REVOKE EXECUTE ON FUNCTION public.get_workouts_awaiting_creator_join(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_workouts_awaiting_creator_join(uuid) TO authenticated;

-- Self-check: abort (and roll the whole migration back) if the end state is wrong.
DO $$
DECLARE
  f_create oid := 'public.create_buddy_workout_sessions(uuid, uuid, uuid, timestamp with time zone, text, text, integer)'::regprocedure;
  f_active oid := 'public.is_user_in_active_workout(uuid)'::regprocedure;
  f_await  oid := 'public.get_workouts_awaiting_creator_join(uuid)'::regprocedure;
BEGIN
  IF has_function_privilege('anon', f_create, 'EXECUTE')
     OR has_function_privilege('authenticated', f_create, 'EXECUTE')
     OR has_function_privilege('anon', f_active, 'EXECUTE')
     OR has_function_privilege('authenticated', f_active, 'EXECUTE')
     OR has_function_privilege('anon', f_await, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', f_await, 'EXECUTE') THEN
    RAISE EXCEPTION 'workout function grants are not in the expected end state';
  END IF;
  IF (SELECT prosecdef FROM pg_proc WHERE oid = f_await) THEN
    RAISE EXCEPTION 'get_workouts_awaiting_creator_join is still SECURITY DEFINER';
  END IF;
END $$;
