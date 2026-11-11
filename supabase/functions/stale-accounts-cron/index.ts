import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { clampCap, runStale, STALE_DAYS, type Deps } from './stale_logic.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// Constant-time service-key check (same as workout-overtime-cron).
async function isServiceKey(bearer: string): Promise<boolean> {
  const enc = new TextEncoder()
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(bearer)),
    crypto.subtle.digest('SHA-256', enc.encode(SUPABASE_SERVICE_KEY)),
  ])
  const tse = (crypto.subtle as any).timingSafeEqual
  if (typeof tse === 'function') return tse.call(crypto.subtle, a, b)
  const x = new Uint8Array(a), y = new Uint8Array(b)
  let d = 0
  for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i]
  return d === 0
}

// Deletes accounts that never finished setting up, 30 days after they were created or last signed in (prompt 44).
// Scheduled service job only: pg_cron 'stale-accounts-daily' (created OFF) sends {"cap":25} with the service-role key.
// Body: {"cap": 1..100} (default 25, hard maximum 100), {"dry_run": true} lists and logs, deletes nothing.
// The delete is delete-account's two steps for each account (the user_profiles row, then auth.admin.deleteUser); that
// function itself needs the user's own JWT, so a job cannot call it. The list comes from stale_account_candidates().
serve(async (req) => {
  try {
    const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
    if (!(await isServiceKey(bearer))) {
      console.log('⛔ stale-accounts-cron: caller is not the service role')
      return new Response(JSON.stringify({ error: 'forbidden' }), { status: 403 })
    }

    const body = await req.json().catch(() => ({}))
    const cap = clampCap(body?.cap)
    const dryRun = body?.dry_run === true

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const deps: Deps = {
      async listCandidates() {
        const { data, error } = await admin.rpc('stale_account_candidates', { p_days: STALE_DAYS })
        if (error) throw new Error(`candidates: ${error.message}`)
        return data ?? []
      },
      async getUser(id) {
        const { data, error } = await admin.auth.admin.getUserById(id)
        if (error) {
          if ((error as any).status === 404 || /not.?found/i.test(error.message)) return null
          throw new Error(`getUserById: ${error.message}`)
        }
        return data?.user ?? null
      },
      async deleteUnfinishedProfile(id) {
        const { error } = await admin.from('user_profiles').delete().eq('id', id).eq('onboarding_completed', false)
        if (error) throw new Error(`delete user_profiles: ${error.message}`)
      },
      async profileExists(id) {
        const { data, error } = await admin.from('user_profiles').select('id').eq('id', id).maybeSingle()
        if (error) throw new Error(`read user_profiles: ${error.message}`)
        return data != null
      },
      async deleteAuthUser(id) {
        const { error } = await admin.auth.admin.deleteUser(id)
        if (error) throw new Error(`admin.deleteUser: ${error.message}`)
      },
    }

    let result
    try {
      result = await runStale(deps, { cap, dryRun, now: Date.now() })
    } catch (e) {
      // Only the list can fail here: nothing was touched.
      console.error('stale-accounts-cron list_failed:', String((e as Error).message ?? e))
      return new Response(JSON.stringify({ error: 'internal_error' }), { status: 500 })
    }

    // The log row: counts only, never an email or an id. A failed write is reported, never fatal.
    const { error: logErr } = await admin.from('stale_account_runs').insert({
      mode: dryRun ? 'dry_run' : 'run', cap, candidates: result.candidates,
      deleted: result.deleted, failed: result.failed, skipped: result.skipped, note: result.note,
    })
    if (logErr) console.error('stale-accounts-cron log_failed:', logErr.message)

    console.log(`stale-accounts-cron ${dryRun ? 'dry_run' : 'run'}: cap=${cap} candidates=${result.candidates} deleted=${result.deleted} failed=${result.failed} skipped=${result.skipped}`)
    return new Response(JSON.stringify({ mode: dryRun ? 'dry_run' : 'run', cap, ...result, note: undefined }), { status: 200 })
  } catch (error) {
    console.error('stale-accounts-cron fatal:', String((error as Error).message ?? error))
    return new Response(JSON.stringify({ error: 'internal_error' }), { status: 500 })
  }
})
