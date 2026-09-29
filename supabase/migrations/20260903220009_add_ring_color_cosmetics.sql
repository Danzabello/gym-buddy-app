-- Add ring-color support to existing shop_items table
ALTER TABLE shop_items
  ADD COLUMN color_hex text NULL,
  ADD COLUMN unlock_achievement_id text NULL REFERENCES achievements(id);

-- Level-tier ring colors (purchasable + level-gated, same pattern as avatars/frames/badges)
INSERT INTO shop_items (name, description, category, cost, emoji, asset_id, unlock_level, is_available, color_hex)
VALUES
  ('Coral Ring',           'A warm coral check-in ring.',        'ring_color', 150, null, 'ring_coral',           2, true, '#FF6F5E'),
  ('Sky Teal Ring',        'A cool teal check-in ring.',         'ring_color', 250, null, 'ring_sky_teal',        4, true, '#3FC1C9'),
  ('Sunflower Gold Ring',  'A bright gold check-in ring.',       'ring_color', 400, null, 'ring_sunflower_gold',  6, true, '#FFC93C'),
  ('Violet Bloom Ring',    'A rich violet check-in ring.',       'ring_color', 300, null, 'ring_violet_bloom',    1, true, '#9B5DE5'),
  ('Rose Quartz Ring',     'A soft rose check-in ring.',         'ring_color', 300, null, 'ring_rose_quartz',     1, true, '#FF8FA3'),
  ('Ocean Blue Ring',      'A deep ocean-blue check-in ring.',   'ring_color', 350, null, 'ring_ocean_blue',      1, true, '#2E86AB'),
  ('Mint Frost Ring',      'A crisp mint check-in ring.',        'ring_color', 350, null, 'ring_mint_frost',      1, true, '#6FE7DD');

-- Achievement-locked ring colors: cost 0, NOT purchasable -- granted automatically by trigger below
INSERT INTO shop_items (name, description, category, cost, emoji, asset_id, unlock_level, is_available, color_hex, unlock_achievement_id)
VALUES
  ('Molten Bronze Ring', 'Exclusive ring color -- unlocked by the Century Club achievement.',    'ring_color', 0, null, 'ring_molten_bronze', 1, true, '#CD7F32', 'century_club'),
  ('Crown Gold Ring',    'Exclusive ring color -- unlocked by the Year of the Beast achievement.', 'ring_color', 0, null, 'ring_crown_gold',    1, true, '#FFD700', 'year_of_the_beast');

-- Auto-grant achievement-locked ring colors into user_inventory the moment the achievement unlocks
CREATE OR REPLACE FUNCTION public._grant_achievement_shop_items()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.unlocked_at IS NOT NULL AND OLD.unlocked_at IS NULL THEN
    INSERT INTO user_inventory (user_id, shop_item_id, equipped, purchased_at)
    SELECT NEW.user_id, si.id, false, now()
    FROM shop_items si
    WHERE si.unlock_achievement_id = NEW.achievement_id
    ON CONFLICT (user_id, shop_item_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._grant_achievement_shop_items() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._grant_achievement_shop_items() TO authenticated;

DROP TRIGGER IF EXISTS trg_grant_achievement_shop_items ON user_achievements;
CREATE TRIGGER trg_grant_achievement_shop_items
AFTER INSERT OR UPDATE OF unlocked_at ON user_achievements
FOR EACH ROW
EXECUTE FUNCTION public._grant_achievement_shop_items();
