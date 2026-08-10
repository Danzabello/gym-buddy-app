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

// 2xx so the branded card actually renders: the edge gateway serves non-2xx
// bodies as text/plain under a sandbox CSP, which shows this page as raw
// source. Flip to 404 if the status matters more than the styling.
const INVALID_STATUS = 200

const LANDING_PAGE = 'https://danzabello.github.io/gym-buddy-app/invite.html'

// One message for every outcome that depends on a real lookup: no such code,
// already accepted, or past its TTL. A caller must not be able to tell those
// apart -- the old 404-vs-410 split let anyone confirm that a code existed.
const GENERIC_INVALID = 'This invite link is invalid, expired, or has already been used.'

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

const htmlHeaders = {
  'Content-Type': 'text/html; charset=utf-8',
  'X-Content-Type-Options': 'nosniff',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const url = new URL(req.url)
  const code = url.searchParams.get('code')?.toUpperCase()

  // A missing param is a malformed request, not a lookup result: it says
  // nothing about which codes exist, so it keeps its own status.
  if (!code) {
    return htmlResponse('Invalid invite link.', 400)
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

  // Every unusable case leaves through this one door, with one status and one
  // body. Do not add a reason to this response.
  if (!usable) {
    return htmlResponse(GENERIC_INVALID, INVALID_STATUS)
  }

  // PostgREST types a to-one embed as an array; at runtime it is a single
  // object (verified against live). Cast through unknown to say so.
  const profile = invite.user_profiles as unknown as
    { username: string; display_name: string } | null
  // display_name only, no username fallback: a handle is a stronger
  // identifier than a first name, and anyone holding a valid code gets this
  // from an unauthenticated request.
  const inviterName = profile?.display_name || 'Someone'

  const pageUrl =
    `${LANDING_PAGE}?code=${encodeURIComponent(code)}&inviter=${encodeURIComponent(inviterName)}`

  return new Response(null, {
    headers: {
      'Location': pageUrl,
    },
    status: 302,
  })
})

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

// ── Error page ──────────────────────────────────────────────────────────────

function htmlResponse(message: string, status: number): Response {
  return new Response(renderPage(message), { headers: htmlHeaders, status })
}

// Takes fixed literals only -- there is no escaping here. If you ever pass
// caller-supplied text into this, escape it first.
function renderPage(message: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Gym Buddy Invite</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Syne:wght@400;700;800&display=swap');
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #0a0a0f;
      color: #f0f0f8;
      font-family: 'Syne', sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      background: #13131a;
      border: 1px solid rgba(255,255,255,0.06);
      border-radius: 24px;
      padding: 48px 32px;
      max-width: 400px;
      width: 100%;
      text-align: center;
    }
    .emoji { font-size: 64px; margin-bottom: 24px; display: block; }
    h1 { font-size: 28px; font-weight: 800; margin-bottom: 12px; line-height: 1.2; }
    h1 span {
      background: linear-gradient(135deg, #00ff88, #4d9fff);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
    }
    p { color: #6b6b85; font-size: 15px; line-height: 1.6; margin-bottom: 32px; }
    .error { color: #ff6b35; font-size: 15px; }
  </style>
</head>
<body>
  <div class="card">
    <span class="emoji">&#x1F62C;</span>
    <h1>Invite <span>Not Found</span></h1>
    <p class="error">${message}</p>
    <p>Ask your buddy to send you a fresh invite link.</p>
  </div>
</body>
</html>`
}
