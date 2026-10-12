-- H1 Phase B: workouts lock-down. APPLIED as migration 20261012190000_handshake_phase_b_lockdown (H4a); this file is the original draft.
--
-- Closes the H0 forgery hole: neither participant can write the row any
-- more, so buddy_status / *_ready / *_cancelled / user_id / buddy_id only
-- change through the SECURITY DEFINER handshake functions.
-- Kept: client INSERT (createWorkout; cap + safe defaults are enforced by
-- _clamp_client_workout_writes) and the owner DELETE policy.
-- No column needs a client UPDATE after H3 (see H1 report).

REVOKE UPDATE ON public.workouts FROM authenticated, anon;

DROP POLICY "Users can update own or buddy workouts" ON public.workouts;
DROP POLICY "Users can update their workouts" ON public.workouts;

-- ready_expires_at is no longer written; "I'm here" uses the planned_at window.
SELECT cron.unschedule('reset-expired-ready');
