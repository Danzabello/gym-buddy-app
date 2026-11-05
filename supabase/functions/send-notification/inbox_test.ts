// Run: deno test --allow-read supabase/functions/send-notification/inbox_test.ts
// (also runs under Node: node --test --experimental-strip-types <this file>)
import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { recordInbox, stripEmoji } from './inbox.ts'

const NOW = Date.parse('2026-11-05T12:00:00Z')
const ago = (min: number) => new Date(NOW - min * 60 * 1000).toISOString()

const PUSH = {
  user_id: 'u1', type: 'buddy_nudge', title: 'Ana', body: 'is waiting on your check-in.',
  quiet: false, reference_id: 'r1', batch_key: 'k1', dedupeMinutes: 60,
}

// A stand-in for the service-role client: records each lookup and insert. `count` answers a
// lookup; `selectError` / `insertError` come back as PostgREST errors; `throws` throws on from().
function fake(o: { count?: (f: Record<string, unknown>) => number, selectError?: object, insertError?: object, throws?: boolean } = {}) {
  const lookups: Record<string, unknown>[] = []
  const inserts: Record<string, unknown>[] = []
  return {
    lookups,
    inserts,
    from(table: string) {
      assert.equal(table, 'notification_inbox')
      if (o.throws) throw new Error('boom')
      return {
        select() {
          const f: Record<string, unknown> = {}
          const q = {
            eq(k: string, v: unknown) { f[k] = v; return q },
            gte(k: string, v: unknown) { f[`${k}>=`] = v; return q },
            then(res: (r: unknown) => void) {
              lookups.push(f)
              res(o.selectError ? { count: null, error: o.selectError } : { count: o.count?.(f) ?? 0, error: null })
            },
          }
          return q
        },
        insert(row: Record<string, unknown>) {
          inserts.push(row)
          return Promise.resolve({ error: o.insertError ?? null })
        },
      }
    },
  }
}

test('stripEmoji removes emoji of every shape', () => {
  const cases: Record<string, string> = {
    '🔥 7 day streak': '7 day streak',
    'Ana 💪🏽 · Day 3': 'Ana · Day 3',
    '❤️‍🔥 ok': 'ok',
    '👨‍👩‍👧 fam': 'fam',
    '🇮🇪 Dublin': 'Dublin',
    '🏴󠁧󠁢󠁳󠁣󠁴󠁿 Glasgow': 'Glasgow',
    '1️⃣ one': 'one',
    'a🏽b': 'ab',
    '☀️ morning ✔️': 'morning',
    '🔥': '',
  }
  for (const [input, want] of Object.entries(cases)) assert.equal(stripEmoji(input), want, input)
})

test('stripEmoji leaves real text alone', () => {
  for (const s of ['3½ hours, 100% #1 *', 'Zoë · Day 2', 'अक्‍क', "It's 18:30. Tap I'm here.", 'Day 7 with Team 42']) {
    assert.equal(stripEmoji(s), s)
  }
})

test('a row carries the stored text, the flag and the routing fields', async () => {
  const c = fake()
  assert.equal(await recordInbox(c, { ...PUSH, title: 'Ana 💪', quiet: true }, NOW), true)
  assert.deepEqual(c.inserts, [{
    user_id: 'u1', notification_type: 'buddy_nudge', title: 'Ana', body: 'is waiting on your check-in.',
    quiet: true, reference_id: 'r1', batch_key: 'k1',
  }])
})

test('missing reference_id and batch_key are stored as null, and no batch_key means no dedupe lookup', async () => {
  const c = fake({ count: () => 5 })
  assert.equal(await recordInbox(c, { ...PUSH, reference_id: undefined, batch_key: undefined }, NOW), true)
  assert.equal(c.lookups.length, 0)
  assert.equal(c.inserts[0].reference_id, null)
  assert.equal(c.inserts[0].batch_key, null)
})

test('an emoji-only title is stored empty; nothing left at all writes no row', async () => {
  const c = fake()
  assert.equal(await recordInbox(c, { ...PUSH, title: '🔥' }, NOW), true)
  assert.equal(c.inserts[0].title, '')
  const d = fake()
  assert.equal(await recordInbox(d, { ...PUSH, title: '🔥', body: '💪' }, NOW), false)
  assert.equal(d.inserts.length, 0)
})

test('the same batch_key inside the push window writes no second row', async () => {
  const c = fake({ count: () => 1 })
  assert.equal(await recordInbox(c, { ...PUSH, dedupeMinutes: 10 }, NOW), false)
  assert.equal(c.inserts.length, 0)
  assert.deepEqual(c.lookups, [{ user_id: 'u1', batch_key: 'k1', 'created_at>=': ago(10) }])
})

test('the same batch_key past the window writes a new row', async () => {
  const c = fake({ count: () => 0 })
  assert.equal(await recordInbox(c, PUSH, NOW), true)
  assert.equal(c.inserts.length, 1)
})

test('client cap: at the cap no row, below it a row, the lookup is target + type over the last hour', async () => {
  const at = fake({ count: (f) => (f.notification_type ? 10 : 0) })
  assert.equal(await recordInbox(at, { ...PUSH, hourlyCap: 10 }, NOW), false)
  assert.equal(at.inserts.length, 0)
  assert.deepEqual(at.lookups, [{ user_id: 'u1', notification_type: 'buddy_nudge', 'created_at>=': ago(60) }])
  const below = fake({ count: (f) => (f.notification_type ? 9 : 0) })
  assert.equal(await recordInbox(below, { ...PUSH, hourlyCap: 10 }, NOW), true)
})

test('a service caller has no cap', async () => {
  const c = fake({ count: (f) => (f.notification_type ? 999 : 0) })
  assert.equal(await recordInbox(c, PUSH, NOW), true)
  assert.equal(c.lookups.some((f) => f.notification_type), false)
})

test('fails open: a thrown client, a lookup error and an insert error all resolve to false', async () => {
  const missing = { code: 'PGRST205', message: "Could not find the table 'public.notification_inbox'" }
  assert.equal(await recordInbox(fake({ throws: true }), PUSH, NOW), false)
  assert.equal(await recordInbox(fake({ selectError: missing }), PUSH, NOW), false)
  assert.equal(await recordInbox(fake({ selectError: missing }), { ...PUSH, batch_key: null, hourlyCap: 10 }, NOW), false)
  assert.equal(await recordInbox(fake({ insertError: missing }), PUSH, NOW), false)
  assert.equal(await recordInbox(fake({ insertError: missing }), { ...PUSH, batch_key: null }, NOW), false)
})

test('a lookup error writes no row (a retry could otherwise duplicate one)', async () => {
  const c = fake({ selectError: { message: 'x' } })
  await recordInbox(c, PUSH, NOW)
  assert.equal(c.inserts.length, 0)
})

// index.ts cannot be imported (serve() runs on import), so the order is checked on its source.
test('index.ts order: category, log dedupe, quiet worked out, inbox, quiet return, tokens, FCM, log', () => {
  const src = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
  const marks = [
    'categoryDisabled(type, settings)',
    "if (batch_key) {",
    'quiet = isQuietHour(',
    'await recordInbox(',
    'if (quiet) {',
    ".from('device_tokens')\n      .select('token')",
    'fetch(fcmUrl',
    "from('notification_log').insert(",
  ]
  let at = -1
  for (const m of marks) {
    const i = src.indexOf(m)
    assert.ok(i > at, `${m} is out of order (index ${i}, previous ${at})`)
    assert.equal(src.indexOf(m, i + 1), -1, `${m} appears twice`)
    at = i
  }
})

test('index.ts sends the sanitized text to both the inbox and the phone, and caps client callers only', () => {
  const src = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
  assert.match(src, /recordInbox\(supabase, \{[^}]*title: cleanTitle, body: cleanBody/)
  assert.match(src, /title: cleanTitle, body: cleanBody, type, reference_id, kind/)
  assert.match(src, /hourlyCap: isService \? undefined : CLIENT_HOURLY_CAP/)
})
