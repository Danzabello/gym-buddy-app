import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

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

  if (!code) {
    return new Response(renderPage(null, null, 'Invalid invite link.'), {
      headers: htmlHeaders,
      status: 400,
    })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const { data: invite, error } = await supabase
    .from('invites')
    .select('id, code, status, inviter_id, user_profiles!invites_inviter_id_fkey(username, display_name)')
    .eq('code', code)
    .maybeSingle()

  if (error || !invite) {
    return new Response(renderPage(null, null, 'This invite link is invalid or has expired.'), {
      headers: htmlHeaders,
      status: 404,
    })
  }

  if (invite.status !== 'pending') {
    return new Response(renderPage(null, null, 'This invite has already been used.'), {
      headers: htmlHeaders,
      status: 410,
    })
  }

  const profile = invite.user_profiles as { username: string; display_name: string } | null
  const inviterName = profile?.display_name || profile?.username || 'Someone'

  // Redirect to GitHub Pages with inviter name + code as params
  const pageUrl = `https://danzabello.github.io/gym-buddy-app/invite.html?code=${code}&inviter=${encodeURIComponent(inviterName)}`
  
  return new Response(null, {
    headers: {
      'Location': pageUrl,
    },
    status: 302,
  })
})

function renderPage(inviterName: string | null, code: string | null, errorMsg: string | null): string {
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
    .btn {
      display: block;
      background: linear-gradient(135deg, #00ff88, #4d9fff);
      color: #0a0a0f;
      font-family: 'Syne', sans-serif;
      font-weight: 700;
      font-size: 16px;
      padding: 16px 24px;
      border-radius: 14px;
      text-decoration: none;
      margin-bottom: 16px;
      transition: opacity 0.2s;
    }
    .btn:hover { opacity: 0.9; }
    .code-pill {
      display: inline-block;
      background: rgba(0,255,136,0.08);
      border: 1px solid rgba(0,255,136,0.2);
      color: #00ff88;
      font-size: 13px;
      padding: 6px 14px;
      border-radius: 100px;
      letter-spacing: 0.15em;
      font-family: monospace;
      margin-bottom: 24px;
    }
    .error { color: #ff6b35; font-size: 15px; }
  </style>
  ${code ? `<script>
    try { localStorage.setItem('gym_buddy_invite_code', '${code}'); } catch(e) {}
  </script>` : ''}
</head>
<body>
  <div class="card">
    ${errorMsg ? `
      <span class="emoji">&#x1F62C;</span>
      <h1>Invite <span>Not Found</span></h1>
      <p class="error">${errorMsg}</p>
      <p>Ask your buddy to send you a fresh invite link.</p>
    ` : `
      <span class="emoji">&#x1F4AA;</span>
      <h1><span>${inviterName}</span> wants to be your Gym Buddy!</h1>
      <p>Stay accountable together. You both check in daily &mdash; miss a day and the streak dies. No solo streaks. That's the point.</p>
      ${code ? `<div class="code-pill">INVITE: ${code}</div>` : ''}
      <a class="btn" href="https://play.google.com/store/apps/details?id=com.gymbuddy.app">
        Download Gym Buddy &#x1F3CB;&#xFE0F;
      </a>
      <p style="font-size:13px; margin-bottom:0;">Already have the app? Open it and your invite will be waiting.</p>
    `}
  </div>
</body>
</html>`
}