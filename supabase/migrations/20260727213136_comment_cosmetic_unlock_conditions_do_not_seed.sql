-- Surface the 20260727212854 caveat in the schema itself, not only in git
-- history: anyone inspecting this table sees why it is empty before they
-- consider filling it.

COMMENT ON TABLE public.cosmetic_unlock_conditions IS
'Do not seed until the milestone-verification RPC exists (see finding 2.6 follow-up). If seeded first, LevelService.grantMilestoneUnlock will silently fail on every insert — fire-and-forget call, catch block only logs under kDebugMode.';
