-- Ring Colors cosmetic system: shop_items schema + seed data.
--
-- Backfilled: this was applied directly to the live project during
-- development and was never captured as a migration until now. Mirrors
-- e1a14a0's precedent for tracking already-live, previously-untracked
-- schema. Idempotent (IF NOT EXISTS / ON CONFLICT DO NOTHING) since the
-- columns and rows already exist live.
ALTER TABLE public.shop_items
  ADD COLUMN IF NOT EXISTS color_hex text,
  ADD COLUMN IF NOT EXISTS unlock_achievement_id text
    REFERENCES public.achievements(id);

INSERT INTO public.shop_items
  (id, name, description, category, cost, asset_id, is_available, unlock_level, color_hex, unlock_achievement_id)
VALUES
  ('777d7a64-631e-41b3-97a8-2c8ea5a352a7', 'Coral Ring', 'A warm coral check-in ring.', 'ring_color', 150, 'ring_coral', true, 2, '#FF6F5E', null),
  ('804d0be5-a916-44ed-84c9-f8a46fe83cea', 'Sky Teal Ring', 'A cool teal check-in ring.', 'ring_color', 250, 'ring_sky_teal', true, 4, '#3FC1C9', null),
  ('09ca46ba-4538-472b-b2fd-5451b66e7728', 'Violet Bloom Ring', 'A rich violet check-in ring.', 'ring_color', 300, 'ring_violet_bloom', true, 1, '#9B5DE5', null),
  ('028e8ca7-e11d-4d7d-992a-598357a3e969', 'Rose Quartz Ring', 'A soft rose check-in ring.', 'ring_color', 300, 'ring_rose_quartz', true, 1, '#FF8FA3', null),
  ('41e3e5eb-375e-4931-b72c-6d813245cc4c', 'Ocean Blue Ring', 'A deep ocean-blue check-in ring.', 'ring_color', 350, 'ring_ocean_blue', true, 1, '#2E86AB', null),
  ('13d7bfb2-76fb-4f5c-979d-424231d5744a', 'Mint Frost Ring', 'A crisp mint check-in ring.', 'ring_color', 350, 'ring_mint_frost', true, 1, '#6FE7DD', null),
  ('6cfd777a-2379-4681-8c2c-c2d30c392040', 'Sunflower Gold Ring', 'A bright gold check-in ring.', 'ring_color', 400, 'ring_sunflower_gold', true, 6, '#FFC93C', null),
  ('6c828fb7-3e9b-4753-b1e5-00c1740bc02a', 'Molten Bronze Ring', 'Exclusive ring color -- unlocked by the Century Club achievement.', 'ring_color', 0, 'ring_molten_bronze', true, 1, '#CD7F32', 'century_club'),
  ('80f8c12e-1b91-4ca0-8222-9c67c5cfe875', 'Crown Gold Ring', 'Exclusive ring color -- unlocked by the Year of the Beast achievement.', 'ring_color', 0, 'ring_crown_gold', true, 1, '#FFD700', 'year_of_the_beast')
ON CONFLICT (id) DO NOTHING;
