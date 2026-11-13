-- Indexes for the foreign keys the performance advisor lists as unindexed (tracker: "Perf: unindexed FKs").
-- Additive only: no grant, policy or function changes.
-- Left out: the FKs on check_ins and daily_check_ins (legacy tables with no caller, handled in their own migration).
-- Rollback: dev/rollback_20261113231552.sql

CREATE INDEX IF NOT EXISTS idx_friendships_friend_id            ON public.friendships (friend_id);
CREATE INDEX IF NOT EXISTS idx_friend_nicknames_friend_id       ON public.friend_nicknames (friend_id);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id            ON public.device_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_notification_inbox_sender_id     ON public.notification_inbox (sender_id);
CREATE INDEX IF NOT EXISTS idx_buddy_nudges_receiver_id         ON public.buddy_nudges (receiver_id);
CREATE INDEX IF NOT EXISTS idx_user_inventory_shop_item_id      ON public.user_inventory (shop_item_id);
CREATE INDEX IF NOT EXISTS idx_user_achievements_achievement_id ON public.user_achievements (achievement_id);
CREATE INDEX IF NOT EXISTS idx_user_unlocked_cosmetics_item_id  ON public.user_unlocked_cosmetics (shop_item_id);
CREATE INDEX IF NOT EXISTS idx_shop_items_unlock_achievement_id ON public.shop_items (unlock_achievement_id);
CREATE INDEX IF NOT EXISTS idx_workout_logs_team_id             ON public.workout_logs (team_id);
CREATE INDEX IF NOT EXISTS idx_workout_logs_buddy_id            ON public.workout_logs (buddy_id);
CREATE INDEX IF NOT EXISTS idx_workout_templates_created_by     ON public.workout_templates (created_by);
CREATE INDEX IF NOT EXISTS idx_streak_events_missed_user_id     ON public.streak_events (missed_user_id);
CREATE INDEX IF NOT EXISTS idx_dead_letters_invite_id           ON public.invite_reward_dead_letters (invite_id);
CREATE INDEX IF NOT EXISTS idx_dead_letters_inviter_id          ON public.invite_reward_dead_letters (inviter_id);
