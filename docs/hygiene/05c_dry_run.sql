-- 05c dry run: READ ONLY. Prints exactly what 05c will drop or delete, with counts. Run:
--   supabase db query --linked -f docs/hygiene/05c_dry_run.sql
with allowed(uid, label) as (values
  ('5e67f64d-16e3-4b09-9b00-ddc49df8c3f6'::uuid,'rokitest1'), ('6ef4e82e-a54d-4b91-8ce4-b5f179a65f66','newesttest'),
  ('cf4946f5-f921-4e81-bbf4-88d574e8baf5','testtest1'), ('6dfac56a-74a1-4a60-b7fa-e200338350f3','mijotest'),
  ('f7c1ef63-3b93-401d-b2bb-8402ddf9a881','mijotest3'), ('00000000-0000-0000-0000-000000000001','Coach Max')),
tt as (select b.id, left(b.id::text,8) p from public.buddy_teams b
       where left(b.id::text,8) in ('d168695d','3847194a','a3ae42dc','c06f57ea','05c20a6a','bd6736f1','dc1ee1ab','2a45a481','0e596a48','c2e4b37e')),
teamrows as (
  select tt.p, (select count(*) from public.team_members m where m.team_id=tt.id) members,
         (select count(*) from public.team_members m where m.team_id=tt.id and m.user_id not in (select uid from allowed)) non_test_members,
         (select string_agg(coalesce(up.display_name,'?'), ', ') from public.team_members m left join public.user_profiles up on up.id=m.user_id where m.team_id=tt.id) who,
         (select count(*) from public.team_streaks s where s.team_id=tt.id) streaks,
         (select count(*) from public.daily_team_checkins d join public.team_streaks s on s.id=d.team_streak_id where s.team_id=tt.id) checkins,
         (select count(*) from public.streak_events e where e.team_id=tt.id) streak_events,
         (select count(*) from public.workout_logs w where w.team_id=tt.id) workout_logs,
         (select count(*) from public.team_streaks s where s.team_id=tt.id and left(s.id::text,8)='d557efec') protected_streak
  from tt)
select 1 ord, 'DROP TABLE workout_invites' item, (select count(*) from public.workout_invites)::text || ' rows; ' ||
       (select count(*) from pg_trigger where tgrelid='public.workout_invites'::regclass and not tgisinternal) || ' triggers, ' ||
       (select count(*) from pg_policies where tablename='workout_invites') || ' policies, ' ||
       (select count(*) from pg_indexes where tablename='workout_invites') || ' indexes; code callers: 0 (Dart hits are the widget file workout_invites_list.dart)' detail
union all select 2, 'DROP FUNCTION ' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       'callers in other functions: ' || (select count(*) from pg_proc q where q.pronamespace='public'::regnamespace and q.oid<>p.oid and q.prosrc ~ p.proname)
       || '; policies: ' || (select count(*) from pg_policies where coalesce(qual,'')||coalesce(with_check,'') ~ p.proname)
       || '; cron: ' || (select count(*) from cron.job where command ~ p.proname) || '; Dart/edge: 0'
  from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('notify_workout_invite','notify_workout_invite_response','is_user_in_active_workout','get_workouts_awaiting_creator_join')
union all select 3, 'DROP COLUMN workouts.ready_expires_at', (select count(*) from public.workouts where ready_expires_at is not null) || ' non-null values; references: 0'
union all select 3, 'DROP COLUMN workouts.creator_popup_shown', (select count(*) from public.workouts where creator_popup_shown) || ' true values; only reader is get_workouts_awaiting_creator_join (dropped above)'
union all select 3, 'DROP COLUMN user_profiles.workout_join_popups_enabled', (select count(*) from public.user_profiles where workout_join_popups_enabled is distinct from true) || ' rows differ from default; column grants INSERT/UPDATE to authenticated go with it; get_my_profile() is SELECT * so it follows'
union all select 4, 'KEEP creator_ready / buddy_ready', 'still used by ' || (select count(*) from pg_proc where pronamespace='public'::regnamespace and prosrc ~ 'buddy_ready|creator_ready') || ' live handshake functions'
union all select 5, 'DELETE team ' || t.p, case when t.non_test_members = 0 and t.protected_streak = 0 then 'APPROVED' else 'SKIPPED (non-test member or protected streak)' end
       || ' members=' || t.members || ' [' || coalesce(t.who,'none') || '] streaks=' || t.streaks || ' checkins=' || t.checkins || ' streak_events=' || t.streak_events || ' workout_logs=' || t.workout_logs
  from teamrows t
union all select 6, 'TOTAL approved team deletes', count(*) filter (where non_test_members=0 and protected_streak=0)::text || ' teams; checkins ' || coalesce(sum(checkins) filter (where non_test_members=0 and protected_streak=0),0) || '; streaks ' || coalesce(sum(streaks) filter (where non_test_members=0 and protected_streak=0),0) || '; members ' || coalesce(sum(members) filter (where non_test_members=0 and protected_streak=0),0) from teamrows
union all select 7, 'DELETE vault secret by id', id::text || ' created ' || created_at::date || '; value is ' ||
       case when decrypted_secret = (select decrypted_secret from vault.decrypted_secrets where name='service_role_key') then 'IDENTICAL to service_role_key' else 'NOT the service_role_key' end
       || '; JWT role claim: ' || coalesce((select convert_from(decode(translate(split_part(decrypted_secret,'.',2),'-_','+/') || repeat('=', (4 - length(split_part(decrypted_secret,'.',2)) % 4) % 4), 'base64'),'UTF8')::jsonb->>'role'), 'n/a')
       || '; consumers found: 0'
  from vault.decrypted_secrets where name <> 'service_role_key'
union all select 8, 'CREATE trigger scrub team_name', 'BEFORE DELETE ON user_profiles; replaces the deleted user''s display name in "A & B" team names with "Former buddy" (non-Coach-Max teams only)'
order by 1, 2;
