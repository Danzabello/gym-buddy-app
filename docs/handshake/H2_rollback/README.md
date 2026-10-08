Deployed edge function sources as they were before H2 (send-notification v11,
workout-overtime-cron v1, coach-max-cron v15), downloaded with
`supabase functions download`. To roll back one, copy its folder over
supabase/functions/<name>/ and run `supabase functions deploy <name>`.
SQL side: the H2 migration's previous function bodies are in git history
(20261008180000 and earlier), and `supabase secrets unset PUSH_MODE` restores
nothing by itself; v11 never read it.
