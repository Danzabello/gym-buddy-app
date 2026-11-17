-- Roll back newest to oldest: 20261116225000 must be rolled back before this file.
-- Rollback for 20261116223000_rls_initplan.sql: puts back the exact USING / WITH CHECK text of the 54 policies
-- it wrapped, as read from pg_policies on live on 2026-11-16. Roll back 20261116225000 first if it is applied (it
-- drops two of these policies). Policies that were wrapped before (notification_inbox and others) are not touched.
SET LOCAL lock_timeout = '3s';
ALTER POLICY "Users can delete own sessions" ON public.active_checkin_sessions USING ((auth.uid() = user_id));
ALTER POLICY "Users can insert own sessions" ON public.active_checkin_sessions WITH CHECK ((auth.uid() = user_id));
ALTER POLICY "Users can view own sessions" ON public.active_checkin_sessions USING ((auth.uid() = user_id));
ALTER POLICY "Users can cancel their own break days" ON public.break_day_usage USING ((auth.uid() = user_id)) WITH CHECK (((auth.uid() = user_id) AND (cancelled_at IS NOT NULL)));
ALTER POLICY "Users can view their own break days" ON public.break_day_usage USING ((auth.uid() = user_id));
ALTER POLICY "Users can view their partners' break days" ON public.break_day_usage USING ((EXISTS ( SELECT 1
   FROM ((team_streaks ts
     JOIN team_members tm1 ON (((tm1.team_id = ts.team_id) AND (tm1.user_id = auth.uid()))))
     JOIN team_members tm2 ON (((tm2.team_id = ts.team_id) AND (tm2.user_id = break_day_usage.user_id))))
  WHERE (ts.is_active = true))));
ALTER POLICY "Users can insert own nudges" ON public.buddy_nudges WITH CHECK ((auth.uid() = sender_id));
ALTER POLICY "Users can read own nudges" ON public.buddy_nudges USING ((auth.uid() = sender_id));
ALTER POLICY "Users can update teams they created" ON public.buddy_teams USING ((created_by = auth.uid()));
ALTER POLICY "Users can update their own teams" ON public.buddy_teams USING ((created_by = auth.uid()));
ALTER POLICY "Users can view teams they created" ON public.buddy_teams USING ((created_by = auth.uid()));
ALTER POLICY "Users can view their teams" ON public.buddy_teams USING ((id IN ( SELECT team_members.team_id
   FROM team_members
  WHERE (team_members.user_id = auth.uid()))));
ALTER POLICY "Users can insert their own Coach Max schedule" ON public.coach_max_schedule WITH CHECK ((user_id = auth.uid()));
ALTER POLICY "Users can update their own Coach Max schedule" ON public.coach_max_schedule USING ((user_id = auth.uid()));
ALTER POLICY "Users can view their own Coach Max schedule" ON public.coach_max_schedule USING ((user_id = auth.uid()));
ALTER POLICY "Users see own transactions" ON public.coin_transactions USING ((auth.uid() = user_id));
ALTER POLICY "Users can view check-ins for their teams and friends" ON public.daily_team_checkins USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM (team_streaks ts
     JOIN team_members tm ON ((tm.team_id = ts.team_id)))
  WHERE ((ts.id = daily_team_checkins.team_streak_id) AND (tm.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM friendships f
  WHERE ((f.status = 'accepted'::text) AND (((f.user_id = auth.uid()) AND (f.friend_id = daily_team_checkins.user_id)) OR ((f.friend_id = auth.uid()) AND (f.user_id = daily_team_checkins.user_id))))))));
ALTER POLICY "Users manage own tokens" ON public.device_tokens USING ((auth.uid() = user_id));
ALTER POLICY "Users can delete own nicknames" ON public.friend_nicknames USING ((auth.uid() = user_id));
ALTER POLICY "Users can insert own nicknames" ON public.friend_nicknames WITH CHECK ((auth.uid() = user_id));
ALTER POLICY "Users can update own nicknames" ON public.friend_nicknames USING ((auth.uid() = user_id));
ALTER POLICY "Users can view own nicknames" ON public.friend_nicknames USING ((auth.uid() = user_id));
ALTER POLICY "Users see only nicknames they set" ON public.friend_nicknames USING ((user_id = auth.uid()));
ALTER POLICY "Recipients can accept friend requests" ON public.friendships USING ((auth.uid() = friend_id));
ALTER POLICY "Users can delete friendships they're part of" ON public.friendships USING (((auth.uid() = user_id) OR (auth.uid() = friend_id)));
ALTER POLICY "Users can send friend requests" ON public.friendships WITH CHECK (((auth.uid() = user_id) AND (status = 'pending'::text) AND (friend_id <> user_id)));
ALTER POLICY "Users can view their friendships" ON public.friendships USING (((auth.uid() = user_id) OR (auth.uid() = friend_id)));
ALTER POLICY "Users can create own invites" ON public.invites WITH CHECK ((auth.uid() = inviter_id));
ALTER POLICY "Users can view own invites" ON public.invites USING (((auth.uid() = inviter_id) OR (auth.uid() = accepted_by)));
ALTER POLICY "Users read own logs" ON public.notification_log USING ((auth.uid() = user_id));
ALTER POLICY "Users manage own settings" ON public.notification_settings USING ((auth.uid() = user_id));
ALTER POLICY "Users mark own streak events seen" ON public.streak_events USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));
ALTER POLICY "Users read own streak events" ON public.streak_events USING ((user_id = auth.uid()));
ALTER POLICY "Users can update streaks for their teams" ON public.team_streaks USING ((team_id IN ( SELECT team_members.team_id
   FROM team_members
  WHERE (team_members.user_id = auth.uid()))));
ALTER POLICY "Users can view streaks for their teams" ON public.team_streaks USING ((team_id IN ( SELECT team_members.team_id
   FROM team_members
  WHERE (team_members.user_id = auth.uid()))));
ALTER POLICY user_achievements_select_own ON public.user_achievements USING ((auth.uid() = user_id));
ALTER POLICY "Users can update own inventory equip state" ON public.user_inventory USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
ALTER POLICY "Users can view partners' equipped items" ON public.user_inventory USING (((equipped = true) AND (EXISTS ( SELECT 1
   FROM ((team_streaks ts
     JOIN team_members tm1 ON (((tm1.team_id = ts.team_id) AND (tm1.user_id = auth.uid()))))
     JOIN team_members tm2 ON (((tm2.team_id = ts.team_id) AND (tm2.user_id = user_inventory.user_id))))
  WHERE (ts.is_active = true)))));
ALTER POLICY "Users see own inventory" ON public.user_inventory USING ((auth.uid() = user_id));
ALTER POLICY "Users can insert own profile" ON public.user_profiles WITH CHECK ((auth.uid() = id));
ALTER POLICY "Users can update own profile" ON public.user_profiles USING ((auth.uid() = id)) WITH CHECK ((auth.uid() = id));
ALTER POLICY "Users read own unlocked cosmetics" ON public.user_unlocked_cosmetics USING ((auth.uid() = user_id));
ALTER POLICY "Users can delete their own break plans" ON public.weekly_break_plans USING ((auth.uid() = user_id));
ALTER POLICY "Users can insert their own break plans" ON public.weekly_break_plans WITH CHECK ((auth.uid() = user_id));
ALTER POLICY "Users can update their own break plans" ON public.weekly_break_plans USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
ALTER POLICY "Users can view their own break plans" ON public.weekly_break_plans USING ((auth.uid() = user_id));
ALTER POLICY "Users can create their own workout logs" ON public.workout_logs WITH CHECK ((user_id = auth.uid()));
ALTER POLICY "Users can update their own workout logs" ON public.workout_logs USING ((user_id = auth.uid()));
ALTER POLICY "Users can view their own workout logs" ON public.workout_logs USING ((user_id = auth.uid()));
ALTER POLICY "Anyone can view system templates" ON public.workout_templates USING (((is_system_template = true) OR (created_by = auth.uid())));
ALTER POLICY "Users can create workouts" ON public.workouts WITH CHECK ((auth.uid() = user_id));
ALTER POLICY "Users can delete their workouts" ON public.workouts USING ((auth.uid() = user_id));
ALTER POLICY "Users can view their workouts" ON public.workouts USING (((auth.uid() = user_id) OR (auth.uid() = buddy_id)));
ALTER POLICY "Users can read own xp_transactions" ON public.xp_transactions USING ((auth.uid() = user_id));
