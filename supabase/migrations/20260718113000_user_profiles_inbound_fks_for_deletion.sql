-- Account deletion (delete-account Edge Function) deletes user_profiles, but
-- four inbound FKs to user_profiles were ON DELETE NO ACTION and blocked it
-- (buddy_teams.created_by hit first with 23503). Give them non-blocking
-- actions so the profile delete never depends on a caller pre-clearing rows:
--   - attribution pointers ("who created" / "who buddied") -> SET NULL
--     (the row -- team/template/log -- survives; the deleted user's
--     attribution is simply unknown)
--   - the user's OWN workout_logs (workout_logs.user_id, NOT NULL) -> CASCADE

ALTER TABLE public.buddy_teams DROP CONSTRAINT buddy_teams_created_by_fkey;
ALTER TABLE public.buddy_teams ADD CONSTRAINT buddy_teams_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES user_profiles(id) ON DELETE SET NULL;

ALTER TABLE public.workout_logs DROP CONSTRAINT workout_logs_user_id_fkey;
ALTER TABLE public.workout_logs ADD CONSTRAINT workout_logs_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;

ALTER TABLE public.workout_logs DROP CONSTRAINT workout_logs_buddy_id_fkey;
ALTER TABLE public.workout_logs ADD CONSTRAINT workout_logs_buddy_id_fkey
  FOREIGN KEY (buddy_id) REFERENCES user_profiles(id) ON DELETE SET NULL;

ALTER TABLE public.workout_templates DROP CONSTRAINT workout_templates_created_by_fkey;
ALTER TABLE public.workout_templates ADD CONSTRAINT workout_templates_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES user_profiles(id) ON DELETE SET NULL;
