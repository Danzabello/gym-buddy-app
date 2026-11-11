-- The copy flag is transaction-local: set in one transaction, it is gone in the next one on the same session.
-- Both transactions roll back; nothing is written.
BEGIN;
SELECT set_config('app.checkin_copy', '1', true);
DO $$ BEGIN
  IF current_setting('app.checkin_copy', true) IS DISTINCT FROM '1' THEN RAISE EXCEPTION 'flag not set inside its own transaction'; END IF;
END $$;
ROLLBACK;
BEGIN;
DO $$ BEGIN
  RAISE EXCEPTION 'FLAG_PROBE % next transaction on the same session sees app.checkin_copy = %',
    CASE WHEN coalesce(current_setting('app.checkin_copy', true), '') = '' THEN 'PASS' ELSE 'FAIL' END,
    coalesce(quote_literal(current_setting('app.checkin_copy', true)), 'NULL');
END $$;
ROLLBACK;
