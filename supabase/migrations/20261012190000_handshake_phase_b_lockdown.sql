-- Handshake Phase B (H4a): workouts lock-down. Every handshake write goes through
-- the SECURITY DEFINER RPCs now (H3 removed the last direct client write), so
-- neither participant can forge buddy_status / *_ready / *_cancelled / user_id /
-- buddy_id any more. Kept: client INSERT (createWorkout; cap + safe defaults are
-- enforced by _clamp_client_workout_writes) and the owner DELETE policy.
-- Rollback: Phase B reversal in docs/handshake/H1_rollback.sql.

REVOKE UPDATE ON public.workouts FROM authenticated, anon;

DROP POLICY IF EXISTS "Users can update own or buddy workouts" ON public.workouts;
DROP POLICY IF EXISTS "Users can update their workouts" ON public.workouts;

-- ready_expires_at is no longer written; "I'm here" uses the planned_at window.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'reset-expired-ready') THEN
    PERFORM cron.unschedule('reset-expired-ready');
  END IF;
END $$;
