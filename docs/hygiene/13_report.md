# Prompt 13 report: SEARCH-RATE

Date: 2026-10-29 (UTC). Migration `20261029200000_search_request_rate` is applied on live. `db push --dry-run` reports up to date. The rollback is `docs/rollback_20261029200000.sql`, and `13_rollback_test.sql` passes 4/4: the restored body matches the backup byte for byte, the ACL is restored, and the tables, trigger and function are gone.

## What changed

- **A. Search.** `search_usernames` now meters each caller in `username_search_attempts`, capped at 60 calls per 10 minutes. Over the cap it returns no rows instead of raising. Queries under 3 characters return before the meter and cost nothing. Everything else about the function is unchanged.
- **B. Friend requests.** A BEFORE INSERT trigger, `meter_friend_request`, now runs on `friendships`. It allows 20 requests per hour overall and 2 per 24 hours to the same target. Over either cap it raises `too_many_requests`.
  - The trigger only fires when `current_user = 'authenticated'`, which is a direct client insert.
  - `_meter_friend_request()` is SECURITY DEFINER. EXECUTE is revoked from PUBLIC, anon and authenticated. Trigger functions need no EXECUTE grant to fire, and R1.1 proves this.
  - The meter key is `auth.uid()`, not `NEW.user_id`. RLS WITH CHECK runs after BEFORE triggers.
- **Meter tables.** Both have RLS on and no client grants, and their sequences are revoked as well. Both prune on write and fail open.

## Server-side inserts into friendships

| Place | Handling |
|---|---|
| `create_invite_team` (SECURITY DEFINER, postgres), inserts `accepted` | Not metered: `current_user` is `postgres`. R1.5–R1.7 cover it: pairing works at the cap and is not counted. |
| Edge Functions | None insert. `send-notification` only reads. |
| Other functions, triggers, cron jobs | None. Searched every `pg_proc` body in every schema, and `cron.job`. |
| service_role / postgres direct | Not metered (R4.1, R4.2). |

## Client

- `FriendService.sendFriendRequest` maps `too_many_requests` to `FriendRequestResult.tooManyRequests`. The friends page then shows "Too many requests. Try again later."
- The only search box that calls `search_usernames` is the onboarding value-props search. It is already debounced at 400 ms, so it is unchanged.
- **Finding:** the Friends page search (`FriendService.searchUsers`) does not call `search_usernames`. It selects `user_profiles` directly, which every signed-in user can read. That path has no meter, so the new search cap is bypassable until the client is routed through the RPC and the direct read is narrowed.

## Suite

`docs/hygiene/suite/run.sh` now runs 135 assertions, up from 101:

- `grants_fresh`: 32 (G9.15 ×8, G9.16)
- `economy_suite`: 78
- `rate_suite`: 25 (new)

The outputs are in `13_suite_output_{prepush,live,negative_control}.txt`. The negative control has the tables but the old bodies and no trigger, and it fails 14 rate lines.

## Residuals

- **Count-then-insert race.** The limiter counts and then inserts without a lock, as `accept_invite` does. Parallel requests can overshoot a cap by the number in flight.
- **Upsert.** An `ON CONFLICT DO NOTHING` upsert can meter a request that never lands. This only burns the caller's own quota.
