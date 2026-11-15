// Row ceilings for list reads that are small in practice but have no hard
// limit (P-9). Each is at least 10 times the realistic maximum and at least
// 3 times the largest count on live when it was set (2026-11-14), so no user
// should ever reach one. A read that can grow for ever needs paging, not a
// ceiling: those are listed in the P-9 inventory.

/// Accepted friendships of one user, and the nicknames given to them.
/// Realistic maximum 50; largest on live 5.
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
