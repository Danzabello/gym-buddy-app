-- Rollback for 20261113231552_fk_indexes.sql
DROP INDEX IF EXISTS public.idx_buddy_nudges_receiver_id;
DROP INDEX IF EXISTS public.idx_dead_letters_invite_id;
DROP INDEX IF EXISTS public.idx_dead_letters_inviter_id;
DROP INDEX IF EXISTS public.idx_device_tokens_user_id;
DROP INDEX IF EXISTS public.idx_friend_nicknames_friend_id;
DROP INDEX IF EXISTS public.idx_friendships_friend_id;
DROP INDEX IF EXISTS public.idx_notification_inbox_sender_id;
DROP INDEX IF EXISTS public.idx_shop_items_unlock_achievement_id;
DROP INDEX IF EXISTS public.idx_streak_events_missed_user_id;
DROP INDEX IF EXISTS public.idx_user_achievements_achievement_id;
DROP INDEX IF EXISTS public.idx_user_inventory_shop_item_id;
DROP INDEX IF EXISTS public.idx_user_unlocked_cosmetics_item_id;
DROP INDEX IF EXISTS public.idx_workout_logs_buddy_id;
DROP INDEX IF EXISTS public.idx_workout_logs_team_id;
DROP INDEX IF EXISTS public.idx_workout_templates_created_by;
