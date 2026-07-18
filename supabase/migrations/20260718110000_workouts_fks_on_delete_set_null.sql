-- workouts.started_by_user_id and workouts.cancel_requested_by reference
-- auth.users with the default ON DELETE NO ACTION, which blocks deleting a
-- user who started/cancelled a (buddy) workout owned by someone else -- the
-- exact case that made account deletion fail with 23503.
--
-- They're attribution pointers ("who started" / "who requested cancel"); the
-- workout's ownership lives on workouts.user_id. Change to ON DELETE SET NULL
-- so account deletion never depends on a caller clearing them first. Losing
-- the attribution on the deleted user is acceptable.
ALTER TABLE public.workouts DROP CONSTRAINT workouts_started_by_user_id_fkey;
ALTER TABLE public.workouts ADD CONSTRAINT workouts_started_by_user_id_fkey
  FOREIGN KEY (started_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.workouts DROP CONSTRAINT workouts_cancel_requested_by_fkey;
ALTER TABLE public.workouts ADD CONSTRAINT workouts_cancel_requested_by_fkey
  FOREIGN KEY (cancel_requested_by) REFERENCES auth.users(id) ON DELETE SET NULL;
