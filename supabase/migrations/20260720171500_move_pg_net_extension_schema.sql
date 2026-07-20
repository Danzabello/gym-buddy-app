-- Move the pg_net extension's home schema out of public
-- (advisor lint extension_in_public, Group E / LIVE-11b).
--
-- pg_net is not relocatable (relocatable=false, so ALTER EXTENSION ... SET
-- SCHEMA is refused); the only way to change its home schema is DROP +
-- CREATE ... SCHEMA extensions. This is safe here because ALL pg_net objects
-- (http_post/http_get, the queue/response tables, types) live in the
-- extension-owned `net` schema regardless of the home schema -- the home
-- schema is pure metadata, and nothing pg_net-owned actually sits in public.
-- Every live call site (six public.notify_* trigger functions + the
-- coach-max-hourly cron job) is already `net.`-qualified and is untouched.
--
-- Verified in rollback sim (2026-07-20): bare DROP succeeds with no
-- dependents (PL/pgSQL bodies aren't dependency-tracked, so no CASCADE);
-- CREATE into `extensions` succeeds (control file does not pin a schema);
-- net.http_post invoked cron-style afterwards works and enqueues normally.
--
-- Cost of the DROP: pending rows in net.http_request_queue and the
-- net._http_response log are lost (ephemeral by design -- pg_net expires
-- responses itself). Apply away from minute 0 so the hourly cron's in-flight
-- request isn't clipped. Supabase's grant_pg_net_access event trigger
-- re-applies role grants on CREATE EXTENSION automatically.

CREATE SCHEMA IF NOT EXISTS extensions;

DROP EXTENSION pg_net;

CREATE EXTENSION pg_net SCHEMA extensions;
