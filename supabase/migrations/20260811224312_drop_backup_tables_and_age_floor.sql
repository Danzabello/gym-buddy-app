-- Three cleanups from the privacy-policy data inventory (2026-08-11), one
-- logical unit: stop leaking check-ins to non-friends, make the stated
-- minimum age real, and delete data that survives account deletion.
--
-- Ordering is deliberate: the two reversible fixes run FIRST and the
-- irreversible DROP TABLE block runs LAST, so if anything above fails the
-- transaction aborts before any data is destroyed.


-- ── 1. Close the pending-friendship read hole on daily_team_checkins ────────
--
-- The friend arm of this policy was asymmetric. Verbatim, as it stood:
--
--   EXISTS (SELECT 1 FROM friendships WHERE
--       (friendships.user_id   = auth.uid() AND friendships.friend_id = daily_team_checkins.user_id)
--       -- ^ FORWARD arm: no status condition AT ALL
--    OR (friendships.friend_id = auth.uid() AND friendships.user_id   = daily_team_checkins.user_id
--        AND friendships.status = 'accepted'))
--       -- ^ REVERSE arm: correctly gated
--
-- Because the forward arm tested no status, merely *sending* a friend
-- request was enough to read the target's entire team check-in history --
-- which team streak, which dates, what time of day. The friendships INSERT
-- policy is WITH CHECK (auth.uid() = user_id), so any user could do this to
-- any other user with no consent step, and access began the moment the row
-- was inserted.
--
-- Confirmed empirically on live in a rolled-back transaction (2026-08-11):
-- with no friendship the attacker saw 0 of the target's rows; after a single
-- status='pending' outbound insert, 56. The reverse direction correctly
-- stayed at 0, isolating the missing condition as the sole cause.
--
-- Origin: captured as-is into 20260628000000_baseline_rls_policies_snapshot,
-- which is a snapshot of what was already live -- so the defect predates
-- version control rather than arriving in a later edit.
--
-- The fix hoists `status = 'accepted'` out of both arms into a single
-- condition. Preferred over bolting AND status='accepted' onto the forward
-- arm: with the check hoisted the asymmetry cannot be reintroduced by
-- editing one branch, and it matches the shape verify_achievement_progress
-- already uses. ALTER POLICY (not DROP + CREATE) so there is no window in
-- which the table sits unprotected.
--
-- Scope note: the friend arm is KEPT. Friends seeing team check-ins is
-- intended behaviour per the policy's name; only the missing status gate
-- was a defect.
--
-- Verified isolated: this is the only policy in the schema that references
-- friendships, and the three SECURITY DEFINER functions that do
-- (verify_achievement_progress, create_invite_team, remove_friend) plus
-- isFriendOrTeammate in the send-notification Edge Function are all
-- symmetric.

ALTER POLICY "Users can view check-ins for their teams and friends"
  ON public.daily_team_checkins
  USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM team_streaks ts
                 JOIN team_members tm ON tm.team_id = ts.team_id
                WHERE ts.id = daily_team_checkins.team_streak_id
                  AND tm.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM friendships f
                WHERE f.status = 'accepted'
                  AND (   (f.user_id = auth.uid() AND f.friend_id = daily_team_checkins.user_id)
                       OR (f.friend_id = auth.uid() AND f.user_id = daily_team_checkins.user_id)))
  );


-- ── 2. Make the 16+ minimum age a real server-side guarantee ────────────────
--
-- InputLimits.ageMin = 16 (lib/utils/input_validators.dart) has always been
-- client-only: user_profiles carried no CHECK constraint at all, and the
-- authenticated role holds INSERT/UPDATE grants on the age column, so a
-- modified client or a direct PostgREST call could write any value.
--
-- NOT NULL and CHECK are both required, and neither is sufficient alone:
-- a CHECK fails only on FALSE, so `age >= 16` evaluates to NULL -- and
-- therefore PASSES -- for a NULL age. Without NOT NULL the constraint is a
-- floor that applies only when a value happens to be present; with it, the
-- CHECK can never see NULL and the minimum actually holds.
--
-- Preconditions verified on live immediately before applying:
--   38 profiles, 0 NULL, 0 below 16 (min 16, max 100), column nullable.
-- No existing row is rewritten, excluded, or defaulted.

ALTER TABLE public.user_profiles
  ALTER COLUMN age SET NOT NULL;

ALTER TABLE public.user_profiles
  ADD CONSTRAINT user_profiles_age_min_16 CHECK (age >= 16);

-- Not done here, deliberately: no upper bound mirroring
-- InputLimits.ageMax = 120. Out of scope for this migration; live max is 100.


-- ── 3. Drop the five orphaned *_backup tables (IRREVERSIBLE) ────────────────
--
-- One-off snapshots taken during a pre-version-control migration. They hold
-- 249 rows of real user data (user_ids, social graph, check-in history) and
-- are dead weight in two distinct ways:
--
--   * Nothing reads them. Verified fresh 2026-08-11 against Dart (lib/,
--     test/), Edge Functions (supabase/functions/), and the live DB: no
--     function body, view, matview, trigger, or foreign key -- inbound or
--     outbound -- refers to any of them.
--   * They defeat account deletion. Having no FK to user_profiles or
--     auth.users, they are untouched by the delete-account Edge Function, so
--     a user who deletes their account still leaves rows here. That is why
--     this drop is happening now: the privacy policy is about to make a
--     deletion promise these tables would falsify.
--
-- Access-wise they were never exposed (RLS enabled with no policies =
-- deny-all; team_members_backup carried an explicit USING (false)), so this
-- is a retention fix, not a hole being closed.
--
-- Row counts at drop time, for the record:
--   buddy_teams_backup          31
--   friendships_backup          12
--   team_members_backup         58
--   team_streaks_backup         34
--   daily_team_checkins_backup 114
--
-- Irreversible: this data exists nowhere else.
--
-- Replay note: 20260628000000_baseline_rls_policies_snapshot ENABLEs RLS on
-- these five and defines the team_members_backup policy, so those lines
-- would fail on a strict from-scratch replay. Per CLAUDE.md such a replay is
-- already impossible (it dies at the first migration, against tables no
-- migration creates) and `db push` skips the baseline as recorded-applied.
-- This adds no new breakage.

DROP TABLE IF EXISTS public.buddy_teams_backup;
DROP TABLE IF EXISTS public.friendships_backup;
DROP TABLE IF EXISTS public.team_members_backup;
DROP TABLE IF EXISTS public.team_streaks_backup;
DROP TABLE IF EXISTS public.daily_team_checkins_backup;
