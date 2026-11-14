# Buddy chat: user stories

Chat is one-to-one between two buddies. Every message disappears 24 hours after it was sent, for both people.
Each story is told by a buddy. **Launch** means it must work on day one. **Later** means it can wait.

The design that answers these stories is in [design.md](design.md). Story numbers are used there and in the test plan.

## Sending and reading

| # | Story | When |
|---|---|---|
| S1 | I just finished a workout. I open my buddy's chat, type "done, your turn" and send it. It shows in the conversation straight away, and my buddy can read it. | Launch |
| S2 | My app is closed. My buddy sends me a message. My phone shows a notification with my buddy's name that says they sent me a message. It does not show what they wrote. I tap it and the app opens. | Launch |
| S3 | I open a chat with a buddy I have never messaged, or where everything has expired. I see an empty conversation and one line that tells me messages disappear after 24 hours. I can type right away. | Launch |
| S4 | I have the conversation open while my buddy writes. Their message appears without me refreshing. | Launch |
| S5 | We both send at the same moment. We both see the two messages in the same order. | Launch |
| S6 | I come back to a conversation later the same day. I see every message from the last 24 hours, oldest first, and nothing older. | Launch |

## The 24-hour rule

| # | Story | When |
|---|---|---|
| E1 | A message is 24 hours old. It is gone for me and for my buddy at the same time. Neither of us can get it back. | Launch |
| E2 | I am looking at the conversation when a message reaches 24 hours. It leaves the screen on its own. I do not need to reopen the chat. | Launch |
| E3 | A message is close to its 24 hours. I can see that it will disappear soon. | Launch |
| E4 | My phone's clock is wrong, or my buddy is in another time zone. Messages still disappear 24 hours after they were sent, at the same moment for both of us, because the server keeps the time. | Launch |
| E5 | Something goes wrong on the server and the clean-up is late. I still never see a message older than 24 hours. | Launch |

## When sending goes wrong

| # | Story | When |
|---|---|---|
| F1 | I have no signal. I send a message. It stays in the conversation marked as not sent, with a way to try again. | Launch |
| F2 | My signal dropped just as I pressed send. I do not know if it went. I press retry. My buddy gets the message once, never twice. | Launch |
| F3 | I send a lot of messages very quickly. The app tells me to slow down and when I can send again. Nothing I typed is lost. | Launch |
| F4 | I paste a very long text. The app tells me the limit before I send, and does not let me send more than the limit. | Launch |
| F5 | I try to send an empty message or only spaces. Nothing is sent. | Launch |

## Buddies coming and going

| # | Story | When |
|---|---|---|
| R1 | I remove a buddy. Our conversation disappears right away, for both of us, and neither of us can open it again. | Launch |
| R2 | My buddy removes me. The conversation disappears for me too. If I had it open, I am told I can no longer message this person, and I cannot send. | Launch |
| R3 | We become buddies again later. The conversation starts empty. | Launch |
| R4 | My buddy deletes their account. Our conversation and its messages are deleted. | Launch |
| R7 | A buddy sends me something abusive and removes me straight away. I can still report that message while I have it in front of me. | Launch |
| R5 | I delete my account. My messages, my conversations and my block list are deleted. | Launch |
| R6 | I was in the middle of sending when my buddy removed me. The message is not delivered, and I am told why. | Launch |

## Blocking

| # | Story | When |
|---|---|---|
| B1 | A buddy is sending me messages I do not want. I block them in the chat. From that moment they cannot message me and I get no notifications from them. | Launch |
| B2 | After I block someone, I no longer see our conversation. | Launch |
| B3 | I blocked someone by mistake, or we sorted it out. I unblock them and we can chat again. | Launch |
| B4 | I am blocked by a buddy. When I try to send, I am told I cannot message this buddy. My message is not delivered and they are not notified. | Launch |
| B5 | I can see a list of the people I have blocked and unblock any of them. | Launch |
| B6 | I want to block someone and also stop being their buddy. I can do both; blocking does not remove the buddy for me. | Launch |

## Reporting

| # | Story | When |
|---|---|---|
| P1 | A buddy sent me something abusive. I report that message from inside the chat, pick a reason, and can add a short note. I am told the report was received. | Launch |
| P2 | I reported a message and it has since disappeared. My report still holds a copy of it and of the messages around it, so the person reviewing it can see what happened. | Launch |
| P3 | I report a message and want to block the sender in the same step. | Launch |
| P4 | I tap report twice on the same message. It counts as one report. | Launch |
| P5 | Someone reports one of my messages. I am not told who reported it. A copy of the reported messages is kept for review for a limited time, and the privacy policy says so. | Launch |
| P6 | I am told the outcome of my report. | Later |
| P7 | An account that keeps breaking the rules is removed by the team. | Launch (done by hand) |

## Spam and misuse

| # | Story | When |
|---|---|---|
| M1 | A buddy floods me with messages. They are slowed down by the server, and my phone does not buzz for every message. | Launch |
| M2 | Someone who is not my buddy cannot message me at all. | Launch |
| M3 | Nobody except me and the buddy I am talking to can read our messages. | Launch |
| M4 | Coach Max is a coach, not a person to chat with. There is no chat with Coach Max. | Launch |

## Not in this version

| # | Story | When |
|---|---|---|
| L1 | I see whether my buddy has read my message. | Later |
| L2 | I delete a message I sent before the 24 hours are up. | Later |
| L3 | I send a photo, a voice note or a reaction. | Later |
| L4 | I chat with a whole team at once. | Later (out of scope) |
| L5 | I see a dot on a buddy's card when they have sent me something I have not opened. | Later |
| L6 | I mute chat notifications from one buddy without blocking them. | Later |
| L7 | I see that my buddy is typing. | Later |
