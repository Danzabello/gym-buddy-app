# Buddy chat: mockup brief

A brief for the mockup tool. No code and no mockup exist yet, and no UI is built until a mockup is approved.
Background: [user_stories.md](user_stories.md) and [design.md](design.md). The service the screens will use is `lib/services/chat_service.dart`.

## What to design

One-to-one text chat between two buddies in the Gym Buddy app. Text only. Every message disappears 24 hours after it was sent, for both people.

**The 24-hour rule, in the words shown to the user:** "Messages disappear 24 hours after they are sent."

**Theme:** Emerald Ink is the only theme. Design in Emerald Ink only; no light theme, no Signal Blue or Lime Spark variants. Warm orange is for the primary action only (Send). No emoji in toasts, dialogs or notifications. The person is always called "buddy", never "friend" or "partner".

**Out of scope for the mockup:** photos, voice, reactions, read receipts, typing indicator, deleting a sent message, team chat, a chat with Coach Max.

## Where chat is entered

The entry points already exist in the Buddies tab and are switched off. The mockup shows them switched on:

1. **Tap a buddy card** on the Buddies tab: opens the conversation.
2. **Buddy options sheet** (long-press on a card): a "Message" row, subtitle "Open your chat".
3. **Search buddies** (search icon in the Buddies header): pick a buddy, opens the conversation.
4. **Notification tap**: opens the conversation with the buddy who wrote.

A chat entry point is active only for an accepted buddy. For someone whose buddy request is still pending, including a person the user already shares a team and a streak with, the card tap, the "Message" row and the search result must not appear as active chat entries: show them disabled or leave them out, and point to the pending request instead.

There is no separate conversation list in this version. The buddy card is the list. Decide in the mockup whether a card needs a hint that a chat has messages in it; the service has no unread count yet (story L5 is later), so the hint, if any, can only be "has messages from the last 24 hours".

## Screens and states

Each state lists what it shows and the data it needs from the service.

### 1. Conversation

The main screen. Header with the buddy's avatar (with their ring), their name (the nickname the user gave them, if any) and an overflow menu. Message list, oldest at the top, newest at the bottom, own messages on one side and the buddy's on the other. Input row at the bottom with a text field and Send.

| State | What it shows | Data from the service |
|---|---|---|
| **Loading** | Header is already there (the buddy is known). A quiet placeholder where messages go. No spinner over the input | `watchConversation(buddyId)` has not emitted yet |
| **Empty** | No messages. One centred line: "Messages disappear 24 hours after they are sent." and a second, lighter line: "Say something to {name}." The input is ready | First emission with no messages, `canSend` true |
| **With messages** | Bubbles with the text and the send time. The 24-hour line stays visible as a small caption at the top of the list | `messages` (id, sender, body, createdAt, expiresAt) |
| **Expiring soon** | A message with under one hour left carries a small, quiet mark and the text "Disappears in 12 min". Under one minute: "Disappears in under a minute". No countdown animation | `expiresAt` minus `serverNow()` |
| **A message expires while open** | The bubble leaves the list with a short fade. Nothing else moves abruptly. If it was the last one, the Empty state returns | The stream emits a list without it |
| **Sending** | Own bubble appears at once at the bottom, dimmed, with "Sending" | Local, until `send()` answers |
| **Sent** | The bubble becomes normal and takes its place by server time | `send()` returned `sent` with the message |
| **Failed send** | The bubble stays, marked "Not sent", with a "Try again" action on the bubble and a way to discard it. Retrying never produces a second copy | `send()` returned `offline` or `error`; retry calls `send()` again with the same `id` |
| **Offline** | A slim banner under the header: "No connection. Messages will send when you try again." Messages already loaded stay visible. Send still works as an attempt and falls into Failed send | The first load failed (stream error) or a send returned `offline` |
| **Error loading** | Centred: "Could not load this chat." with a "Try again" button | Stream error on first load |
| **Rate limit** | A line above the input: "You are sending messages too fast. Try again in 40 seconds." The typed text stays in the field. Send is disabled until the time is up | `send()` returned `rateLimited` with `retryAfter` |
| **Too long** | A counter appears near the limit ("480/500"). At 500 the field stops accepting text. No error dialog | `chatMaxLength` (500 characters) |
| **Blocked by me** | No messages. Centred: "You blocked {name}. You will not get messages from each other." with an "Unblock" button. No input row | `blockedByMe` true |
| **I am blocked** | Shown only after a send is refused. The message is not added. A line where the input was: "You can't message this buddy." The earlier messages stay until they disappear. No mention of who did what | `send()` returned `blocked` |
| **No longer buddies** | The input row is replaced by: "You are no longer buddies, so you can't send messages." Messages that were on the screen stay, read-only, and can still be reported. Leaving the screen clears them. The server gives the same answer for the next state, so the screen must tell the two apart | `isBuddy` false, or `send()` returned `notBuddies` |
| **Request still pending** | The same server answer as No longer buddies, but a different situation: a buddy request between the two is waiting, and they may already share a team and a streak (an invite code was redeemed while the request was pending). It needs its own wording, plain and with no emoji. No messages, no input row. If the user received the request: "Accept {name}'s buddy request to chat." with an "Accept" button. If the user sent it: "{name} has not accepted your buddy request yet. You can chat once they do." The entry points should keep the user from reaching this screen at all; it is the fallback for a notification tap or a stale screen | `isBuddy` false together with a pending request for this person from the Buddies tab data (`FriendService`); the chat service alone cannot tell pending from removed |

### 2. Message actions

Long-press on a **buddy's** message opens a small sheet:

- "Report message"
- "Copy text"

Long-press on **your own** message: "Copy text" only. There is no delete and no edit in this version.

### 3. Conversation menu (overflow in the header)

- "Block {name}" (or "Unblock {name}")
- "Report {name}": explains that a message is reported by pressing and holding it, since a report needs a message
- "View profile": the existing buddy profile sheet

### 4. Report flow

A bottom sheet in two steps.

Step 1, reason. Title: "Report this message". The reported message is quoted at the top so the user sees what they are reporting. One choice from:

| Label | Value sent |
|---|---|
| Harassment or bullying | `harassment` |
| Spam | `spam` |
| Sexual content | `sexual` |
| Hate speech | `hate` |
| Threat of violence | `threat` |
| Something else | `other` |

Step 2, details. An optional note, up to 500 characters: "Anything else we should know? (optional)". A checkbox, on by default: "Also block {name}". Body text: "We will review this message and the messages around it. {name} is not told who reported it." Primary button: "Send report". Secondary: "Cancel".

When "Also block" is ticked the report is sent first and the block second, because a block hides the conversation.

| Outcome | What it shows | Data |
|---|---|---|
| Sent | Sheet closes. Toast: "Report sent. Thank you." If blocked too: "Report sent and {name} blocked." | `report()` returned `reported` |
| Already reported | Toast: "You already reported this message." | `alreadyReported` |
| Message gone | Sheet stays. Text: "This message is no longer available, so it can't be reported." | `messageGone` |
| Too many reports | Text: "You have sent a lot of reports today. Try again tomorrow." | `rateLimited` |
| No connection | Text: "No connection. Try again." The choices stay as they were | `offline` |
| Other failure | Text: "Something went wrong. Try again." | `error` |

### 5. Block confirmation

A dialog from the conversation menu.

- Title: "Block {name}?"
- Body: "You will not be able to message each other, and you will not get chat notifications from {name}. You stay buddies and your streak carries on. You can unblock at any time."
- Buttons: "Block" (destructive style, not orange) and "Cancel".
- After: the conversation switches to the Blocked by me state. Toast: "{name} blocked."
- Failure: toast "Could not block {name}. Try again."

Unblock needs no confirmation. Toast: "{name} unblocked."

### 6. Blocked buddies list

Reached from Settings (place it next to the notification settings in the mockup). A plain list of blocked people with avatar, name and an "Unblock" button on each row.

| State | What it shows | Data |
|---|---|---|
| Loading | Placeholder rows | `loadBlockedIds()` pending |
| Empty | "You have not blocked anyone." | Empty set |
| List | Rows with "Unblock" | The ids, joined with the profile fields the app already loads |
| Error | "Could not load this list." with "Try again" | The call threw |

### 7. Notification

Shown by the system, drawn by the app's existing notification style on the Friends channel.

- Title: the buddy's name (the nickname the receiver gave them, if any).
- Body: "sent you a message. It disappears after 24 hours."
- Never the message text. One notification per buddy; a newer one replaces the older one. At most one every 5 minutes per buddy.
- Tap: opens the conversation with that buddy.
- The same line appears in the in-app Notifications page for 7 days.
- Chat notifications follow the existing "Social" toggle and quiet hours. The mockup for notification settings needs one changed description: "Friend requests and messages from buddies".

## Copy list

All strings in one place, for the copy pass. `{name}` is the buddy's name. `{time}` is a short duration such as "40 seconds" or "12 min".

| Where | Text |
|---|---|
| Rule, empty state and caption | Messages disappear 24 hours after they are sent. |
| Empty state, second line | Say something to {name}. |
| Input placeholder | Message {name} |
| Send button (accessible name) | Send |
| Sending | Sending |
| Failed | Not sent |
| Failed, action | Try again |
| Failed, discard | Delete |
| Expiring | Disappears in {time} |
| Expiring, last minute | Disappears in under a minute |
| Offline banner | No connection. Messages will send when you try again. |
| Load error | Could not load this chat. |
| Rate limit | You are sending messages too fast. Try again in {time}. |
| I am blocked | You can't message this buddy. |
| Blocked by me | You blocked {name}. You will not get messages from each other. |
| No longer buddies | You are no longer buddies, so you can't send messages. |
| Request pending, received | Accept {name}'s buddy request to chat. |
| Request pending, received, button | Accept |
| Request pending, sent | {name} has not accepted your buddy request yet. You can chat once they do. |
| Menu | Block {name} / Unblock {name} / Report {name} / View profile |
| Message sheet | Report message / Copy text |
| Report title | Report this message |
| Report note | Anything else we should know? (optional) |
| Report checkbox | Also block {name} |
| Report body | We will review this message and the messages around it. {name} is not told who reported it. |
| Report button | Send report |
| Report toasts | Report sent. Thank you. / Report sent and {name} blocked. / You already reported this message. |
| Report, gone | This message is no longer available, so it can't be reported. |
| Report, limit | You have sent a lot of reports today. Try again tomorrow. |
| Block dialog title | Block {name}? |
| Block dialog body | You will not be able to message each other, and you will not get chat notifications from {name}. You stay buddies and your streak carries on. You can unblock at any time. |
| Block toasts | {name} blocked. / {name} unblocked. / Could not block {name}. Try again. |
| Blocked list, empty | You have not blocked anyone. |
| Notification body | sent you a message. It disappears after 24 hours. |
| Generic failure | Something went wrong. Try again. |

## Data the screens get from the service

| Need | Call | Notes |
|---|---|---|
| The live conversation | `watchConversation(buddyId)` | Emits `messages`, `isBuddy`, `blockedByMe`, `canSend`. Already drops expired messages and adds new ones. Listen again when the app returns to the foreground |
| Send | `send(buddyId, body, id)` | Create the id with `ChatService.newMessageId()` when the bubble is created and reuse it on every retry. Statuses: sent, notBuddies, blocked, rateLimited (with `retryAfter`), tooLong, empty, offline, error |
| Time left on a message | `message.expiresAt` and `serverNow()` | Always the server's clock |
| Block, unblock | `block(userId)`, `unblock(userId)` | true or false |
| Block list | `loadBlockedIds()` | Ids only |
| Report | `report(messageId, reason, note)` | Statuses: reported, alreadyReported, messageGone, rateLimited, offline, error |
| Buddy name and avatar | Already on the Buddies tab | Nickname first, then display name |

Not available yet, so do not design around them: unread counts, "read" marks, typing, the last message preview on a buddy card.

## Accessibility

- Every bubble is one screen-reader item that reads: who sent it, the text, when, and "disappears in {time}" when that mark is shown. For example "You, 14:05: done, your turn" or "Sam, 14:06: on my way. Disappears in 12 minutes."
- Sending, Not sent and expiry are shown with text or an icon with a label, never by colour or dimming alone.
- A new incoming message is announced politely when the conversation is open. A message that expires is removed without an announcement.
- Touch targets are at least 48 by 48 dp, including Send, the "Try again" action on a failed bubble and the menu.
- Long-press actions (report, copy) are also reachable without a long press: through the screen reader's actions menu, and the message sheet has ordinary buttons.
- Text scales with the system font size up to 200 percent. Bubbles grow in height; nothing is cut off. The input grows to about four lines and then scrolls.
- Contrast: text on both bubble colours and the expiry mark meet 4.5 to 1 in Emerald Ink. Own and buddy bubbles differ by position as well as colour.
- The input stays above the keyboard, and the newest message stays visible when the keyboard opens.
- Dialogs and sheets move focus to their title when they open and return it to the message or menu that opened them.
- Motion is small: a short fade for arriving and expiring messages, none when the system's reduce-motion setting is on.
- The report reason list is a radio group with one choice; the "Also block" control is a labelled checkbox.

## Decisions the mockup should settle

1. Whether a buddy card shows that a chat has recent messages, and how, given there is no unread count.
2. Where the 24-hour line lives when there are messages: a caption at the top of the list (proposed), or in the header.
3. How the expiry mark looks at one hour, and whether it is shown on own messages too (proposed: yes, same mark).
4. Where the blocked buddies list sits in Settings.
5. Whether "Report {name}" in the menu stays as an explainer or is dropped in favour of long-press only.
