-- Close two INSERT policies named "Service role inserts ..." that were actually
-- granted to PUBLIC with WITH CHECK (true). The names describe the intent; the
-- policies never implemented it. Supabase advisor flags both as
-- rls_policy_always_true.
--
-- Confirmed live before writing this, as `authenticated` with a JWT sub set to
-- one user and the row addressed to a DIFFERENT user, each inside a rolled-back
-- transaction:
--   * xp_transactions          -> forged +999999 XP ledger row landed for another user
--   * user_unlocked_cosmetics  -> "Diamond Frame" (1500 coins, unlock_level 9)
--                                 granted free to another user
-- (Both probes must omit RETURNING: the SELECT policy is auth.uid() = user_id,
-- so reading the forged row back fails even though the write succeeds. An
-- INSERT ... RETURNING misleadingly reports an RLS violation here.)
--
-- Group A locked user_profiles.xp / level / coin_balance, so balances were never
-- writable -- but the ledger meant to audit them was, and cosmetics bypassed
-- purchase_shop_item entirely.

-- ---------------------------------------------------------------------------
-- 1. xp_transactions -- no client writes at all.
--
-- Matches the coin_transactions pattern, which is the house convention for an
-- audit ledger: a SELECT policy only (auth.uid() = user_id), no INSERT policy,
-- every write via a SECURITY DEFINER RPC. Legitimate writers here are
-- _apply_checkin_rewards, award_achievement_rewards and award_xp -- all
-- SECURITY DEFINER owned by postgres, which owns the table and therefore
-- bypasses RLS (relforcerowsecurity = false), so none of them is affected.
--
-- No live client writer exists: XpService has zero references outside its own
-- file, and LevelService._applyXp is reachable only from awardWorkoutXP, which
-- has no callers. Both also write user_profiles.xp first, which Group A already
-- revoked -- so those paths were dead before this migration.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Service role inserts xp_transactions" ON public.xp_transactions;
REVOKE INSERT ON public.xp_transactions FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. user_unlocked_cosmetics -- close cross-user grants.
--
-- Dropping only the always-true policy leaves "Users can insert own unlocked
-- cosmetics" (WITH CHECK auth.uid() = user_id) in place, which the live
-- LevelService.grantMilestoneUnlock path needs -- it is called fire-and-forget
-- from TeamStreakService when a streak hits 30/60/90/100.
--
-- NOTE: this closes granting cosmetics to OTHER users. It does NOT close a user
-- granting cosmetics to THEMSELVES, which the remaining self-insert policy
-- still permits and which still bypasses cost and unlock_level. Fully closing
-- that needs milestone unlocks moved behind a SECURITY DEFINER RPC that
-- verifies the milestone server-side, plus a client change -- out of scope for
-- this migration and tracked separately.
--
-- INSERT stays granted to `authenticated` for the reason above. anon is revoked:
-- auth.uid() is null for anon so the remaining policy could never pass anyway.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Service role inserts unlocked cosmetics" ON public.user_unlocked_cosmetics;
REVOKE INSERT ON public.user_unlocked_cosmetics FROM PUBLIC, anon;
