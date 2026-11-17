-- Rollback for 20261117100000_reward_catalogue_data.sql. Restores the four rows to the values read from live on 2026-11-17.
-- Accounts that unlocked personal_best or year_of_the_beast while the new values were live keep what they were paid.
UPDATE public.achievements SET coin_reward = 100, xp_reward = 200 WHERE id = 'personal_best';
UPDATE public.shop_items SET is_available = true WHERE name IN ('Wolf', 'Lion') AND category = 'avatar';
UPDATE public.achievements SET description = 'Send 5 buddy requests' WHERE id = 'connector';
UPDATE public.achievements SET coin_reward = 5000 WHERE id = 'year_of_the_beast';
