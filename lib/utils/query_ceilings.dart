// Row ceilings for list reads that are small in practice but have no hard
// limit (P-9). Each is at least 10 times the realistic maximum and at least
// 3 times the largest count on live when it was set (2026-11-14), so no user
// should ever reach one. A read that can grow for ever needs paging, not a
// ceiling: those are listed in the P-9 inventory.

/// Accepted friendships of one user, and the nicknames given to them. Also
/// bounds the friends-checked-in-today read. Realistic maximum 50; largest
/// on live 5.
const int kFriendsCeiling = 500;

/// Incoming friend requests still pending. Realistic maximum 20; live 0.
const int kPendingRequestsCeiling = 200;

/// One user's workouts on one day. Realistic maximum 10; largest on live 6.
const int kDayWorkoutsCeiling = 100;

/// One user's coin rows in seven days. Realistic maximum 70; largest on
/// live 3. Also PostgREST's own default row cap.
const int kWeekCoinRowsCeiling = 1000;

/// One user's open (scheduled or in-progress) workouts on the Schedule tab.
/// Realistic maximum 30; largest on live 2 (2026-11-14).
const int kOpenWorkoutsCeiling = 300;

/// One user's check-in dates in eight days (own heatmap). Realistic maximum
/// 160 (8 days x 20 teams); largest on live 43 in 90 days. Capped at 1000 by
/// PostgREST's default row limit, so the margin is only 6 times.
const int kWeekCheckInsCeiling = 1000;

/// A friend's check-in dates in 30 days (profile dialog). Realistic maximum
/// 62 (31 days x 2 shared teams).
const int kMonthCheckInsCeiling = 700;

/// One user's team memberships. Realistic maximum 20; largest on live 6.
const int kTeamMembershipsCeiling = 200;
