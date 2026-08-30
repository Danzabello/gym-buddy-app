-- Buddy-invite reward: delayed + tapered for the inviter, gated on the
-- invitee being a genuinely new account.
--
-- Replaces the immediate symmetric +20/+20 from 20260830125653 (kept intact
-- by 20260830130200's dedupe work). New shape:
--
--   invitee  -- 20 coins immediately, as before, but ONLY if genuinely new.
--   inviter  -- nothing at accept time. Paid when the invitee has checked in
--              on 2 DISTINCT DATES anywhere in the app, tapered by the
--              inviter's friend count AT PAYOUT TIME:
--                  0-29 -> 20   30-59 -> 10   60-89 -> 5   90+ -> 2
--
-- No new table. Everything a pending_invite_rewards row would hold already
-- exists somewhere immutable: invite_id/inviter_id/invitee_id/created_at on
-- the invites row itself, "genuinely new" re-derivable from auth.users, and
-- "already paid" from the presence of the payout coin_transactions row. A
-- second table would only be a second source of truth to keep in sync.
--
-- ── "Genuinely new" ────────────────────────────────────────────────────────
-- There was no existing signal for this -- invites carries only id, code,
-- inviter_id, invitee_email, status, created_at, accepted_at, accepted_by.
-- The test used is auth.users.created_at > invites.created_at: the account
-- came into existence after the invite did. Both operands are immutable, so
-- the answer can never drift, which is why it is re-derived at payout rather
-- than frozen onto a row at accept time.
--
-- This matters beyond the onboarding flow. Today consumePendingInviteCode()
-- is called from exactly one place (onboarding_basic_info_new.dart, inside
-- _saveProfile after signup), so the invitee is always new in practice -- an
-- existing logged-in user tapping an invite link only writes the code to
-- SharedPreferences, where it sits unconsumed. But accept_invite and
-- create_invite_team are both granted to authenticated, so an existing
-- account can call them directly and skip onboarding entirely. The check
-- closes that structurally instead of relying on the client flow to stay
-- shaped the way it is today.
--
-- ponytail: gates on ACCOUNT newness, not PERSON newness -- a user making a
-- second account for themselves still reads as new. Catching that needs
-- device/payment fingerprinting; separate project.
--
-- ── Why a trigger on the table ─────────────────────────────────────────────
-- daily_team_checkins is INSERTed client-side directly from five call sites
-- (team_streak_service, friend_service, coach_max_service, team_sync_service,
-- home_screen) as well as server-side via checkin_team_for_user ->
-- _apply_checkin_rewards. Hooking _apply_checkin_rewards would silently miss
-- every client-side path. A trigger on the table catches all of them.
--
-- ── Why distinct dates, not row count ──────────────────────────────────────
-- The UNIQUE on daily_team_checkins is (team_streak_id, user_id,
-- check_in_date), so one user can log two check-in ROWS on the same calendar
-- day across two teams. Every new user gets a Coach Max team at onboarding
-- plus the buddy team from this invite, so "2 rows" is reachable in a single
-- sitting and would pay the inviter out on day one. COUNT(DISTINCT
-- check_in_date) measures the thing actually being rewarded: the invitee came
-- back on a second day.
--
-- Coach Max's own check-ins are inserted under the Coach Max UUID
-- (00000000-0000-0000-0000-000000000001), not the user's, so they cannot
-- inflate the invitee's count.

-- ── Verified live (BEGIN/ROLLBACK synthetic tests, 2026-08-30) ─────────────
-- Taper, 8 synthetic pairs at the tier boundaries 0/29/30/59/60/89/90/120
-- friends -> paid 20/20/10/10/5/5/2/2, matching both the coin_transactions
-- amount and the resulting coin_balance on every one.
--   * after the 1st check-in:                 0 payouts
--   * after a 2nd check-in on the SAME DAY
--     via a second team:                      0 payouts  <- distinct-date rule
--   * after a check-in on a 2nd DISTINCT date: 8 payouts
--   * after 3rd and 4th check-ins:            still 8 payouts, balances flat
-- create_invite_team driven through real auth.uid() claims:
--   * new invitee   -> team + members + friendship, invitee +20 invite_bonus,
--                      inviter 0 at accept time; +20 only after 2 distinct
--                      check-in dates. Replaying the call did not double the
--                      invitee bonus.
--   * existing account (auth.users.created_at 30 days BEFORE the invite)
--                   -> team + 2 members + friendship all created normally,
--                      but 0 coins to BOTH sides, and still 0 after three
--                      check-ins on three distinct dates.
-- Rolled back and re-checked clean: auth.users 50, user_profiles 38,
-- daily_team_checkins 3988 (all unchanged), 0 invite_bonus/invite_reward
-- transactions, 0 residual test profiles/invites/teams.

-- ── Hot path index ─────────────────────────────────────────────────────────
-- The trigger below runs on EVERY check-in insert, for every user, forever.
-- Almost none of them were ever invited, so this index makes the common case
-- a single empty index scan.
CREATE INDEX IF NOT EXISTS invites_accepted_by_idx
  ON public.invites (accepted_by)
  WHERE status = 'accepted';

-- ── create_invite_team: drop the inviter award, gate the invitee's ─────────
-- Unchanged: the auth check, no_accepted_invite, the existing-pair dedupe
-- (20260830130200), and the buddy_teams / team_members / team_streaks /
-- friendships inserts. A non-new invitee still gets fully paired -- team,
-- streak and friendship all land normally -- they just get no coins, and
-- neither does the inviter, because no real growth happened.
CREATE OR REPLACE FUNCTION public.create_invite_team(p_inviter_id uuid, p_invitee_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_team_id UUID;
  v_invite_id UUID;
  v_invite_created TIMESTAMPTZ;
  v_invitee_is_new BOOLEAN;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_invitee_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT id, created_at INTO v_invite_id, v_invite_created
  FROM invites
  WHERE inviter_id = p_inviter_id
    AND accepted_by = p_invitee_id
    AND status = 'accepted'
  ORDER BY accepted_at DESC NULLS LAST
  LIMIT 1;

  IF v_invite_id IS NULL THEN
    RAISE EXCEPTION 'no_accepted_invite';
  END IF;

  -- Idempotency: invites has no team_id column to link back to, so "already
  -- handled" is detected the only way the schema supports -- a team that
  -- already has both of them as members. Covers a replayed call for this
  -- same invite, and also the pair already being buddies via the normal
  -- FriendService flow (which also creates a team) before this invite was
  -- accepted. Either way, one team per pair is correct: return it instead of
  -- creating a second team_streak, a duplicate friendship, or a duplicate
  -- coin award.
  SELECT tm1.team_id INTO v_team_id
  FROM team_members tm1
  JOIN team_members tm2 ON tm2.team_id = tm1.team_id AND tm2.user_id = p_invitee_id
  WHERE tm1.user_id = p_inviter_id
  LIMIT 1;

  IF v_team_id IS NOT NULL THEN
    RETURN v_team_id;
  END IF;

  INSERT INTO buddy_teams (team_name, team_emoji, is_coach_max_team, max_members, created_by, created_at, updated_at)
  VALUES ('Gym Buddies', '💪', false, 2, p_inviter_id, v_now, v_now)
  RETURNING id INTO v_team_id;

  INSERT INTO team_members (team_id, user_id, role, joined_at, created_at)
  VALUES
    (v_team_id, p_inviter_id, 'member', v_now, v_now),
    (v_team_id, p_invitee_id, 'member', v_now, v_now);

  INSERT INTO team_streaks (team_id, current_streak, longest_streak, is_active, created_at, updated_at)
  VALUES (v_team_id, 0, 0, true, v_now, v_now);

  -- Mirror the normal buddy flow: an invited buddy is also a friend, so they
  -- appear in the Gym Buddies list. Skip if a friendship already exists in
  -- either direction (unique key is directional on (user_id, friend_id)).
  INSERT INTO friendships (user_id, friend_id, status)
  SELECT p_inviter_id, p_invitee_id, 'accepted'
  WHERE NOT EXISTS (
    SELECT 1 FROM friendships
    WHERE (user_id = p_inviter_id AND friend_id = p_invitee_id)
       OR (user_id = p_invitee_id AND friend_id = p_inviter_id)
  );

  -- Did this invite cause this account to exist? See the header note.
  SELECT (u.created_at > v_invite_created) INTO v_invitee_is_new
  FROM auth.users u WHERE u.id = p_invitee_id;

  -- Invitee's own bonus: unchanged at 20 coins on acceptance, but now skipped
  -- entirely for a pre-existing account -- the "new signup" framing does not
  -- apply to them either.
  --
  -- The NOT EXISTS guard is now scoped by user_id. It used to be a single
  -- shared check covering both awards, which was fine while they fired
  -- together; with the inviter's award moved to _fulfil_invite_reward (and
  -- carrying its own transaction_type) an unscoped guard would be ambiguous.
  IF COALESCE(v_invitee_is_new, false) THEN
    IF NOT EXISTS (
      SELECT 1 FROM coin_transactions
      WHERE transaction_type = 'invite_bonus'
        AND reference_id = v_invite_id::text
        AND user_id = p_invitee_id
    ) THEN
      PERFORM award_coins(p_invitee_id, 20, 'invite_bonus', 'Joined via buddy invite', v_invite_id::text);
    END IF;
  END IF;

  RETURN v_team_id;
END;
$function$;

-- ── Delayed inviter payout ─────────────────────────────────────────────────
-- postgres-owned SECURITY DEFINER because award_coins is postgres-owned
-- SECURITY DEFINER with an ACL of postgres + service_role only -- a trigger
-- function running as the invoking `authenticated` role could not call it.
CREATE OR REPLACE FUNCTION public._fulfil_invite_reward()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_invite  RECORD;
  v_days    INT;
  v_friends INT;
  v_amount  INT;
BEGIN
  -- In practice this loops at most once: one invite code is consumed per
  -- onboarding, so an invitee has at most one accepted invite. The loop costs
  -- nothing and cannot be wrong if that ever stops holding.
  --
  -- The lock is taken BEFORE the already-paid check, not alongside it. Under
  -- READ COMMITTED, putting the NOT EXISTS in this WHERE would be racy:
  -- EvalPlanQual re-checks the locked invites row after a concurrent commit,
  -- but it does NOT re-evaluate a subquery against a different table, so two
  -- concurrent check-ins could both pass the guard before either took the
  -- lock. Locking first means the second one blocks, and its EXISTS below
  -- runs as a fresh statement afterwards -- seeing the committed payout.
  FOR v_invite IN
    SELECT i.id, i.inviter_id, i.created_at
    FROM invites i
    WHERE i.accepted_by = NEW.user_id
      AND i.status = 'accepted'
    FOR UPDATE
  LOOP
    IF EXISTS (
      SELECT 1 FROM coin_transactions
      WHERE transaction_type = 'invite_reward'
        AND reference_id = v_invite.id::text
    ) THEN
      CONTINUE;   -- already paid; this is the 3rd/4th/Nth check-in
    END IF;

    -- Genuinely new, re-derived from immutable inputs.
    IF NOT EXISTS (
      SELECT 1 FROM auth.users u
      WHERE u.id = NEW.user_id
        AND u.created_at > v_invite.created_at
    ) THEN
      CONTINUE;
    END IF;

    -- NEW's row is already visible here (AFTER INSERT), so it counts itself.
    -- >= 2 rather than = 2 so this still fires correctly for anyone who
    -- already had check-ins when the trigger was deployed; the EXISTS guard
    -- above is what prevents paying twice.
    SELECT COUNT(DISTINCT check_in_date) INTO v_days
    FROM daily_team_checkins
    WHERE user_id = NEW.user_id;

    IF v_days < 2 THEN
      CONTINUE;
    END IF;

    -- Same shape as the squad_goals/social_butterfly/influencer branch of
    -- verify_and_unlock_achievement: bidirectional, friendships not
    -- team_members. Computed fresh at payout, not at accept time.
    SELECT COUNT(*) INTO v_friends
    FROM friendships
    WHERE status = 'accepted'
      AND (user_id = v_invite.inviter_id OR friend_id = v_invite.inviter_id);

    v_amount := CASE
      WHEN v_friends < 30 THEN 20
      WHEN v_friends < 60 THEN 10
      WHEN v_friends < 90 THEN 5
      ELSE 2                       -- floor, does not halve further
    END;

    -- A reward bug must never cost the user their check-in. invites.inviter_id
    -- is ON DELETE CASCADE so award_coins cannot hit user_not_found by that
    -- route, but this trigger sits on the app's most important write path and
    -- the check-in is worth more than the payout.
    -- ponytail: swallows the error, so a failure is a silent non-payment;
    -- add a dead-letter row if that ever needs to be visible.
    BEGIN
      PERFORM award_coins(
        v_invite.inviter_id, v_amount, 'invite_reward',
        'Buddy invite paid off', v_invite.id::text
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;

  RETURN NULL;   -- AFTER trigger; return value is ignored
END;
$function$;

-- Not client-facing: matches _apply_checkin_rewards' ACL (postgres +
-- service_role). Trigger functions are permission-checked at CREATE TRIGGER
-- time, not at fire time, so this does not stop the trigger firing for
-- authenticated callers.
REVOKE EXECUTE ON FUNCTION public._fulfil_invite_reward() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_checkin_fulfil_invite_reward ON public.daily_team_checkins;
CREATE TRIGGER on_checkin_fulfil_invite_reward
  AFTER INSERT ON public.daily_team_checkins
  FOR EACH ROW EXECUTE FUNCTION public._fulfil_invite_reward();
