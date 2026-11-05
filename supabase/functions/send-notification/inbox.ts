// notification_inbox write for send-notification: no Deno globals, no URL imports, so
// inbox_test.ts can import it under Deno or Node.

// Emoji only: compound emoji with their joiners, skin tones, flags and keycaps. Digits, #, *,
// accents and the ZWJ inside Indic scripts stay. \p{Emoji} is not used: it matches digits.
const EMOJI =
  /[0-9#*]️?⃣|(?:\p{Extended_Pictographic}|\p{Regional_Indicator}|\p{Emoji_Modifier})[\p{Emoji_Modifier}️\u{E0020}-\u{E007F}]*(?:‍\p{Extended_Pictographic}[\p{Emoji_Modifier}️]*)*|️/gu

export function stripEmoji(s: string): string {
  return s.replace(EMOJI, '').replace(/\s+/g, ' ').trim()
}

export interface InboxPush {
  user_id: string
  type: string
  title: string
  body: string
  quiet: boolean
  reference_id?: string | null
  sender_id?: string | null
  batch_key?: string | null
  dedupeMinutes: number
  // Set for client callers only. notification_log's hourly cap cannot see a quiet or tokenless
  // push (no log row), so without this a friend could write unlimited rows of their own text.
  // ponytail: per target+type like the log's cap, count by sender_id for a true per-caller cap.
  hourlyCap?: number
}

// Writes one row. Fails open: every failure is logged and swallowed, so a push is delivered or
// held exactly as it would be without the inbox. True only when a row was written.
export async function recordInbox(supabase: any, p: InboxPush, now = Date.now()): Promise<boolean> {
  try {
    const title = stripEmoji(p.title)
    const body = stripEmoji(p.body)
    if (!title && !body) return false

    if (p.hourlyCap != null) {
      const { count, error } = await supabase
        .from('notification_inbox')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', p.user_id)
        .eq('notification_type', p.type)
        .gte('created_at', new Date(now - 60 * 60 * 1000).toISOString())
      if (error) throw error
      if ((count ?? 0) >= p.hourlyCap) {
        console.log(`⛔ notification_inbox: hourly cap reached for ${p.user_id} / ${p.type}`)
        return false
      }
    }

    // Its own check: the log's dedupe cannot see quiet, tokenless or failed sends. A window, not
    // a unique index, because batch keys legitimately come back (buddy_checked_in_<team> daily).
    // ponytail: check-then-insert, like the log's dedupe; two simultaneous calls can leave two
    // rows. Worst case one extra line for 7 days; add a claim column if it ever shows up.
    if (p.batch_key) {
      const { count, error } = await supabase
        .from('notification_inbox')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', p.user_id)
        .eq('batch_key', p.batch_key)
        .gte('created_at', new Date(now - p.dedupeMinutes * 60 * 1000).toISOString())
      if (error) throw error
      if ((count ?? 0) > 0) return false
    }

    const row = {
      user_id: p.user_id,
      notification_type: p.type,
      title,
      body,
      quiet: p.quiet,
      reference_id: p.reference_id ?? null,
      sender_id: p.sender_id ?? null,
      batch_key: p.batch_key ?? null,
    }
    let { error } = await supabase.from('notification_inbox').insert(row)
    // pg_net is asynchronous, so the sender can delete their account before this request lands.
    // The row still belongs in the list, without the avatar, as ON DELETE SET NULL would leave it.
    if (error?.code === '23503' && row.sender_id) {
      ;({ error } = await supabase.from('notification_inbox').insert({ ...row, sender_id: null }))
    }
    if (error) throw error
    return true
  } catch (e) {
    console.error('⚠️ notification_inbox write skipped:', (e as any)?.message ?? e)
    return false
  }
}
