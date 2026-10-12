# Builds docs/hygiene/05a_rollback_test.sql: apply 05a, then its rollback script, inside one DO that raises at the end
# (everything rolled back). Output lists any catalog difference between pre-state and post-rollback state.
V = "20261013000000"
strip = lambda t: "".join(l for l in t.splitlines(keepends=True) if not l.startswith("--"))
mig = strip(open(f"supabase/migrations/{V}_hygiene_05a.sql").read()).replace("SELECT cron.schedule(", "PERFORM cron.schedule(")
rb = strip(open(f"docs/rollback_{V}.sql", "rb").read().decode()).replace("SELECT cron.unschedule(", "PERFORM cron.unschedule(")
acl = lambda c: f"coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest({c}) e),'')"
fp = f"""(SELECT string_agg(k, E'\\n' ORDER BY k) FROM (
 SELECT 'fn:'||p.oid::regprocedure||':'||{acl('p.proacl')}||':'||coalesce(p.proconfig::text,'')||':'||md5(p.prosrc) k FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
 UNION ALL SELECT 'tbl:'||c.relname||':'||{acl('c.relacl')} FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p')
 UNION ALL SELECT 'pol:'||tablename||':'||policyname||':'||cmd||':'||roles::text||':'||coalesce(qual,'')||':'||coalesce(with_check,'') FROM pg_policies WHERE schemaname='public'
 UNION ALL SELECT 'idx:'||indexdef FROM pg_indexes WHERE schemaname='public'
 UNION ALL SELECT 'con:'||conrelid::regclass||':'||conname||':'||pg_get_constraintdef(oid) FROM pg_constraint WHERE connamespace='public'::regnamespace
 UNION ALL SELECT 'trg:'||tgrelid::regclass||':'||tgname FROM pg_trigger WHERE NOT tgisinternal AND tgrelid::regclass::text NOT LIKE 'storage.%'
 UNION ALL SELECT 'cron:'||jobname||':'||schedule FROM cron.job) z)"""
sql = f"""DO $t$
DECLARE a text; b text; d text;
BEGIN
a := {fp};
{mig}
{rb}
b := {fp};
SELECT string_agg(x, E'\\n') INTO d FROM (
  SELECT '- '||l x FROM unnest(string_to_array(a, E'\\n')) l WHERE l <> ALL (string_to_array(b, E'\\n'))
  UNION ALL SELECT '+ '||l FROM unnest(string_to_array(b, E'\\n')) l WHERE l <> ALL (string_to_array(a, E'\\n'))) q;
RAISE EXCEPTION E'ROLLBACK_DIFF\\n%', coalesce(d, 'IDENTICAL');
END $t$;
"""
open("docs/hygiene/05a_rollback_test.sql", "wb").write(("-- Applies 05a then its rollback in ONE DO block that raises at the end (all rolled back); prints catalog differences.\n" + sql).encode())
