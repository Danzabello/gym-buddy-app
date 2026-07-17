-- REGRESSION FIX (introduced by Group A, 20260717165500): new-user onboarding
-- has been failing on live since Group A landed.
--
-- Group A dropped `id` from the authenticated UPDATE grant on user_profiles
-- ("keep id in INSERT only"). That silently broke the onboarding profile
-- write: the client uses PostgREST .upsert(), which compiles to
--   INSERT ... ON CONFLICT (id) DO UPDATE SET <all columns, incl id=excluded.id>
-- Postgres requires UPDATE privilege on EVERY column in the DO UPDATE SET
-- clause -- including id -- even for a pure insert where no row conflicts.
-- Without UPDATE(id), `authenticated` got "permission denied for table
-- user_profiles" and every signup died at "Could not save profile".
-- (Existing users were unaffected -- they were already onboarded.)
--
-- Fix: restore UPDATE(id) to authenticated so the upsert compiles, and add a
-- WITH CHECK to the update policy so a client still cannot change id (or any
-- row) to another user's -- preserving Group A's "no client-driven id change"
-- intent more robustly than the grant removal did (the upsert only ever sets
-- id = the same auth.uid(), which passes the check).

GRANT UPDATE (id) ON public.user_profiles TO authenticated;

DROP POLICY IF EXISTS "Users can update own profile" ON public.user_profiles;
CREATE POLICY "Users can update own profile" ON public.user_profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);
