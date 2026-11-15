-- P-5, file 2 of 2: clients no longer insert coach_max_schedule rows.
-- Prepared 2026-11-14 (data-layer pass). Applied 2026-11-15 with the owner's go-ahead for this file.
-- Design: dev/audits/p5_design.md. A grant change: table public.coach_max_schedule, role authenticated,
-- privilege INSERT (table level; there is no separate column-level INSERT grant).
-- Applied after 20261115142635_coach_max_schedule_job.sql was live and its job had been seen to run. The app
-- stopped inserting these rows in commit d2c2f9c. An older build is not broken by this: its insert fails inside a
-- try/catch that only logs, and the job has made the row.
-- After this, authenticated keeps SELECT only. service_role (the Edge Function) and postgres (the job) still insert.
-- Left in place on purpose: the INSERT policy "Users can insert their own Coach Max schedule" and the trigger
-- clamp_client_coach_max_schedule. Both are dead without the grant; the policy is counted in the held B4 file.
-- Rollback: dev/rollback_20261115144143.sql (rehearsed before the apply: run twice inside a transaction that aborts).

REVOKE INSERT ON public.coach_max_schedule FROM authenticated;
