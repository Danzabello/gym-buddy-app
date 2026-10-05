-- LIVE-26 (owner decision 2026-10-05: search only after signup).
-- search_usernames was executable by anon, so anyone with the anon key could
-- enumerate usernames. Body unchanged (3-char minimum, escaped wildcards,
-- LIMIT 10). The pre-signup onboarding search now gets "permission denied",
-- which its catch swallows, so it shows no results.
REVOKE EXECUTE ON FUNCTION public.search_usernames(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.search_usernames(text) TO authenticated;
