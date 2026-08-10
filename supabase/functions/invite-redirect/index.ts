import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ── Tunables ────────────────────────────────────────────────────────────────

// An invite stops working 7 days after created_at. Enforced here at read time
// only -- this function never writes, so no row is ever moved to
// status='expired'. Note that the app itself never reaches this function (the
// Android App Link intercepts the URL first), so real expiry also needs the
// same cutoff inside the accept_invite RPC.
const INVITE_TTL_DAYS = 7

// Public endpoint with no JWT, so the only caller identity available is the IP.
const RL_MAX_REQUESTS = 20
const RL_WINDOW_MINUTES = 10

const LANDING_PAGE = 'https://danzabello.github.io/gym-buddy-app/invite.html'

// One destination for every outcome that depends on a real lookup: no such
// code, already accepted, past its TTL, or a DB error. A caller must not be
// able to tell those apart -- the old 404-vs-410 split let anyone confirm that
// a code existed.
//
// It has to be a redirect rather than an inline page. The edge gateway
// rewrites any HTML body this function returns to text/plain under a sandbox
// CSP, so an inline card only ever reached users as raw source -- a GET shows
// this, HEAD hides it by having no body. invite.html renders the same "Invite
// Not Found" card from this param, and GitHub Pages does not rewrite it.
const INVALID_REDIRECT = `${LANDING_PAGE}?error=1`

// Service-role client: this endpoint authenticates nothing about the caller,
// it just looks the invite up. <any> because there are no generated DB types
// in this repo, so the table/column shapes are unchecked either way.
const supabase = createClient<any>(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const url = new URL(req.url)
  const code = url.searchParams.get('code')?.toUpperCase()

  // A missing param is a malformed request, not a lookup result: it says
  // nothing about which codes exist, so it keeps its own status rather than
  // joining the uniform redirect. Plain text because the gateway would force
  // text/plain on any HTML here anyway.
  if (!code) {
    return new Response('Invalid invite link.\n', {
      status: 400,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    })
  }

  if (await isRateLimited(req)) {
    return new Response('Too many requests. Try again shortly.\n', {
      status: 429,
      headers: {
        'Content-Type': 'text/plain; charset=utf-8',
        'Retry-After': String(RL_WINDOW_MINUTES * 60),
      },
    })
  }

  const { data: invite, error } = await supabase
    .from('invites')
    .select('status, created_at, user_profiles!invites_inviter_id_fkey(username, display_name)')
    .eq('code', code)
    .maybeSingle()

  const ttlCutoff = Date.now() - INVITE_TTL_DAYS * 86_400_000
  const usable =
    !error &&
    !!invite &&
    invite.status === 'pending' &&
    new Date(invite.created_at as string).getTime() >= ttlCutoff

  // Every unusable case leaves through this one door, to one URL. Do not add
  // a reason to this redirect.
  if (!usable) {
    return redirect(INVALID_REDIRECT)
  }

  // PostgREST types a to-one embed as an array; at runtime it is a single
  // object (verified against live). Cast through unknown to say so.
  const profile = invite.user_profiles as unknown as
    { username: string; display_name: string } | null
  // display_name only, no username fallback: a handle is a stronger
  // identifier than a first name, and anyone holding a valid code gets this
  // from an unauthenticated request.
  const inviterName = profile?.display_name || 'Someone'

  return redirect(
    `${LANDING_PAGE}?code=${encodeURIComponent(code)}&inviter=${encodeURIComponent(inviterName)}`
  )
})

// Both outcomes are 302s to the same host, so a caller cannot learn anything
// from the response shape -- only from the query string of a valid one.
function redirect(location: string): Response {
  return new Response(null, { status: 302, headers: { 'Location': location } })
}

// ── Rate limiting ───────────────────────────────────────────────────────────

// Cloudflare sets cf-connecting-ip and the client cannot spoof it;
// x-forwarded-for is the fallback. A caller we cannot identify goes into one
// shared bucket, which errs toward limiting rather than passing unmetered.
function callerIp(req: Request): string {
  return (
    req.headers.get('cf-connecting-ip') ??
    req.headers.get('x-forwarded-for')?.split(',')[0].trim() ??
    '0.0.0.0'
  )
}

// ponytail: count-then-insert, so two concurrent requests can both pass at the
// boundary. Irrelevant at 20 per 10 min; swap in a DB-side atomic counter only
// if the threshold ever gets tight.
async function isRateLimited(req: Request): Promise<boolean> {
  const windowStart = new Date(Date.now() - RL_WINDOW_MINUTES * 60_000).toISOString()
  const ip = callerIp(req)

  try {
    // Rows outside the window can no longer affect any decision. Pruning here
    // keeps the table permanently small without a cron sweep.
    await supabase.from('invite_lookup_attempts').delete().lt('attempted_at', windowStart)

    const { count, error } = await supabase
      .from('invite_lookup_attempts')
      .select('*', { count: 'exact', head: true })
      .eq('ip', ip)
      .gte('attempted_at', windowStart)
    if (error) throw error

    if ((count ?? 0) >= RL_MAX_REQUESTS) return true

    await supabase.from('invite_lookup_attempts').insert({ ip })
    return false
  } catch (e) {
    // Fail open. A limiter outage must not take the invite funnel down with
    // it: knowing which codes exist is worth less than every real click
    // working.
    console.error('invite-redirect: rate limit check failed, allowing request:', e)
    return false
  }
}

