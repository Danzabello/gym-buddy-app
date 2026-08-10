-- Rate-limit ledger for the public invite-redirect Edge Function.
--
-- invite-redirect is the one endpoint with verify_jwt = false, so it is
-- reachable by anyone with no credentials. Before this table there was no
-- server-side rate limiting anywhere in the project, which left invite-code
-- lookups unmetered. The function keys a 20-request / 10-minute window on the
-- caller IP and prunes rows outside that window on every request, so the table
-- stays tiny and needs no cron sweep.
--
-- Raw inet rather than a hash: retention is bounded by the prune (~10 min) and
-- nothing but the service_role key can read the table. An unpeppered hash of an
-- IPv4 address is brute-forceable in seconds, so hashing would only help with a
-- managed pepper secret -- not worth the moving parts at this retention.

create table public.invite_lookup_attempts (
  id           bigserial   primary key,
  ip           inet        not null,
  attempted_at timestamptz not null default now()
);

create index invite_lookup_attempts_ip_time_idx
  on public.invite_lookup_attempts (ip, attempted_at desc);

-- RLS on with zero policies: only the service_role key touches this table, and
-- it bypasses RLS. The explicit REVOKE is because new tables in public pick up
-- default grants for anon/authenticated on this instance.
alter table public.invite_lookup_attempts enable row level security;
revoke all on table public.invite_lookup_attempts from anon, authenticated;
