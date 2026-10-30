// Pure settings logic for send-notification: no Deno globals, no URL imports, no I/O,
// so settings_test.ts can import it under Deno or Node.

export interface NotificationSettings {
  notif_social: boolean
  notif_workouts: boolean
  notif_streaks: boolean
  notif_coach_max: boolean
  quiet_hours_enabled: boolean
  quiet_hours_start: number
  quiet_hours_end: number
  live_checkin_banner: boolean
}

// Used when the recipient has no notification_settings row. These mirror
// _defaultSettings() in lib/services/notification_service.dart and the column
// defaults of public.notification_settings, and must be kept in sync by hand.
export const DEFAULT_SETTINGS: NotificationSettings = {
  notif_social: true,
  notif_workouts: true,
  notif_streaks: true,
  notif_coach_max: true,
  quiet_hours_enabled: true,
  quiet_hours_start: 23,
  quiet_hours_end: 7,
  live_checkin_banner: true,
}

// A real row's own values always win (including quiet_hours_enabled false);
// only a missing row, or a null/undefined field, falls back to the default.
export function resolveSettings(row?: Record<string, any> | null): NotificationSettings {
  if (row == null) return { ...DEFAULT_SETTINGS }
  const out: Record<string, any> = { ...row }
  for (const [k, v] of Object.entries(DEFAULT_SETTINGS)) {
    if (out[k] == null) out[k] = v
  }
  return out as NotificationSettings
}

// start > end wraps midnight; start == end is an empty window.
export function isQuietHour(hour: number, start: number, end: number): boolean {
  return start > end
    ? (hour >= start || hour < end)
    : (hour >= start && hour < end)
}

export const categoryMap: Record<string, string> = {
  'friend_request': 'notif_social',
  'friend_accepted': 'notif_social',
  'workout_invite': 'notif_workouts',
  'workout_accepted': 'notif_workouts',
  'workout_declined': 'notif_workouts',
  'workout_starting_soon': 'notif_workouts',
  'buddy_started_workout': 'notif_workouts',
  'join_window_expiring': 'notif_workouts',
  'workout_overtime': 'notif_workouts',
  'invite_received': 'notif_workouts',
  'invite_accepted': 'notif_workouts',
  'invite_declined': 'notif_workouts',
  'invite_expired': 'notif_workouts',
  'invite_rescheduled': 'notif_workouts',
  'workout_cancelled': 'notif_workouts',
  'time_to_start': 'notif_workouts',
  'buddy_tapped_first': 'notif_workouts',
  'started': 'notif_workouts',
  'nudge': 'notif_workouts',
  'cant_make_it': 'notif_workouts',
  'buddy_left': 'notif_workouts',
  'buddy_finished': 'notif_workouts',
  'still_going': 'notif_workouts',
  'before_auto': 'notif_workouts',
  'buddy_checked_in': 'notif_streaks',
  'streak_complete': 'notif_streaks',
  'streak_milestone': 'notif_streaks',
  'streak_danger': 'notif_streaks',
  'streak_broken': 'notif_streaks',
  'break_day_taken': 'notif_streaks',
  'coach_max_checked_in': 'notif_coach_max',
  'coach_max_motivational': 'notif_coach_max',
  'buddy_nudge': 'notif_streaks',
}

// True only when the mapped field is exactly false; an unknown type is never disabled.
export function categoryDisabled(type: string, settings: Record<string, any>): boolean {
  const field = categoryMap[type]
  return !!field && settings[field] === false
}
