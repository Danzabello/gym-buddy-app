-- Two pre-existing orphan rows for accounts already gone (no matching
-- auth.users or user_profiles). Harmless leftovers, not caused by the
-- current delete-account flow (FK coverage there is confirmed complete).
DELETE FROM device_tokens WHERE user_id = '56b4a556-8105-40d9-bcf3-49c312461f73';
DELETE FROM weekly_break_plans WHERE user_id = 'c8880ff2-1e5a-4fa1-b595-9362e4e99ddf';
