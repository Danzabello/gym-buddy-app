import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  // Identify the caller from THEIR jwt -- never trust a body param, or one
  // user could delete another. verify_jwt=true also gates this at the gateway.
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return json({ error: 'missing_authorization' }, 401)

  // Pass the raw JWT to getUser() explicitly. With no arg + no persisted
  // session it errors "Auth session missing" (returned 401 in testing).
  const jwt = authHeader.replace(/^Bearer\s+/i, '')
  const asCaller = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: { user }, error: userErr } = await asCaller.auth.getUser(jwt)
  if (userErr || !user) return json({ error: 'invalid_token', detail: userErr?.message }, 401)

  const uid = user.id
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  try {
    // 1. Delete the profile. user_profiles has no FK to auth.users, so the
    //    auth-user delete below would NOT remove it; its own dependents cascade.
    const delProfile = await admin.from('user_profiles').delete().eq('id', uid)
    if (delProfile.error) throw new Error(`delete user_profiles: ${delProfile.error.message}`)

    // 2. Delete the auth user via the Admin API (hard delete). GoTrue removes
    //    the auth.users row plus auth-internal rows (sessions/identities/mfa).
    //    Public tables FK'd to auth.users follow their ON DELETE action:
    //    CASCADE deletes dependents; workouts.started_by_user_id /
    //    cancel_requested_by are ON DELETE SET NULL (migration
    //    20260718110000), so buddy workouts survive with those fields nulled.
    const delUser = await admin.auth.admin.deleteUser(uid)
    if (delUser.error) throw new Error(`admin.deleteUser: ${delUser.error.message}`)

    return json({ deleted: true, user_id: uid })
  } catch (e) {
    return json({ error: 'delete_failed', detail: String((e as Error).message ?? e) }, 500)
  }
})
