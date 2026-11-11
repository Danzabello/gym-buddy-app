// Run: deno test supabase/functions/stale-accounts-cron/stale_logic_test.ts
// (also runs under Node: node --test --experimental-strip-types <this file>)
import test from 'node:test'
import assert from 'node:assert/strict'
import { clampCap, COACH_MAX_ID, isStillStale, runStale, type Candidate, type Deps } from './stale_logic.ts'

const NOW = Date.parse('2026-11-11T12:00:00Z')
const daysAgo = (d: number) => new Date(NOW - d * 86400000).toISOString()

test('cap: default 25, whole numbers from 1, hard maximum 100', () => {
  for (const v of [undefined, null, 'x', NaN, Infinity, 0, -5]) assert.equal(clampCap(v), 25, String(v))
  assert.equal(clampCap(1), 1)
  assert.equal(clampCap(7.9), 7)
  assert.equal(clampCap(100), 100)
  assert.equal(clampCap(101), 100)
  assert.equal(clampCap(1e9), 100)
})

test('clock: the later of created_at and last_sign_in_at must be older than 30 days', () => {
  assert.equal(isStillStale({ id: 'u', created_at: daysAgo(31) }, NOW), true)
  assert.equal(isStillStale({ id: 'u', created_at: daysAgo(31), last_sign_in_at: null }, NOW), true)
  assert.equal(isStillStale({ id: 'u', created_at: daysAgo(30) }, NOW), false, 'exactly 30 days is not past it')
  assert.equal(isStillStale({ id: 'u', created_at: daysAgo(90), last_sign_in_at: daysAgo(5) }, NOW), false, 'signed in since')
  assert.equal(isStillStale({ id: 'u', created_at: daysAgo(5), last_sign_in_at: daysAgo(90) }, NOW), false, 'created recently wins')
  assert.equal(isStillStale({ id: 'u', created_at: daysAgo(90), last_sign_in_at: daysAgo(40) }, NOW), true)
  assert.equal(isStillStale({ id: 'u', created_at: 'garbage' }, NOW), false, 'an unreadable date is never stale')
  assert.equal(isStillStale({ id: COACH_MAX_ID, created_at: daysAgo(900) }, NOW), false, 'never Coach Max')
})

// A stand-in for the database and the Auth admin API, with every call recorded.
function fake(o: {
  candidates: Candidate[]
  users?: Record<string, { created_at: string, last_sign_in_at?: string | null } | null>
  finishedMidRun?: string[]
  failOn?: Record<string, 'getUser' | 'profile' | 'exists' | 'authDelete'>
  listFails?: boolean
}) {
  const calls: string[] = []
  const deps: Deps = {
    async listCandidates() {
      calls.push('list')
      if (o.listFails) throw new Error('rpc down')
      return o.candidates
    },
    async getUser(id) {
      calls.push(`getUser ${id}`)
      if (o.failOn?.[id] === 'getUser') throw new Error('auth down')
      const u = o.users && id in o.users ? o.users[id] : { created_at: daysAgo(60) }
      return u ? { id, ...u } : null
    },
    async deleteUnfinishedProfile(id) {
      calls.push(`profile ${id}`)
      if (o.failOn?.[id] === 'profile') throw new Error('profile delete failed')
    },
    async profileExists(id) {
      calls.push(`exists ${id}`)
      if (o.failOn?.[id] === 'exists') throw new Error('read failed')
      return o.finishedMidRun?.includes(id) ?? false
    },
    async deleteAuthUser(id) {
      calls.push(`authDelete ${id}`)
      if (o.failOn?.[id] === 'authDelete') throw new Error('admin.deleteUser failed')
    },
  }
  return { calls, deps }
}
const C = (id: string, paired = false): Candidate => ({ user_id: id, paired })
const run = (deps: Deps, cap = 25, dryRun = false) => runStale(deps, { cap, dryRun, now: NOW })

test('deletes each candidate: profile, a check that it is gone, then the auth user', async () => {
  const f = fake({ candidates: [C('a')] })
  const r = await run(f.deps)
  assert.deepEqual(r, { candidates: 1, deleted: 1, failed: 0, skipped: 0, note: null })
  assert.deepEqual(f.calls, ['list', 'getUser a', 'profile a', 'exists a', 'authDelete a'])
})

test('paired accounts and Coach Max are never touched or counted', async () => {
  const f = fake({ candidates: [C('p', true), C(COACH_MAX_ID), C('a')] })
  const r = await run(f.deps)
  assert.equal(r.candidates, 1)
  assert.equal(r.deleted, 1)
  assert.ok(!f.calls.some((c) => c.endsWith(' p') || c.endsWith(COACH_MAX_ID)))
})

test('the cap limits one run, oldest first as listed', async () => {
  const f = fake({ candidates: [C('a'), C('b'), C('c'), C('d')] })
  const r = await run(f.deps, 2)
  assert.equal(r.candidates, 4)
  assert.equal(r.deleted, 2)
  assert.deepEqual(f.calls.filter((c) => c.startsWith('authDelete')), ['authDelete a', 'authDelete b'])
})

test('dry run lists and counts, deletes nothing, reads no user', async () => {
  const f = fake({ candidates: [C('a'), C('b'), C('p', true)] })
  const r = await run(f.deps, 25, true)
  assert.deepEqual(r, { candidates: 2, deleted: 0, failed: 0, skipped: 0, note: null })
  assert.deepEqual(f.calls, ['list'])
})

test('signed in since the list was read: skipped, nothing deleted', async () => {
  const f = fake({ candidates: [C('a')], users: { a: { created_at: daysAgo(90), last_sign_in_at: daysAgo(1) } } })
  const r = await run(f.deps)
  assert.deepEqual(r, { candidates: 1, deleted: 0, failed: 0, skipped: 1, note: null })
  assert.deepEqual(f.calls, ['list', 'getUser a'])
})

test('auth user already gone: skipped', async () => {
  const f = fake({ candidates: [C('a')], users: { a: null } })
  assert.equal((await run(f.deps)).skipped, 1)
  assert.ok(!f.calls.some((c) => c.startsWith('profile') || c.startsWith('authDelete')))
})

test('profile finished mid-run: the auth user is kept', async () => {
  const f = fake({ candidates: [C('a')], finishedMidRun: ['a'] })
  const r = await run(f.deps)
  assert.deepEqual(r, { candidates: 1, deleted: 0, failed: 0, skipped: 1, note: null })
  assert.ok(!f.calls.some((c) => c.startsWith('authDelete')))
})

test('one failure is counted and the batch goes on', async () => {
  for (const stage of ['getUser', 'profile', 'exists', 'authDelete'] as const) {
    const f = fake({ candidates: [C('a'), C('b')], failOn: { a: stage } })
    const r = await run(f.deps)
    assert.equal(r.failed, 1, stage)
    assert.equal(r.deleted, 1, stage)
    assert.ok(f.calls.includes('authDelete b'), stage)
    assert.ok(r.note && r.note.length <= 200, stage)
  }
})

test('the note keeps the first failure only, never an id or email from the call list', async () => {
  const f = fake({ candidates: [C('a'), C('b')], failOn: { a: 'profile', b: 'authDelete' } })
  const r = await run(f.deps)
  assert.equal(r.failed, 2)
  assert.equal(r.note, 'profile delete failed')
})

test('a failed list throws before anything is touched', async () => {
  const f = fake({ candidates: [], listFails: true })
  await assert.rejects(run(f.deps), /rpc down/)
  assert.deepEqual(f.calls, ['list'])
})
