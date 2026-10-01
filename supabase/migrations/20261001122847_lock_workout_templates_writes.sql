-- LIVE-27: any authenticated user could insert workout_templates rows with
-- is_system_template = true, shown to every user. Client only SELECTs templates
-- (workout_history_service.dart). SELECT grant and RLS policies are untouched.
REVOKE INSERT, UPDATE ON public.workout_templates FROM authenticated;
