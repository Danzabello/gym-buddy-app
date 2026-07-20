-- Recategorize + expand workout_templates for the redesigned check-in category grid.
--
-- Redesign surfaces 10 category tiles: strength, cardio, hiit, yoga (Yoga / stretch),
-- outside, sports, swimming, cycling, martial_arts, recovery.
--
-- Re-tags move existing rows so the grid groups them correctly; the `other` category
-- is emptied entirely (its two rows move to yoga / recovery). New rows fill categories
-- that had no templates. All statements are idempotent (safe to re-run).

begin;

-- ── Expand the category CHECK constraint ────────────────────────────────
-- Live constraint allowed only: strength, cardio, hiit, yoga, sports, other.
-- Add the new grid categories. `other` is retained (harmless) though we empty it.
alter table public.workout_templates
  drop constraint if exists workout_templates_category_check;
alter table public.workout_templates
  add constraint workout_templates_category_check
  check (category = any (array[
    'strength', 'cardio', 'hiit', 'yoga', 'sports', 'other',
    'cycling', 'swimming', 'outside', 'martial_arts', 'recovery'
  ]));

-- ── Re-tags (existing rows) ─────────────────────────────────────────────
-- Split single-activity categories out of the catch-all `cardio` group.
update public.workout_templates set category = 'cycling'
  where name = 'Cycling'  and category = 'cardio';
update public.workout_templates set category = 'swimming'
  where name = 'Swimming' and category = 'cardio';

-- Stretching joins the Yoga / stretch tile (keyed `yoga`).
update public.workout_templates set category = 'yoga'
  where name = 'Stretching' and category = 'other';

-- Outdoor / pickup activities move to `outside`; `sports` keeps racquet/club games.
update public.workout_templates set category = 'outside'
  where name in ('Basketball', 'Soccer') and category = 'sports';

-- Existing Walking (🚶 30min) is the recovery walk; re-tag rather than duplicate it.
update public.workout_templates set category = 'recovery'
  where name = 'Walking' and category = 'other';

-- ── New templates (fill previously empty categories) ────────────────────
insert into public.workout_templates (name, category, default_duration_minutes, emoji, is_system_template)
select v.name, v.category, v.dur, v.emoji, true
from (values
  ('Boxing',       'martial_arts', 60,  '🥊'),
  ('MMA',          'martial_arts', 60,  '🤼'),
  ('BJJ',          'martial_arts', 60,  '🥋'),
  ('Kickboxing',   'martial_arts', 45,  '🦵'),
  ('Volleyball',   'outside',      45,  '🏐'),
  ('Hiking',       'outside',      60,  '🥾'),
  ('Padel',        'sports',       60,  '🎾'),
  ('Squash',       'sports',       45,  '🎾'),
  ('Golf',         'sports',       120, '⛳'),
  ('Foam Rolling', 'recovery',     20,  '🧻'),
  ('Sauna',        'recovery',     20,  '🧖')
) as v(name, category, dur, emoji)
where not exists (
  select 1 from public.workout_templates t where t.name = v.name
);

commit;
