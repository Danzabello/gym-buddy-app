// The decisions of stale-accounts-cron, with the database and the Auth admin API handed in: no Deno globals, no URL
// imports, so stale_logic_test.ts can import it under Deno or Node.

export const COACH_MAX_ID = '00000000-0000-0000-0000-000000000001'
export const STALE_DAYS = 30
export const DEFAULT_CAP = 25
export const MAX_CAP = 100
const DAY_MS = 24 * 60 * 60 * 1000

// A whole number from 1 to MAX_CAP; anything else (missing, text, NaN, zero, negative) is the default.
export function clampCap(v: unknown): number {
  if (typeof v !== 'number' || !Number.isFinite(v) || v < 1) return DEFAULT_CAP
  return Math.min(Math.floor(v), MAX_CAP)
}

export interface Candidate { user_id: string, paired: boolean }
export interface AuthUserLite { id: string, created_at: string, last_sign_in_at?: string | null }

// Same clock as stale_account_candidates: the later of created_at and last_sign_in_at is older than the window.
// An unreadable date is never stale.
export function isStillStale(u: AuthUserLite, now: number, days = STALE_DAYS): boolean {
  if (u.id === COACH_MAX_ID) return false
  const created = Date.parse(u.created_at)
  const signedIn = u.last_sign_in_at ? Date.parse(u.last_sign_in_at) : created
  const idle = Math.max(created, signedIn)
  return Number.isFinite(idle) && idle < now - days * DAY_MS
}

export interface Deps {
  listCandidates(): Promise<Candidate[]>
  // null when the auth user is already gone.
  getUser(id: string): Promise<AuthUserLite | null>
  // Deletes the profile row only while onboarding_completed is still false (one statement, so a user who finished a
  // moment ago is not deleted). A missing row is fine.
  deleteUnfinishedProfile(id: string): Promise<void>
  profileExists(id: string): Promise<boolean>
  deleteAuthUser(id: string): Promise<void>
}

export interface RunResult { candidates: number, deleted: number, failed: number, skipped: number, note: string | null }

// One run. Never throws for one account's trouble: it is counted and the next account goes on. A failure to list the
// candidates is the caller's (nothing was touched).
export async function runStale(deps: Deps, o: { cap: number, dryRun: boolean, now: number }): Promise<RunResult> {
  const eligible = (await deps.listCandidates()).filter((c) => !c.paired && c.user_id !== COACH_MAX_ID)
  const res: RunResult = { candidates: eligible.length, deleted: 0, failed: 0, skipped: 0, note: null }
  if (o.dryRun) return res

  const fail = (e: unknown) => {
    res.failed++
    res.note ??= String((e as Error)?.message ?? e).slice(0, 200)
  }
  for (const c of eligible.slice(0, o.cap)) {
    try {
      // Look again just before deleting: they may have signed in, or already be gone.
      const u = await deps.getUser(c.user_id)
      if (!u || !isStillStale(u, o.now)) { res.skipped++; continue }
      await deps.deleteUnfinishedProfile(c.user_id)
      // Still a row: onboarding finished after the list was read. Leave the account alone.
      if (await deps.profileExists(c.user_id)) { res.skipped++; continue }
      await deps.deleteAuthUser(c.user_id)
      res.deleted++
    } catch (e) {
      fail(e)
    }
  }
  return res
}
