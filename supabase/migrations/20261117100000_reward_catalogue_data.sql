-- Prompt 53, migration 1 of 2: reward catalogue data (R1, R4, R5, R7). Config rows only: no RLS, grant, streak or credit logic.
--   R1 personal_best: 100 coins / 200 XP -> 25 coins / 50 XP (future unlocks only; accounts that hold it keep what they were paid).
--   R4 Wolf and Lion shop rows hidden: both are free starters, so the shop sold an avatar the user already has.
--   R5 connector text: it counts accepted buddies since 20261115170000, so the text now says so.
--   R7 year_of_the_beast: 5,000 -> 2,000 coins; XP stays 5,000 and the Crown Gold ring it grants is untouched.
-- Each UPDATE matches the old values too, and the block raises unless it hits exactly the rows it expects, so a drifted
-- row can never pass as a silent no-op. Rollback: dev/rollback_20261117100000.sql.
DO $m$
DECLARE n integer;
BEGIN
  -- R4 guard: an owner of either row needs it to stay available so the item still shows as owned.
  IF EXISTS (SELECT 1 FROM user_inventory ui JOIN shop_items si ON si.id = ui.shop_item_id
             WHERE si.category = 'avatar' AND si.name IN ('Wolf', 'Lion')) THEN
    RAISE EXCEPTION 'R4: an account owns Wolf or Lion through the shop; leave those rows available';
  END IF;

  UPDATE public.achievements SET coin_reward = 25, xp_reward = 50
   WHERE id = 'personal_best' AND coin_reward = 100 AND xp_reward = 200;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'R1: expected 1 personal_best row at 100/200, updated %', n; END IF;

  UPDATE public.shop_items SET is_available = false
   WHERE name IN ('Wolf', 'Lion') AND category = 'avatar' AND is_available;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 2 THEN RAISE EXCEPTION 'R4: expected 2 available shop rows (Wolf, Lion), updated %', n; END IF;

  UPDATE public.achievements SET description = 'Have 5 buddies'
   WHERE id = 'connector' AND description = 'Send 5 buddy requests';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'R5: expected 1 connector row, updated %', n; END IF;

  UPDATE public.achievements SET coin_reward = 2000
   WHERE id = 'year_of_the_beast' AND coin_reward = 5000 AND xp_reward = 5000;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'R7: expected 1 year_of_the_beast row at 5000/5000, updated %', n; END IF;
END
$m$;
