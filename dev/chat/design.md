# Buddy chat: design

One-to-one text chat between two buddies. Every message disappears 24 hours after it was sent.
Stories are in [user_stories.md](user_stories.md); story numbers (S1, E2, ...) are used below.
The UI brief is in [mockup_brief.md](mockup_brief.md).

Status: server and service layer are written, nothing is applied or deployed, and there is no UI. `kShowChatEntryPoints` stays `false`.

## 1. Scope

- **In:** text messages between two people who are accepted buddies (`friendships.status = 'accepted'`), a push when a message arrives, block, report.
- **Who is a buddy** is decided by the flows that exist today and is not changed here: a friend request the other person accepted, or an invite code that was redeemed. Whoever is a buddy can chat.
- **Out:** team chat, photos, voice, reactions, read receipts, typing indicators, deleting a sent message, an unread marker. Team chat is a separate feature with different rules (who can read, who can remove) and is not started here.
- **Coach Max** and any account with `user_profiles.is_bot = true` cannot send or receive chat messages. The send function refuses both directions.
- Chat awards nothing: no coins, XP, streak credit or rest tokens. No existing function body is changed. Chat takes none of the credit-path locks.

## 2. Decisions

Each row is the default taken for this build. Rows marked **confirm** are choices the owner should look at before the migration is applied.

| # | Choice | Alternative | Cost of the alternative | |
|---|---|---|---|---|
| D1 | Accepted buddies only, one-to-one | Team chat | New membership and moderation rules; out of scope | |
| D2 | A conversation is the `friendships` row. Messages carry `friendship_id`; removing the buddy clears it, and a message without a friendship is visible to nobody | A `conversations` table | One more table with its own clean-up for removal and account deletion | |
| D3 | Expiry is 24 hours from the server's send time. Reads filter it in RLS, and a job deletes expired rows every 10 minutes | Job only | A late job would show expired messages | |
| D4 | Text only, 1 to 500 characters after trimming | 1000 or more | Longer reports and pushes of the limit; 500 matches workout notes | confirm |
| D5 | Messages are written only by `send_chat_message` (SECURITY DEFINER). Clients hold no INSERT, UPDATE or DELETE on the table | Direct INSERT under RLS | RLS cannot count messages for the rate limit, and the buddy, block and bot checks would each need a policy subquery | |
| D6 | The client creates the message id (UUID v4). A retry with the same id returns the stored message | Server ids plus a client token column | One more column and index for the same result | |
| D7 | Rate limit per sender, all conversations together: 20 messages a minute and 200 an hour | Per conversation | A sender with many buddies could send many times the limit | confirm |
| D8 | Push text is generic: the buddy's name (the nickname the receiver gave them, if any) and "sent you a message". No message text | Message preview in the push | Message text would sit in Firebase, the lock screen and the 7-day notification inbox, past the 24 hours | |
| D9 | At most one push per buddy per 5-minute window | One push per message | Up to 20 buzzes a minute from one buddy | confirm |
| D9b | Chat pushes use the existing Friends channel and the Social toggle | A new Chat channel and toggle | App and settings changes; can be added with the UI | confirm |
| D10 | Open app gets new messages through Supabase Realtime (INSERT changes under RLS on a private channel), with a 60-second reload as a safety net | Polling only | A few seconds of delay on every message and one request every few seconds per open chat | |
| D11 | Removing a buddy hides the conversation at once for both people. The rows stay stored, readable by no client, until their 24 hours are up, so the receiver can still report them. Becoming buddies again starts empty | Delete the rows at the moment of removal | Someone could send an abusive message and remove the buddy to erase it before it is reported | confirm |
| D12 | Account deletion deletes the user's messages (both directions) and block rows at once. Report copies stay until their 30 days are up; the report's account columns are cleared, the copy inside it keeps the ids and names as they were | Delete reports with the account | Deleting the account would erase the evidence against it | confirm |
| D13 | Block is chat-only, stops sending in both directions, hides the conversation from the blocker, and can be undone | Block also removes the buddy | Loses the shared streak without asking; the user can remove the buddy separately | confirm |
| D14 | A blocked sender is told "You can't message this buddy" and nothing is stored | Accept and silently drop | The sender is misled, and a retry looks like a bug | confirm |
| D15 | Only the receiver of a message can report it. The report stores a server-made copy of the message, the 5 messages before it and the 2 after it | Client sends the text; or a wider copy | A report could be forged; a wide copy keeps more of an ordinary conversation for 30 days than a review needs | |
| D15b | Report limits: 20 a day per reporter, 5 a day about one person. Block list limit: 200 | No limits | Reports could be used to keep a whole conversation, or to flood the review queue | |
| D16 | Reports are deleted 30 days after they are made | 90 days or longer | Would outlast the public promise that account data is deleted within 30 days | confirm |
| D17 | Moderation is by hand in the Supabase dashboard. Actions: dismiss, warn by email, delete the account (existing runbook) | A chat suspension table checked by the send function | One more table and check; add it when deleting the account is too blunt | confirm |
| D18 | A conversation load returns the newest 300 unexpired messages | Paging | More client code; 300 is far above normal use in 24 hours | |
| D19 | No unsend, read receipts or unread marker in this version | Build them now | Each needs new state (stories L1, L2, L5) | |

## 3. Data model

Three new tables in `public`. All have RLS enabled, nothing for `anon`, and only the grants listed.

### 3.1 `chat_messages`

| Column | Type | Rule |
|---|---|---|
| `id` | uuid | Primary key. Created by the client (D6) |
| `friendship_id` | uuid | `REFERENCES friendships(id) ON DELETE SET NULL`. Never null when the row is written; cleared when the buddy is removed |
| `sender_id` | uuid, not null | Set by the send function to `auth.uid()`. `REFERENCES user_profiles(id) ON DELETE CASCADE` |
| `recipient_id` | uuid, not null | The other party of the friendship. `REFERENCES user_profiles(id) ON DELETE CASCADE` |
| `body` | text, not null | `CHECK (char_length(body) BETWEEN 1 AND 500)` and `CHECK (body ~ '\S')` |
| `created_at` | timestamptz, not null | Server clock, set by the send function. Expiry is `created_at + 24 hours` |

- `CHECK (sender_id <> recipient_id)`.
- **Sender must be a participant.** A trigger (`_chat_message_guard`) rejects a new row unless `friendship_id` is an accepted friendship whose two parties are exactly `sender_id` and `recipient_id`. On update it rejects any change to the sender or the recipient, and any change to `friendship_id` other than clearing it. This holds for every writer, not only the send function.
- Indexes: `(friendship_id)` for the buddy-removal update; `(sender_id, created_at)` for loading and the rate limit; `(recipient_id)` for account deletion; `(created_at)` for the expiry job.
- Replica identity stays the default, so a Realtime delete event carries the row id only.

### 3.2 `chat_blocks`

| Column | Type | Rule |
|---|---|---|
| `blocker_id` | uuid, not null | `REFERENCES user_profiles(id) ON DELETE CASCADE` |
| `blocked_id` | uuid, not null | `REFERENCES user_profiles(id) ON DELETE CASCADE` |
| `created_at` | timestamptz, not null | default `now()` |

- Primary key `(blocker_id, blocked_id)`; `CHECK (blocker_id <> blocked_id)`; index on `(blocked_id)` for the cascade.
- Written only by `set_chat_block`.

### 3.3 `chat_reports`

| Column | Type | Rule |
|---|---|---|
| `id` | uuid | Primary key, `gen_random_uuid()` |
| `reporter_id` | uuid | `REFERENCES user_profiles(id) ON DELETE SET NULL` |
| `reported_user_id` | uuid | `REFERENCES user_profiles(id) ON DELETE SET NULL` |
| `message_id` | uuid, not null | No foreign key: the message will be gone |
| `reason` | text, not null | One of `harassment`, `spam`, `sexual`, `hate`, `threat`, `other` |
| `note` | text | Optional, up to 500 characters |
| `snapshot` | jsonb, not null | The copy, see 9 |
| `status` | text, not null | `open` (default), `actioned`, `dismissed` |
| `resolved_at`, `resolution_note` | timestamptz, text | Filled in by the owner |
| `created_at` | timestamptz, not null | default `now()` |

- `UNIQUE (reporter_id, message_id)`: one report per person per message (P4). Index on `(reported_user_id)`.
- Written only by `report_chat_message`. No client can read, change or delete a report.

## 4. Who can do what

### 4.1 Table privileges and RLS

| Table | `anon` | `authenticated` | Policy |
|---|---|---|---|
| `chat_messages` | nothing | SELECT | One SELECT policy, below. No INSERT, UPDATE or DELETE grant |
| `chat_blocks` | nothing | SELECT | SELECT where `blocker_id = auth.uid()`. A blocked person cannot read that they are blocked |
| `chat_reports` | nothing | nothing | No policy. Owner reads it in the dashboard |

The `chat_messages` SELECT policy, for `authenticated`:

```sql
USING (
  created_at > now() - interval '24 hours'
  AND friendship_id IS NOT NULL
  AND (SELECT auth.uid()) IN (sender_id, recipient_id)
  AND NOT EXISTS (
    SELECT 1 FROM public.chat_blocks b
    WHERE b.blocker_id = (SELECT auth.uid())
      AND b.blocked_id IN (chat_messages.sender_id, chat_messages.recipient_id)
  )
)
```

So a row is visible only to its two parties, only while they are still buddies, only while it is under 24 hours old, and not to a party who has blocked the other. Every read goes through this one policy: the load function runs with the caller's rights, and Realtime applies the same policy before it delivers a row.

Nobody deletes a message from the client. Rows leave by the expiry job and by account deletion, and by nothing else.

### 4.2 Functions

All are in `public`, have `SET search_path = public`, and have EXECUTE revoked from `PUBLIC` and `anon` and granted to `authenticated` only.

| Function | Rights | Does |
|---|---|---|
| `send_chat_message(p_id uuid, p_recipient_id uuid, p_body text) returns jsonb` | SECURITY DEFINER | The only way to write a message. See 5 |
| `get_chat_messages(p_buddy_id uuid) returns jsonb` | SECURITY INVOKER | The newest 300 messages between the caller and the buddy that the SELECT policy lets the caller see, oldest first, plus `server_now`, `is_buddy` and `blocked_by_me`. It reads only what the caller's own rights allow |
| `set_chat_block(p_user_id uuid, p_blocked boolean) returns boolean` | SECURITY DEFINER | Adds or removes the caller's block on a user. See 8 |
| `report_chat_message(p_message_id uuid, p_reason text, p_note text) returns jsonb` | SECURITY DEFINER | Stores a report with its snapshot. See 9 |
| `_chat_message_guard()` | trigger | The participant check in 3.1. Not callable by clients |

The three client-facing write functions take the caller from `auth.uid()` and never from a parameter. `send_chat_message` and `report_chat_message` answer with `{ "ok": false, "reason": "..." }` for expected refusals, so the client gets a typed result and not an exception. Inputs are checked inside the functions before any insert, so a table constraint is never the thing that refuses a client's text.

## 5. Sending

`send_chat_message` runs these steps in one transaction:

1. No caller: raise `not_authenticated`.
2. Trim spaces, tabs and line breaks from both ends of the body. Nothing left (or no body): `empty`. Over 500 characters: `too_long`.
3. Take the sender lock: `pg_advisory_xact_lock(hashtext('chat_send'), hashtext(sender id))`. One sender's sends run one at a time on every device, which makes the retry check and the rate limit exact.
4. **Retry check.** If a row with `p_id` exists: when it is the caller's own message to the same recipient, still under 24 hours old and still attached to a friendship, return it with `duplicate: true` and stop (F2). The caller's own message whose buddy has been removed: `not_buddies`. Anything else, including an expired row and a row that belongs to someone else: `id_taken`, with nothing about the row. A stored message is only ever returned to its own author.
5. Take the pair lock: `pg_advisory_xact_lock(hashtext('chat_pair'), hashtext(smaller id || larger id))`. Blocking takes the same lock, so a send and a block for the same pair never interleave.
6. Lock the two `user_profiles` rows `FOR KEY SHARE`, in id order. A profile that is gone: `not_buddies`. An account deletion locks the profile first and the friendship after it, so the send takes them in the same order and the two cannot deadlock. This lock does not get in the way of coin, XP or level updates on the same rows.
6b. Find the accepted friendship between caller and recipient and lock its row `FOR KEY SHARE`. None: `not_buddies` (M2, R6). The lock makes a concurrent buddy removal wait until this send has committed, and then the removal hides the new message with the rest.
7. Either party is a bot: `not_buddies` (M4). The same answer as for a stranger, so the private `is_bot` flag cannot be read through this function.
8. A block exists in either direction: `blocked` (B1, B4).
9. **Rate limit** (D7). Count the caller's messages in the last minute and the last hour. At 20 or 200: `rate_limited` with `retry_after_seconds`, the time until the oldest counted message leaves its window. Retries of an already stored message do not count.
10. Insert the row with `created_at = clock_timestamp()` and `ON CONFLICT (id) DO NOTHING`. If another sender stored the same id in this instant, the answer is `id_taken`. Because the pair lock is held, messages in one conversation get strictly increasing times in the order they were accepted, so both phones sort them the same way (S5).
11. Ask for the push (6). A push failure never fails the send; it is written to the database log as a warning, without the message text.
12. Return `{ ok: true, duplicate: false, message: {...}, server_now }`.

Lock order inside chat: sender lock, then pair lock, then the two profile rows, then the friendship row. `set_chat_block` takes a per-blocker lock (`'chat_blocker'`, which nothing else takes) and then the pair lock, and `report_chat_message` takes only its own per-reporter lock (`'chat_report'`). No path takes them in another order, and none of them is a credit-path lock. A send that has to wait for a lock is bounded by the role's statement timeout; it then fails as an error and the retry is safe because of the id.

What the client sees for each refusal is in the UI brief. For the rate limit it is a message that says to slow down and when to try again; the typed text stays in the box (F3).

## 6. Push

The existing path is reused: the send function calls the database helper `_send_push`, which fills a `push_templates` row and posts to the `send-notification` Edge Function. No new Edge Function.

- **Template** `chat_message`: title `{name}`, body `sent you a message. It disappears after 24 hours.` No message text and no emoji (D8).
- **Name**: the nickname the receiver set for the sender (`friend_nicknames`), cut to 40 characters; otherwise the sender's first name as `_send_push` already works it out.
- **How often** (D9): the send function calls `_send_push` once per stored message with the reference `<sender id>:<floor(epoch / 300)>`. That reference is the dedupe key in `send-notification`, so a receiver gets at most one chat push per buddy per 5-minute window. The windows are fixed (clock time divided into 5-minute slots), so two pushes can be less than 5 minutes apart when two messages fall on either side of a slot boundary. The reference starts with the sender's id, which is what a tap on the notification will use to open the right conversation. The Android tag is `chat_<sender id>`, so a newer chat notification from the same buddy replaces the older one.
- **Settings**: type `chat_message` is mapped to the Social toggle in `send-notification` (`settings.ts`, one line). Quiet hours apply; chat is not urgent. Client callers cannot send this type: it is not in the function's client allow-list, so only the database can raise a chat push.
- **Inbox**: like every push, a row with the same generic text is kept in the notification inbox for 7 days. It holds the buddy's name and the fact that a message was sent, never the text.
- **Blocked or removed**: the send is refused before the push step, so there is no push. A push for a message that was accepted a moment before a block or a removal is still delivered; it names the sender and nothing else.

The `send-notification` change needs a deploy before chat pushes follow the Social toggle. Until then a chat push is sent regardless of the toggle, because that function never disables a type it does not know.

## 7. Delivery to the open app (D10)

- `chat_messages` is added to the `supabase_realtime` publication.
- The app joins one private channel, `chat:<own user id>`, and listens for INSERT changes on `chat_messages` where `recipient_id` is the user. Realtime checks the SELECT policy for that user before sending the row, so only the two parties ever receive it.
- Private channels need a SELECT policy on `realtime.messages`. The new policy lets a signed-in user join only the topic that ends in their own id, read-only, the same shape as the two existing topic policies. The topic policy only decides who may open the channel. Which rows a user receives is decided by the `chat_messages` SELECT policy alone.
- The app listens for INSERT only. Expiry is handled on the phone by a timer (E2), and deletes caused by buddy removal are picked up by the reload.
- **Safety net**: while a conversation is open the service reloads it every 60 seconds and when the screen resumes. This covers a dropped Realtime connection, a buddy removal or block that happened while the screen was open (R2), and messages sent from the user's other device.
- **When the buddy is gone.** A reload that says `is_buddy: false` closes the conversation for sending. The messages already on the screen stay there, read-only, until they expire or the user leaves, so a message can still be reported (R7).
- Buddy removal is an update that makes the rows invisible, so Realtime sends them to nobody. Expiry and account deletion are deletes; Realtime announces a deleted row with its id only. Ids are random and carry no text and no names.
- The service keeps messages in memory only. Nothing is written to the phone's storage.

Polling alone was the other option. It was not chosen because every message would arrive late and each open chat would cost a request every few seconds; the 60-second reload keeps its one advantage, which is that it cannot miss anything for long.

## 8. Block (D13, D14)

`set_chat_block(user, true)` adds a row `(caller, user)`; `set_chat_block(user, false)` removes it. Both take the pair lock. The target must be an existing account and not the caller (`invalid_user` otherwise), and a block list holds at most 200 people (`too_many_blocks`). The target does not have to be a buddy: a block on someone who is not one takes effect if the two become buddies.

| | Effect |
|---|---|
| Sending | Neither person can send to the other while a block exists in either direction. The send returns `blocked` and stores nothing |
| Receiving | Nothing new arrives, because nothing can be sent |
| Existing messages | Hidden from the blocker at once by the SELECT policy. The blocked person keeps seeing what was already there until it expires. Nothing is deleted by the block |
| Push | None: refused sends raise no push |
| Undo | Unblocking removes the row. Messages that have not yet expired become visible to the blocker again, and both can send |
| Buddy status | Unchanged. Streaks and workouts carry on. The user can remove the buddy separately |
| Later | The block row survives buddy removal. If the two become buddies again, the block still holds until it is removed |

A user can read their own block list (B5). Nobody can read who has blocked them; a blocked sender learns it only from the refused send.

**Report, then block.** Because a block hides the conversation, the UI offers "Report and block" as one action that reports first (P3). A message that is already hidden by a block can still be reported by its id; the server does not need the reporter to be able to see it.

## 9. Report (D15, D16)

Google Play requires in-app report and block for user-to-user messages. Both are in the conversation; the UI brief places them.

`report_chat_message(message, reason, note)`:

1. The reason must be one of the six in 3.3 (`invalid_reason`); the note is at most 500 characters (`note_too_long`).
2. Take the reporter lock, so one person's reports run one at a time and the counts below are exact.
3. A second report of the same message by the same person returns `{ ok: true, duplicate: true }` and changes nothing (P4), also after the message is gone.
4. The caller must be the **recipient** of the message. Any other case, including a message that does not exist, returns `message_not_found` with no further detail.
5. At most 20 reports per reporter in 24 hours, and at most 5 about the same person (`rate_limited`).
6. The function builds the snapshot itself from the stored rows, inserts the report and returns `{ ok: true, duplicate: false }`. The snapshot is never returned to the client.

**Snapshot.** Built by the server in the same statement that stores the report, so it cannot be forged and cannot be empty (`NOT NULL`):

```json
{
  "taken_at": "...",
  "reported": { "id", "sender_id", "recipient_id", "body", "created_at" },
  "context": [ the 5 messages before and the 2 after the reported one, between the same two people, oldest first ],
  "reporter": { "id", "username", "display_name" },
  "reported_user": { "id", "username", "display_name" }
}
```

**The report outlives the message.** `message_id` has no foreign key, and the report table has no cascade from `chat_messages` or `friendships`. Expiry, buddy removal and blocking do not touch a report.

**A message can be reported for as long as the server stores it.** The function reads the stored row directly, so these all work: a report that is on its way when the message reaches 24 hours (until the expiry job removes the row); a report after the sender removed the buddy (D11: the rows are hidden, not deleted); a report by someone who has already blocked the sender. The one case where a message cannot be reported is when the sender's account has been deleted, because that deletes the rows.

**Retention.** A daily job deletes reports older than 30 days. If the reporter or the reported person deletes their account inside that time, the report's `reporter_id` or `reported_user_id` column is cleared. The snapshot is not edited: it keeps the two account ids, usernames and display names as they were when the report was made, until the 30 days are up (D12).

**What this means for Play and the privacy text.**
- Data Safety, Messages, "Other in-app messages": collected, not shared, purpose App functionality. Add purpose "Fraud prevention, security and compliance" for reported messages. Not optional for people who use chat. This is storage on our server, so it does not count as ephemeral processing.
- Data Safety, "User-generated content": the report note.
- Privacy policy, to add: chat messages are stored on our server and deleted 24 hours after sending; deleting the account deletes them sooner; removing a buddy hides the conversation at once and the messages are deleted when their 24 hours are up; if a message is reported, a copy of it and of up to 7 nearby messages in that conversation, with both people's usernames, is kept for up to 30 days so the report can be reviewed, including when an account is deleted in that time; the push for a new message does not contain its text; the notification history in the app keeps the buddy's name and the fact that a message was sent for 7 days, never the text; the list of people you blocked is kept until you unblock them or delete your account; database backups age out on the hosting provider's schedule.
- The account deletion page promises deletion within 30 days. The 30-day report retention keeps that promise without an exception.
- `dev/play_data_safety.md` and the public policy are not edited in this run; they change when chat ships.

## 10. Moderation (D17)

There is no automatic moderation. The owner reads reports in the Supabase dashboard (SQL editor or table editor, which bypass RLS).

Find open reports, oldest first:

```sql
SELECT id, created_at, reason, note, reporter_id, reported_user_id,
       snapshot->'reported'->>'body' AS reported_text
FROM public.chat_reports WHERE status = 'open' ORDER BY created_at;
```

Read one in full: `SELECT jsonb_pretty(snapshot) FROM public.chat_reports WHERE id = '<id>';`

Reports about one person: `SELECT ... WHERE reported_user_id = '<id>' OR snapshot->'reported_user'->>'id' = '<id>' ORDER BY created_at DESC;` (the second half finds reports whose account has since been deleted).

Act:

- **Dismiss**: `UPDATE public.chat_reports SET status = 'dismissed', resolved_at = now(), resolution_note = '...' WHERE id = '<id>';`
- **Warn**: email the account holder, then mark the report `actioned` with a note.
- **Remove the account**: follow `dev/account_deletion_runbook.md` (steps 3 onward) for `reported_user_id`, then mark the report `actioned`.

Reports must be handled inside 30 days; after that they are gone. Checking the open list is a manual routine. An email or push to the owner on each new report can be added later.

## 11. Buddy removal and account deletion (D11, D12)

| Event | Messages | Blocks | Reports |
|---|---|---|---|
| A removes B (`remove_friend`, or a direct delete of the friendship row) | In the same transaction every message of the pair loses its friendship and becomes invisible to both people. The rows stay stored until they are 24 hours old, reportable by their receiver, then the expiry job deletes them | Stay | Stay |
| A and B become buddies again | New friendship row, empty conversation (R3). Earlier messages stay hidden | An earlier block still applies | n/a |
| A deletes their account | The `user_profiles` delete removes every message A sent or received, at once | Rows where A is blocker or blocked are deleted | `reporter_id` or `reported_user_id` is cleared; the snapshot stays until day 30 |

`remove_friend` and the `delete-account` Edge Function are unchanged. The clean-up is done by foreign keys.

## 12. Clocks (E4)

- The server sets `created_at`. Expiry is the same instant for both people.
- Every response carries `server_now`. The service keeps the difference between the server's clock and the phone's (the existing `ServerClock`) and uses server time for "is this expired" and "how long is left". A wrong phone clock changes nothing.
- Messages are ordered by `created_at`, then `id`.

## 13. Failure and abuse cases

| Case | What happens |
|---|---|
| The expiry job is down or late | Expired rows stay on disk but are invisible: every read is filtered by the SELECT policy. The next run deletes them. `cron.job_run_details` shows the failures for 7 days |
| The report purge job is down | Reports are kept longer than 30 days until it runs again. Nothing is shown to clients either way |
| A user floods | The 21st message in a minute, or the 201st in an hour, is refused with a retry time. The receiver's phone buzzes at most once per 5 minutes per buddy. The receiver can block |
| A user calls the API directly | Direct INSERT, UPDATE and DELETE are refused by missing grants. The functions apply the same checks as for the app |
| A is blocked while sending | The pair lock orders the two. If the send finishes first, the message was sent before the block and is stored, and the blocker's side hides it. If the block finishes first, the send returns `blocked` |
| The buddy row is deleted while sending | The friendship row lock orders the two. If the send is first, the removal waits and then hides the new message with the rest. If the removal is first, the send returns `not_buddies` |
| Someone sends an abusive message and removes the buddy at once | The message is hidden from both, but stays stored until it is 24 hours old, and its receiver can report it in that time |
| Two people send the same new id at the same instant | One is stored; the other gets `id_taken` |
| A buddy removal and the expiry job touch the same rows | The job skips rows that are locked and takes them on its next run |
| The same message is sent twice (retry, double tap) | Same id: stored once, the second call returns the stored message |
| The connection drops after the server stored the message | The app shows "not sent"; retry uses the same id and gets the stored message back |
| A message expires while the screen is open | The phone removes it at its expiry time by server clock; the server would refuse to return it anyway |
| The push service fails | The message is stored and delivered in the app; only the notification is missing |
| Realtime is disconnected | The 60-second reload delivers the messages |
| The receiver's account is deleted while a message is on its way | The profile lock orders the two. If the send is first, the deletion waits and then removes the new message with the rest. If the deletion is first, the send returns `not_buddies` |
| The sender's account is deleted while their message is being reported | The report answers `message_not_found` |
| A report is made at the moment the message expires | It succeeds while the row is still stored; after that the answer is `message_not_found` and the UI says the message is no longer available |

## 14. Scheduled jobs

| Job | Schedule | Command |
|---|---|---|
| `purge-chat-messages` | every 10 minutes | `DELETE FROM public.chat_messages WHERE id IN (SELECT id FROM public.chat_messages WHERE created_at < now() - interval '24 hours' FOR UPDATE SKIP LOCKED)` |
| `purge-chat-reports` | daily 03:31 UTC | `DELETE FROM public.chat_reports WHERE created_at < now() - interval '30 days'` |

A message is therefore a row in the table for at most 24 hours and 10 minutes when the job is healthy. This is deletion from the live database; the hosting provider's backups keep their own copies until they age out, which the privacy text says.

## 15. Service layer

`lib/services/chat_service.dart`, no UI. Constructor takes an optional `SupabaseClient`, like the other services.

| Method | Server call | Result |
|---|---|---|
| `send(buddyId, body, {id})` | `send_chat_message` | `ChatSendResult` with a status: sent, notBuddies, blocked, rateLimited (with seconds), tooLong, empty, offline, error |
| `loadConversation(buddyId)` | `get_chat_messages` | The conversation, messages oldest first; throws on failure so a screen can show its error state |
| `watchConversation(buddyId)` | load, Realtime, 60-second reload, expiry timer | A stream of the conversation: the current messages, whether the two are still buddies, whether the caller blocked the buddy |
| `block(userId)` / `unblock(userId)` | `set_chat_block` | true when done, false when it failed |
| `loadBlockedIds()` | `chat_blocks` | The caller's block list |
| `report(messageId, reason, {note})` | `report_chat_message` | reported, alreadyReported, messageGone, rateLimited, offline, error |

The message id is generated on the phone before the first attempt and reused for every retry of that message.

## 16. Test plan

Database behaviour, tested by the prepared probe (migration applied inside a transaction that is rolled back):

1. A buddy can send, and both parties can read the message.
2. A stranger (not a party) reads nothing from the conversation, by table read and by `get_chat_messages`.
3. A non-buddy cannot send (`not_buddies`); a pending friendship does not count.
4. `anon` can read nothing and call nothing.
5. Direct INSERT, UPDATE and DELETE on `chat_messages` by `authenticated` are refused. A load returns the newest 300 messages, oldest first.
6. The participant trigger rejects a row whose parties do not match its friendship, for a privileged writer too, and rejects an update of the sender, the recipient, or a move to another friendship.
7. A row older than 24 hours is invisible to both parties while it is still stored.
8. The purge command deletes rows older than 24 hours and leaves newer ones.
9. Empty, whitespace-only and 501-character bodies are refused; 500 characters is accepted.
10. The same id sent twice stores one row and returns `duplicate`; another user reusing the id gets `id_taken` and learns nothing; a retry of an expired id returns no text; a retry after the buddy was removed returns `not_buddies`.
11. The 21st message in a minute is refused with `retry_after_seconds`; after the window moves it is accepted. Same for the hourly limit.
12. A retry of a stored message does not count toward the limit.
13. Block: neither direction can send; the blocker stops seeing the conversation; the blocked person still sees it; no push is raised. Unblock restores sending and visibility. The blocked person cannot lift the block. The blocker can still report a message received before the block.
14. A user cannot read another user's block rows, and cannot write `chat_blocks` directly. Blocking yourself or an id that is not an account is refused; the 201st block is refused.
15. Bots: a send to or from an `is_bot` account is refused with the same answer as a stranger.
16. Push: one call to `_send_push` per stored message (the 5-minute dedupe happens in `send-notification`), also with the real helper in place (one queued request, generic text, no message text), with type `chat_message`, the receiver as target, the sender and window as reference, the nickname as name when one exists, and no message text in any argument. Refused sends raise none. A failing push does not fail the send.
17. Buddy removal (through `remove_friend` and through a direct delete of the friendship) hides the pair's messages from both at once and touches no other conversation; the rows stay stored and reportable; the purge removes them at 24 hours; buddies again start empty.
18. Deleting a profile deletes that user's messages and block rows; reports stay with the id column cleared and the snapshot intact.
19. Report: only the recipient can report; the snapshot holds the reported message, the 5 before and the 2 after, of the same two people only; it is unchanged after the message is purged and the buddy removed; a second report is a duplicate, also after the purge; a message past 24 hours that is still stored can be reported; the 6th report about one person and the 21st in all in 24 hours are refused; clients cannot read, change or delete `chat_reports`.
20. The report purge command deletes reports older than 30 days only.
21. Catalog: RLS on for the three tables; exact table privileges; function ACLs; `search_path` set; SECURITY DEFINER only where listed; both cron jobs present; the table is in the publication; the Realtime policy exists and matches only the caller's own topic.
22. Rollback: after the rollback file runs, none of the objects, jobs, policies, template rows or publication entries remain.

Service behaviour, tested in Dart with a fake client:

23. `send`: the RPC name and parameters; a generated id when none is given; each server reason maps to its status; `retry_after_seconds` is passed through; network failure maps to offline; any other exception maps to error.
24. `loadConversation`: the RPC call, parsing, ordering, and that expired rows in a response are dropped using server time.
25. `watchConversation`: first emission after load; a Realtime row from the buddy is added; a row from someone else is ignored; a duplicate id is not added twice; an expiring message leaves the list at its time; the reload replaces the list; cancelling stops the timers and the subscription; a sent message appears in an open stream.
26. `block`, `unblock`, `loadBlockedIds`: calls and results.
27. `report`: each server answer maps to its status.
28. Clock: a phone clock that is hours off does not change what is shown as expired.

Not covered by the single-session probe, and to do before launch:

- **Two-session races** (send against block, send against buddy removal, two devices at the rate limit, the same new id from two senders, a double-tapped report). The design relies on the locks in section 5 for these. They need two connections, in the way the race kit in `dev/hygiene/07_race/` does it.
- Push arrival on a device, Realtime delivery end to end (including that a blocked, removed or third user receives nothing), and the Social toggle after the `send-notification` deploy. These need the migration applied and a build installed.

## 17. Review record

2026-11-14, design review by an independent reviewer that was given only this file, the user stories and the existing schema. Changes made as a result:

| Change | Where |
|---|---|
| Buddy removal no longer deletes the rows: it hides them and they stay reportable until they are 24 hours old | D11, 3.1, 4.1, 9, 11 |
| The retry path returns a stored message only to its author, only while it is unexpired and still attached to a friendship | 5 step 4 |
| The insert tolerates the same new id from two senders | 5 step 10 |
| Bots get the same answer as strangers | 5 step 7 |
| The participant trigger also covers updates | 3.1 |
| Report context cut from 20 messages to 5 before and 2 after; a per-person report limit added; the reporter lock and the duplicate-first order written down | D15, D15b, 9 |
| The text now says that the snapshot keeps ids and names after account deletion, and the moderation query finds such reports | D12, 9, 10 |
| Block: target must exist, list capped at 200, "report then block" order stated | 8 |
| The expiry job skips locked rows | 14 |
| Push reference format, the in-flight push, and what the Realtime topic policy does and does not decide are stated | 6, 7 |
| How someone becomes a buddy is stated | 1 |
| Race tests are listed as open work | 16 |

2026-11-14, review of the migration, rollback and probes by a second independent reviewer. It found no way to read or write another person's rows and no missing grant. Changes made as a result:

| Change | Where |
|---|---|
| The send locks the two profile rows before the friendship row, the same order an account deletion uses | 5 step 6 |
| A failed push is written to the database log; the probe now also runs the real push helper and checks the queued request | 5 step 11, test plan 16 |
| A report made in the instant the sender's account is deleted answers `message_not_found` | 13 |
| One blocker's calls run one at a time, so the 200 cap is exact | 5, 8 |
| The rollback file tolerates objects that are not there, and the rehearsal runs it twice | prepared files |
| Probe: tighter retry-time check, the 300-message load limit, NULL arguments, column-level privileges, a send to a deleted account | test plan |
| The friendship index no longer carries the time column; the fixed 5-minute push windows are stated | 3.1, 6 |
