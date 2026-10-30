// Run: deno test supabase/functions/send-notification/settings_test.ts
// (also runs under Node: node --test --experimental-strip-types <this file>)
import test from 'node:test'
import assert from 'node:assert/strict'
import { categoryDisabled, DEFAULT_SETTINGS, isQuietHour, resolveSettings } from './settings.ts'

const CLIENT_DEFAULTS = {
  notif_social: true,
  notif_workouts: true,
  notif_streaks: true,
  notif_coach_max: true,
  quiet_hours_enabled: true,
  quiet_hours_start: 23,
  quiet_hours_end: 7,
  live_checkin_banner: true,
}

test('resolveSettings(null) equals the eight client defaults exactly', () => {
  assert.deepEqual(resolveSettings(null), CLIENT_DEFAULTS)
  assert.deepEqual(resolveSettings(undefined), CLIENT_DEFAULTS)
  assert.deepEqual(DEFAULT_SETTINGS, CLIENT_DEFAULTS)
})

test('a real row is returned unchanged', () => {
  const row = { ...CLIENT_DEFAULTS, quiet_hours_enabled: false, quiet_hours_start: 17, quiet_hours_end: 7, notif_streaks: false }
  assert.deepEqual(resolveSettings(row), row)
})

test('null fields fall back to the defaults field by field', () => {
  const row = { user_id: 'u', notif_social: false, notif_workouts: null, quiet_hours_enabled: null, quiet_hours_start: 22, quiet_hours_end: null }
  assert.deepEqual(resolveSettings(row), {
    ...CLIENT_DEFAULTS,
    user_id: 'u',
    notif_social: false,
    quiet_hours_start: 22,
  })
})

test('isQuietHour 23 to 7 wraps midnight', () => {
  const expected: Record<number, boolean> = { 22: false, 23: true, 0: true, 6: true, 7: false, 12: false }
  for (const [h, q] of Object.entries(expected)) assert.equal(isQuietHour(Number(h), 23, 7), q, `hour ${h}`)
})

test('isQuietHour 13 to 15 is a same-day window', () => {
  const expected: Record<number, boolean> = { 12: false, 13: true, 14: true, 15: false }
  for (const [h, q] of Object.entries(expected)) assert.equal(isQuietHour(Number(h), 13, 15), q, `hour ${h}`)
})

test('isQuietHour start == end is never quiet', () => {
  for (let h = 0; h < 24; h++) assert.equal(isQuietHour(h, 9, 9), false, `hour ${h}`)
})

test('categoryDisabled: streaks-off row disables buddy_checked_in', () => {
  const s = resolveSettings({ notif_streaks: false })
  assert.equal(categoryDisabled('buddy_checked_in', s), true)
  assert.equal(categoryDisabled('nudge', s), false)
})

test('categoryDisabled: defaults disable nothing', () => {
  assert.equal(categoryDisabled('buddy_checked_in', resolveSettings(null)), false)
  assert.equal(categoryDisabled('friend_request', resolveSettings(null)), false)
  assert.equal(categoryDisabled('coach_max_checked_in', resolveSettings(null)), false)
})

test('categoryDisabled: an unknown type is never disabled', () => {
  const allOff = resolveSettings({ notif_social: false, notif_workouts: false, notif_streaks: false, notif_coach_max: false })
  assert.equal(categoryDisabled('not_a_type', allOff), false)
  assert.equal(categoryDisabled('constructor', allOff), false)
})
