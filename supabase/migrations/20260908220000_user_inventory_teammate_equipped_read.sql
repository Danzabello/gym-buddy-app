-- Allow teammates to see each other's currently-equipped cosmetic items
-- (e.g. ring_color), needed so the check-in ring can render a buddy's own
-- equipped color instead of the hashed fallback. Mirrors the existing
-- break_day_usage "Users can view their partners' break days" policy
-- (20260628000000) — same team_streaks/team_members double-join, same
-- ts.is_active guard — scoped further to equipped = true so a teammate's
-- unequipped inventory/purchase history stays private.
DROP POLICY IF EXISTS "Users can view partners' equipped items" ON public.user_inventory;
CREATE POLICY "Users can view partners' equipped items" ON public.user_inventory
  FOR SELECT TO public USING (
    equipped = true
    AND EXISTS ( SELECT 1
       FROM (team_streaks ts
         JOIN team_members tm1 ON (((tm1.team_id = ts.team_id) AND (tm1.user_id = auth.uid()))))
         JOIN team_members tm2 ON (((tm2.team_id = ts.team_id) AND (tm2.user_id = user_inventory.user_id)))
      WHERE (ts.is_active = true))
  );
