import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const FIREBASE_SERVICE_ACCOUNT = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!)

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

    console.log(`🔔 send-notification called for user ${user_id}, type: ${type}`)

    // ============================================
    // QUIET HOURS & CATEGORY CHECK
    // ============================================
    const { data: settings } = await supabase
      .from('notification_settings')
      .select('*')
      .eq('user_id', user_id)
      .maybeSingle()

    if (settings) {
      if (settings.quiet_hours_enabled) {
        const hour = new Date().getHours()
        const start = settings.quiet_hours_start
        const end = settings.quiet_hours_end
        const inQuietHours = start > end
          ? (hour >= start || hour < end)
          : (hour >= start && hour < end)

        if (inQuietHours) {
          console.log(`🌙 Quiet hours - skipping`)
          return new Response(JSON.stringify({ skipped: 'quiet_hours' }), { status: 200 })
        }
      }

      const categoryMap: Record<string, string> = {
        'friend_request': 'notif_social',
        'friend_accepted': 'notif_social',
        'workout_invite': 'notif_workouts',
        'workout_accepted': 'notif_workouts',
        'workout_declined': 'notif_workouts',
        'workout_starting_soon': 'notif_workouts',
        'buddy_started_workout': 'notif_workouts',
        'join_window_expiring': 'notif_workouts',
        'buddy_checked_in': 'notif_streaks',
        'streak_complete': 'notif_streaks',
        'streak_milestone': 'notif_streaks',
        'streak_danger': 'notif_streaks',
        'streak_broken': 'notif_streaks',
        'break_day_taken': 'notif_streaks',
        'coach_max_checked_in': 'notif_coach_max',
        'coach_max_motivational': 'notif_coach_max',
      }

      const categoryField = categoryMap[type]
      if (categoryField && settings[categoryField] === false) {
        console.log(`🔕 Category disabled - skipping ${type}`)
        return new Response(JSON.stringify({ skipped: 'category_disabled' }), { status: 200 })
      }
    }

    // ============================================
    // BATCHING CHECK
    // ============================================
    if (batch_key) {
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()
      const { data: recentLog } = await supabase
        .from('notification_log')
        .select('id')
        .eq('user_id', user_id)
        .eq('batch_key', batch_key)
        .gte('sent_at', oneHourAgo)
        .maybeSingle()

      if (recentLog) {
        console.log(`📦 Already sent ${batch_key} within last hour - batching`)
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

    const results = []
    for (const { token } of tokens) {
      const fcmResponse = await fetch(fcmUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data: { type, reference_id: reference_id ?? '' },
            android: {
              priority: 'high',
              notification: {
                channel_id: 'gym_buddy_high_importance',
              }
            }
          }
        }),
      })

      const result = await fcmResponse.json()
      results.push(result)

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
    // LOG IT
    // ============================================
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
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})