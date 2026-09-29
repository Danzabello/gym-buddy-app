-- Level path species swap to Shark/Tiger under the new Wolf hub (forest
-- layout). Wolf/Lion shop_items rows (447e6731.../7f4536a9...) are
-- intentionally left untouched — the tree screen excludes them client-side
-- by asset_id rather than by editing their unlock_path/unlock_tier, since
-- those columns still legitimately describe their old Level-path role and
-- nothing else in the app reads them as gated items.
INSERT INTO public.shop_items
  (name, description, category, cost, emoji, asset_id, is_available, unlock_level, unlock_path, unlock_tier)
VALUES
  ('Shark', 'Speed & precision — unlocked at level 5',  'avatar', 350, '🦈', 'shark', true, 5,  'level', 1),
  ('Tiger', 'Ferocity & focus — unlocked at level 15',  'avatar', 550, '🐯', 'tiger', true, 15, 'level', 2);
