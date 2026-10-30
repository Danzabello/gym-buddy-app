import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { categoryDisabled, isQuietHour, resolveSettings } from './settings.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// Constant-time service-key check. Both sides are hashed to 32 bytes first, so a length
// mismatch cannot short-circuit; timingSafeEqual is Deno-specific, the loop is the fallback.
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
const FIREBASE_SERVICE_ACCOUNT = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!)

// Fallback for a missing/unset user_profiles.timezone — same as
// coach-max-cron / workout-overtime-cron.
const FALLBACK_TZ = 'Europe/Dublin'

// Types a client (non-service) caller may send; keep in sync with categoryMap in settings.ts.
const CLIENT_TYPES = new Set([
  'friend_request',
  'friend_accepted',
  'workout_invite',
  'workout_accepted',
  'workout_declined',
  'workout_starting_soon',
  'buddy_started_workout',
  'join_window_expiring',
  'workout_overtime',
  'invite_received',
  'invite_accepted',
  'invite_declined',
  'invite_expired',
  'invite_rescheduled',
  'workout_cancelled',
  'time_to_start',
  'buddy_tapped_first',
  'started',
  'nudge',
  'cant_make_it',
  'buddy_left',
  'buddy_finished',
  'still_going',
  'before_auto',
  'buddy_checked_in',
  'streak_complete',
  'streak_milestone',
  'streak_danger',
  'streak_broken',
  'break_day_taken',
  'coach_max_checked_in',
  'coach_max_motivational',
  'buddy_nudge',
])
const CLIENT_HOURLY_CAP = 10

// ── tz helpers, copied verbatim from coach-max-cron / workout-overtime-cron
// (kept in sync there — each edge function deploys standalone, so no shared
// import) ────────────────────────────────────────────────────────────────
function tzParts(d: Date, tz: string): Record<string, string> {
  const fmt = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
  return Object.fromEntries(fmt.formatToParts(d).map((x) => [x.type, x.value]))
}

// Wall-clock "HH:MM:SS" in the given zone.
function localTimeOfDay(d: Date, tz: string): string {
  const p = tzParts(d, tz)
  const hh = p.hour === '24' ? '00' : p.hour // en-GB midnight edge
  return `${hh}:${p.minute}:${p.second}`
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: FIREBASE_SERVICE_ACCOUNT.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }

  const encode = (obj: object) => 
    btoa(JSON.stringify(obj))
      .replace(/=/g, '')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')

  const headerB64 = encode(header)
  const payloadB64 = encode(payload)
  const signingInput = `${headerB64}.${payloadB64}`

  const privateKey = FIREBASE_SERVICE_ACCOUNT.private_key
  const pemContents = privateKey
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\n/g, '')
  
  const binaryKey = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))
  
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput)
  )

  const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')

  const jwt = `${signingInput}.${signatureB64}`

  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })

  const tokenData = await tokenResponse.json()
  return tokenData.access_token
}

serve(async (req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    const payload = await req.json()

    const { user_id, title, body, type, reference_id, batch_key } = payload
    // H2 fields, all optional: a caller that omits them gets today's behaviour.
    const { kind, color, channel, tag, data } = payload
    const urgent = payload.urgent === true

    // ============================================
    // INPUT GUARD — user_id must be a UUID (feeds PostgREST filters below)
    // ============================================
    const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    if (!user_id || typeof user_id !== 'string' || !UUID_RE.test(user_id)) {
      return new Response(JSON.stringify({ error: 'bad_request' }), { status: 400 })
    }

    // ============================================
    // INPUT GUARD — title/body render on the target's device (Group G)
    // Strip HTML tags/comments and control/invisible chars (bidi overrides,
    // zero-width space, BOM). Keep emoji, accents, ZWJ/ZWNJ — compound emoji
    // (❤️‍🔥) and RTL scripts must survive; every legit caller uses emoji.
    // Over-cap is rejected, not truncated: real payloads top out ~30/~90
    // (display_name is client-capped at 40), so bigger means bug or abuse.
    // Caps count code points, not UTF-16 units, so emoji aren't double-billed.
    // ============================================
    const sanitize = (s: string) => s
      .replace(/<\/?[a-zA-Z][^>]*>|<!--[\s\S]*?-->/g, '')
      .replace(/[\u0000-\u001F\u007F-\u009F\u200B\u200E\u200F\u2028-\u202E\u2060-\u206F\uFEFF]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
    if (typeof title !== 'string' || typeof body !== 'string') {
      return new Response(JSON.stringify({ error: 'bad_request' }), { status: 400 })
    }
    const cleanTitle = sanitize(title)
    const cleanBody = sanitize(body)
    if (!cleanTitle || !cleanBody || [...cleanTitle].length > 100 || [...cleanBody].length > 300) {
      return new Response(JSON.stringify({ error: 'bad_request' }), { status: 400 })
    }

    // type / reference_id / batch_key aren't rendered but are stored
    // (notification_log, unbounded text columns) and forwarded (FCM data) —
    // cap them so they can't be a free-text channel. Legit max ≈ 84 chars
    // (nudge batch_key: two UUIDs + date).
    for (const [k, v] of Object.entries({ type, reference_id, batch_key, kind, color, channel, tag })) {
      if (v != null && (typeof v !== 'string' || v.length > 128)) {
        console.log(`⛔ send-notification: oversized/non-string ${k}`)
        return new Response(JSON.stringify({ error: 'bad_request' }), { status: 400 })
      }
    }
    if (color != null && !/^#[0-9A-Fa-f]{6}$/.test(color)) {
      return new Response(JSON.stringify({ error: 'bad_request' }), { status: 400 })
    }
    if (channel != null && !/^gym_buddy_[a-z_]{1,40}$/.test(channel)) {
      return new Response(JSON.stringify({ error: 'bad_request' }), { status: 400 })
    }
    // data: only these keys are forwarded, each a short string (or absent).
    const DATA_KEYS = ['avatar_id', 'avatar_border', 'ring_hex', 'sender_name', 'streak', 'style']
    const extra: Record<string, string> = {}
    if (data != null) {
      if (typeof data !== 'object' || Array.isArray(data)) {
        return new Response(JSON.stringify({ error: 'bad_request' }), { status: 400 })
      }
      for (const k of DATA_KEYS) {
        const v = data[k]
        if (v == null) continue
        if (typeof v !== 'string' || v.length > 64) {
          return new Response(JSON.stringify({ error: 'bad_request' }), { status: 400 })
        }
        extra[k] = sanitize(v)
      }
    }
    const dedupeMinutes = Math.min(Math.max(Number(payload.dedupe_minutes) || 60, 1), 1440)

    // ============================================
    // AUTHORIZATION
    // Trusted server-to-server callers (cron) present the service-role key
    // and may notify anyone. Every other caller must be the verified target's
    // friend or teammate — never trust the payload's user_id as the sender.
    // ============================================
    const authHeader = req.headers.get('Authorization') ?? ''
    const bearer = authHeader.replace(/^Bearer\s+/i, '').trim()

    if (!(await isServiceKey(bearer))) {
      const { data: userData, error: authErr } = await supabase.auth.getUser(bearer)
      const callerId = userData?.user?.id
      if (authErr || !callerId) {
        console.log('⛔ send-notification: invalid caller JWT')
        return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 })
      }

      // S-15: client callers may only send known notification types, and at most
      // CLIENT_HOURLY_CAP per hour per target. ponytail: notification_log has no sender
      // column, so the cap is per target+type, not per caller; add sender_id for a true per-caller cap.
      if (typeof type !== 'string' || !CLIENT_TYPES.has(type)) {
        console.log(`⛔ send-notification: client type not allowed: ${String(type).slice(0, 40)}`)
        return new Response(JSON.stringify({ error: 'bad_request' }), { status: 400 })
      }
      const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()
      const { count: recent } = await supabase
        .from('notification_log')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', user_id)
        .eq('notification_type', type)
        .gte('sent_at', hourAgo)
      if ((recent ?? 0) >= CLIENT_HOURLY_CAP) {
        console.log(`⛔ send-notification: hourly cap reached for ${user_id} / ${type}`)
        return new Response(JSON.stringify({ error: 'rate_limited' }), { status: 429 })
      }

      if (callerId !== user_id) {
        const allowed = await isFriendOrTeammate(supabase, callerId, user_id)
        if (!allowed) {
          console.log(`⛔ ${callerId} not authorized to notify ${user_id}`)
          return new Response(JSON.stringify({ error: 'forbidden' }), { status: 403 })
        }
      }
    }

    console.log(`🔔 send-notification called for user ${user_id}, type: ${type}`)

    // ============================================
    // QUIET HOURS & CATEGORY CHECK
    // ============================================
    const { data: settingsRow } = await supabase
      .from('notification_settings')
      .select('*')
      .eq('user_id', user_id)
      .maybeSingle()

    // No row means the defaults (quiet hours 23-7 on), same as the app's Settings page.
    const settings = resolveSettings(settingsRow)

    // Time-critical handshake pushes (urgent) ignore quiet hours.
    if (settings.quiet_hours_enabled && !urgent) {
      // Recipient's own local hour, not the server's — a UTC hour was
      // being compared against a quiet-hours window the user configured
      // in their own local time, which is wrong for anyone far from UTC.
      const { data: profile } = await supabase
        .from('user_profiles')
        .select('timezone')
        .eq('id', user_id)
        .maybeSingle()
      const tz = profile?.timezone || FALLBACK_TZ
      const hour = Number(localTimeOfDay(new Date(), tz).slice(0, 2))

      if (isQuietHour(hour, settings.quiet_hours_start, settings.quiet_hours_end)) {
        console.log(`🌙 Quiet hours - skipping`)
        return new Response(JSON.stringify({ skipped: 'quiet_hours' }), { status: 200 })
      }
    }

    if (categoryDisabled(type, settings)) {
      console.log(`🔕 Category disabled - skipping ${type}`)
      return new Response(JSON.stringify({ skipped: 'category_disabled' }), { status: 200 })
    }

    // ============================================
    // BATCHING CHECK
    // ============================================
    // A count, not maybeSingle(): with two matching rows maybeSingle() errors,
    // returns no data, and the dedupe silently let the push through.
    if (batch_key) {
      const since = new Date(Date.now() - dedupeMinutes * 60 * 1000).toISOString()
      const { count } = await supabase
        .from('notification_log')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', user_id)
        .eq('batch_key', batch_key)
        .gte('sent_at', since)

      if ((count ?? 0) > 0) {
        console.log(`📦 Already sent ${batch_key} within ${dedupeMinutes} min - batching`)
        return new Response(JSON.stringify({ skipped: 'batched' }), { status: 200 })
      }
    }

    // ============================================
    // GET DEVICE TOKENS
    // ============================================
    const { data: tokens } = await supabase
      .from('device_tokens')
      .select('token')
      .eq('user_id', user_id)

    if (!tokens || tokens.length === 0) {
      console.log(`❌ No tokens for user ${user_id}`)
      return new Response(JSON.stringify({ error: 'no_tokens' }), { status: 200 })
    }

    console.log(`📱 Found ${tokens.length} device token(s)`)

    // ============================================
    // GET ACCESS TOKEN & SEND VIA FCM V1
    // ============================================
    const accessToken = await getAccessToken()
    const projectId = FIREBASE_SERVICE_ACCOUNT.project_id
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

    const message = buildMessage(Deno.env.get('PUSH_MODE') ?? 'data', {
      title: cleanTitle, body: cleanBody, type, reference_id, kind, color, channel, tag, extra,
    })

    const results = []
    let delivered = 0
    for (const { token } of tokens) {
      const fcmResponse = await fetch(fcmUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ message: { token, ...message } }),
      })

      const result = await fcmResponse.json()
      results.push(result)
      if (result?.name) delivered++

      // Clean up stale tokens
      if (result?.error?.details?.[0]?.errorCode === 'UNREGISTERED') {
        console.log(`🗑️ Removing stale token for user ${user_id}`)
        await supabase
          .from('device_tokens')
          .delete()
          .eq('user_id', user_id)
          .eq('token', token)
      }

      console.log(`📤 FCM V1 result: ${JSON.stringify(result)}`)
    }

    // ============================================
    // LOG IT: only when FCM accepted it for at least one token, so a failed
    // send neither counts as sent nor blocks a retry through the dedupe.
    // ============================================
    if (delivered === 0) {
      console.log(`❌ No token accepted the push for user ${user_id}`)
      return new Response(JSON.stringify({ sent: false, results }), { status: 200 })
    }
    await supabase.from('notification_log').insert({
      user_id,
      notification_type: type,
      reference_id: reference_id ?? null,
      batch_key: batch_key ?? null,
    })

    console.log(`✅ Notification sent successfully for user ${user_id}`)
    return new Response(JSON.stringify({ sent: true, results }), { status: 200 })

  } catch (error) {
    console.error('❌ Error:', error)
    return new Response(JSON.stringify({ error: 'internal_error' }), { status: 500 })
  }
})

// ── FCM MESSAGE ───────────────────────────────────────────────────────────
// PUSH_MODE=data (default): data-only, the app draws the notification
// (channel, colour, tag, avatar). PUSH_MODE=notification: the kill switch,
// a plain notification message the system draws, still with channel, colour
// and tag. Everything in `data` must be a string for FCM.
function buildMessage(mode: string, p: {
  title: string, body: string, type?: string, reference_id?: string, kind?: string,
  color?: string, channel?: string, tag?: string, extra: Record<string, string>,
}) {
  const channelId = p.channel ?? 'gym_buddy_high_importance'
  // Stale nudges are worse than none; invites stay useful for a day.
  const ttl = p.type === 'nudge' || p.type === 'time_to_start' ? 600
    : channelId === 'gym_buddy_handshake' ? 3600 : 86400

  if (mode === 'notification') {
    return {
      notification: { title: p.title, body: p.body },
      data: { type: p.type ?? '', reference_id: p.reference_id ?? '' },
      android: {
        priority: 'high',
        ttl: `${ttl}s`,
        notification: {
          channel_id: channelId,
          ...(p.color ? { color: p.color } : {}),
          ...(p.tag ? { tag: p.tag } : {}),
        },
      },
    }
  }
  return {
    data: {
      title: p.title,
      body: p.body,
      type: p.type ?? '',
      reference_id: p.reference_id ?? '',
      kind: p.kind ?? '',
      color: p.color ?? '',
      channel: channelId,
      tag: p.tag ?? '',
      avatar_id: p.extra.avatar_id ?? '',
      avatar_border: p.extra.avatar_border ?? '',
      ring_hex: p.extra.ring_hex ?? '',
      sender_name: p.extra.sender_name ?? '',
      streak: p.extra.streak ?? '',
      style: p.extra.style ?? '',
    },
    android: { priority: 'high', ttl: `${ttl}s` },
  }
}

// ── AUTHORIZATION HELPER ──────────────────────────────────────────────────
// True if a and b are accepted friends OR share a buddy team.
// Both args are trusted UUIDs (caller from verified JWT, target UUID-checked).
async function isFriendOrTeammate(supabase: any, a: string, b: string): Promise<boolean> {
  const { data: friend } = await supabase
    .from('friendships')
    .select('id')
    .eq('status', 'accepted')
    .or(`and(user_id.eq.${a},friend_id.eq.${b}),and(user_id.eq.${b},friend_id.eq.${a})`)
    .limit(1)
  if (friend && friend.length > 0) return true

  const { data: aTeams } = await supabase
    .from('team_members')
    .select('team_id')
    .eq('user_id', a)
  if (!aTeams || aTeams.length === 0) return false

  const teamIds = aTeams.map((t: any) => t.team_id)
  const { data: shared } = await supabase
    .from('team_members')
    .select('id')
    .eq('user_id', b)
    .in('team_id', teamIds)
    .limit(1)

  return !!(shared && shared.length > 0)
}