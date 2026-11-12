# Rules before and after, 2026-11-12

Branch `chore/loosen-rules`, built on `main` at 261a44e. Task 4: restructure the rules in `CLAUDE.md` into NEVER, ASK FIRST and FREE, and loosen what is left.

"Before" is `CLAUDE.md` on `main`. "After" is the file on this branch, including the owner's answers of 2026-11-12 (section 9), which changed several lines written in the first commit (d825ecd).

## 1. Summary

- `CLAUDE.md` went from 75 lines to 121. It gained two sections, **Working style** and **Permission tiers**, placed before **Rules**.
- Five existing lines were reworded, two were moved into the NEVER tier, one duplicated sentence was deleted from Migrations, and the "Known gap" line was moved to the tracker.
- Nothing else was moved out to `dev/`. The file is well under the 250-line target, and every long paragraph that is left is a Supabase rule the task said to keep in place.
- `.claude/settings.local.json` gained two allow entries and one deny entry, on the owner's answer. The file is gitignored, so that change is on disk and not in a commit. Section 6 has the entries.
- Every owner answer to audit questions 1 to 11 was found applied (section 4), so none was re-applied.

## 2. Changed lines

### 2.1 Commands, deploy line

- **Before:** `supabase functions deploy <name>   # coach-max-cron, delete-account, …`
- **After:** `supabase functions deploy <name>   # ASK FIRST. coach-max-cron, delete-account, …`
- **Reason:** the command sits in the Commands block with no hint that it is an ASK FIRST action.

### 2.2 Migrations, the baseline file

- **Before:** "Their DDL is in `dev/pre_vc_schema_baseline_20260720.sql`, which is REFERENCE ONLY and never applied."
- **After:** "Their DDL is in `dev/pre_vc_schema_baseline_20260720.sql`, which is reference only: do not apply it or place it in `supabase/migrations/`, because it is a record for a from-scratch rebuild and not an executable step (its header has the detail)."
- **Reason:** an absolute "never" with no reason. The reason is the one in the file's own header, lines 14 to 23.

### 2.3 Migrations, new first sentence of the apply rule

- **Before:** "Apply migrations with the CLI (…"
- **After:** "Applying a migration is ASK FIRST (see [Permission tiers](#permission-tiers)). Apply migrations with the CLI (…"
- **Reason:** a reader who lands on Migrations alone now sees the tier. The steps stay here and the tier links to them.

### 2.4 Migrations, duplicated sentence

- **Before:** "…never the MCP `apply_migration` tool: it stamps its own version, which causes drift. `supabase db push` is also fine when `--dry-run` lists only the new file. Never the MCP `apply_migration` tool. Never run `migration repair --status reverted`…"
- **After:** "…never the MCP `apply_migration` tool: it stamps its own version, which causes drift. `supabase db push` is also fine when `--dry-run` lists only the new file. Never run `migration repair --status reverted`…"
- **Reason:** the second "Never the MCP `apply_migration` tool." repeated the first, which already carries the reason.

### 2.5 Rules, Coach Max gradient

- **Before:** "**Coach Max gradient** `0xFF1D4ED8` → `0xFF7C3AED` is scoped to his badge/avatar. Never change or tokenise it; it doesn't follow the accent skin and isn't app-wide. This is the first permitted raw hex. Everything else uses `AppColors`/`colorScheme`. Warm/orange is for the primary CTA only."
- **After:** three lines.
  - "**Coach Max gradient** `0xFF1D4ED8` → `0xFF7C3AED` is scoped to his badge/avatar. Do not change its values, tokenise it or use it elsewhere. Reason: it doesn't follow the accent skin and isn't app-wide."
  - "**Raw hex** is permitted in two places: the Coach Max gradient and the avatar illustration colours (`lib/widgets/avatars/`). Everything else uses `AppColors`/`colorScheme`. Reason: avatar illustrations are character art, like Coach Max, and give the app personality."
  - "Warm/orange is for the primary CTA only. Reason: owner preference, no recorded cause."
- **Reason:** one line held three rules. The gradient rule keeps its own recorded words as its reason. The raw-hex reason is the owner's, given on 2026-11-12. The orange rule has no recorded cause, and the owner confirmed the fallback text for it.

### 2.6 Rules, avatar illustration colours

- **Before:** "**Avatar illustration colours** (`lib/widgets/avatars/`) are the second permitted raw hex, alongside the Coach Max gradient. Everything else uses AppColors/colorScheme."
- **After:** merged into the **Raw hex** line in 2.5.
- **Reason:** "Everything else uses AppColors/colorScheme" appeared twice, once on each line.

### 2.7 Rules, UI changes

- **Before:** "UI changes: show or describe the plan and wait for approval before code. For UI without an approved mockup, write the spec, stop at that item, and carry on with the rest. Reason: no throwaway work on a rejected design."
- **After:** removed from Rules. It is now two lines elsewhere.
  - NEVER: "**UI code without an approved mockup**: any UI change. With an approved mockup, post the plan and proceed. Without one, write the UI spec, stop at that item, and carry on with the rest. Reason: no throwaway work on a rejected design."
  - Working style: "Plans: post the plan, then proceed. Wait for an answer only when the plan contains an owner decision or an ASK FIRST action."
- **Reason:** the task's "plan first, wait for approval" item. The wait is gone for plans in general. The mockup gate stays, with the same reason.

### 2.8 Rules, Branches

- **Before:** "Branches: one branch per prompt, named in the prompt, created from `main` in the main folder. No git worktrees (owner's ways-of-working rule)."
- **After:** "Branches: one branch per prompt, named in the prompt, created from `main` in the main folder. Worktrees are in the NEVER tier."
- **Reason:** the worktree half is a NEVER line now, with the same reason. The branch rule itself is unchanged.

### 2.9 Rules, `docs/` and `dev/`

- **Before:** "…Working files (reports, audits, rollbacks, probes) go in `dev/`. Reason: Pages served the working files until commit f44a77e moved them out."
- **After:** "…go in `dev/`. A `docs/` path that a prompt gives for a working file means the same path under `dev/`. Reason: Pages served the working files until commit f44a77e moved them out."
- **Reason:** the PATH NOTE at the top of the prompt, so later prompts need not repeat it.

### 2.10 Supabase rules, "Known gap"

- **Before:** "**Known gap:** leaked-password protection is off (needs Pro plan). Enable it before public launch."
- **After:** removed from `CLAUDE.md`. The same text is appended to the "Leaked-password protection" row of the Play Store checklist in `dev/audits/audit-2026-09-29.md`, with the date and the advisor status. That tracker already listed the gap in three places (lines 112, 512 and 565).
- **Reason:** owner answer 5. `CLAUDE.md` is public; the tracker is kept out of git. The line is still in git history. "Known residual" (CRON-ORDER) stays where it is, on the same answer.

## 3. Added lines

### 3.1 Working style (new section, an intro line and 7 bullets)

| Line | Source | Loosens or keeps |
|---|---|---|
| Intro: the owner is the only developer and wants fewer stops | task text | gives the section its reason |
| One-line start, short updates, standalone recap | prompt, Working style | new to the file |
| Finish the whole task; no closing list of what remains | prompt, Working style | loosens: fewer stops |
| Plans: post, then proceed | task step 2 | loosens: replaces "wait for approval" |
| Obstacles: diagnose, retry with a fix, continue | task step 2 | loosens. No "stop at the first error", "never retry" or "always confirm" line existed in `CLAUDE.md`, `.claude/` or memory, so this line is new and replaces nothing |
| Where you must ask: prepare, put it in the recap, carry on | prompt, Working style | loosens |
| Subagents: read-only searches or review of your own diff, on Sonnet, no delegated edits | prompt, Working style | keeps. Reason: "they can account for a large share of a session's cost (Anthropic's Fable 5.2 guidance)", from the owner's notes |
| Model and effort: Fable 5.2, high by default, medium for mechanical work, xhigh when measurably needed | task step 2 | new. The second sentence, about the old "Opus" and "Sonnet-medium" labels, is the audit's C5 resolution |

### 3.2 Permission tiers, NEVER

Eleven lines, each with a scope and a reason, and one pointer line.

| Line | Source | Reason used | Where the reason comes from |
|---|---|---|---|
| `git push` | task step 1 | a push to `main` publishes the website and the repo is public, so the owner decides when; Claude Code has no push credentials | owner's notes, 2026-11-12 |
| Git worktrees | task step 1; was in Rules | owner's ways-of-working rule | the Rules line it moved from |
| `flutter run` | task step 1 | it breaks FCM and wipes device data on a debug install. The line also names the path to use: `flutter build apk --release`, and the owner installs it | owner's notes, 2026-11-12 |
| `flutter install` and uninstalling the app | task step 1 | the owner installs builds himself; a debug-signed build once refused a release install (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`); an uninstall wipes the login and data | owner's notes, 2026-11-12 |
| Screenshots | prompt NEVER list | screenshot loops are the biggest token and context cost; `uiautomator dump`, `dumpsys` and `logcat` answer the same questions | owner's notes, 2026-11-12 |
| Secret values in output | task step 1 | "this repo is public on GitHub; no incident on record" | the prompt's PATH NOTE |
| Credit or streak functions outside a rolled-back transaction | task step 1 | "on live they pay real coins and move real streaks" | a statement of what the functions do; the suite header says it runs on live |
| Migration or deploy without the owner's go-ahead | task step 1 | the linked project is live and history must match one-to-one | Migrations paragraph |
| `SELECT` on the private `user_profiles` columns | task step 1 | owner decision 2026-10-12 | memory `project_live10_profile_visibility.md`; migration `20261012210000` |
| Attribution in commits or PRs | task step 1 | global settings blank it; no trailer since 2026-09-28 | audit C6 |
| UI code without an approved mockup | task step 1; was in Rules | no throwaway work on a rejected design | the Rules line it moved from |
| "Also NEVER" pointer line | existing rules | n/a | links to Migrations, Lock order and Rules instead of copying them. The unquoted-heredoc rule is reached through this line |

The first commit had `flutter run`, `flutter install` and uninstall on one line with the text "owner preference, no recorded cause", and the same text on `git push` and Screenshots. The owner supplied the reasons above, and the line was split because `flutter run` has a different reason from the other two.

### 3.3 Permission tiers, ASK FIRST

Seven lines. Six are from the prompt's ASK FIRST list, plus the instruction to name the exact action.

- "Any `supabase db` command" became "any `supabase db` command that is not in FREE", because the owner's Q1 answer allows `supabase db push --dry-run` and the prompt's FREE list allows read-only queries.
- "Merging a branch into `main`. The owner merges after review." Added on owner answer 3.

### 3.4 Permission tiers, FREE

Seven lines, all from the prompt's FREE list. Two additions:

- `supabase db push --dry-run` and `supabase migration list`, from the owner's Q1 answer.
- "This includes a read-only `supabase db query` (the permission prompt still appears; approve it): the permission file cannot tell a `SELECT` from a write, so the prompt is not a reason to stop the task." The bracketed words are the owner's, from answer 6.

### 3.5 Permission tiers, intro

- "An action in no list and under no rule is FREE when it is local to the repo and reversible (name it in the recap); otherwise it is ASK FIRST." New. Without it an unlisted action has no tier. It does not cover a merge into `main`, which is now a listed ASK FIRST action.
- "`.claude/settings.local.json` … enforces part of these lists; where it and this file disagree, the stricter one holds." New. See section 6.

### 3.6 Rules, two new lines

- "No emojis in pushes, toasts or dialogs (text the app shows or sends). Reason: owner preference, no recorded cause." From the prompt's NEVER list. The first commit put it in the NEVER tier; owner answer 4 moved it to Rules.
- "`CLAUDE.md` is public on GitHub. Do not add security gaps or internal weaknesses to it; they go in the tracker under `dev/audits/`, which is kept out of git. Reason: owner instruction, 2026-11-12." From the prompt's PATH NOTE. `dev/audits/` is excluded by `.git/info/exclude` line 18.

## 4. Skipped because the audit round did them

Each was checked against `CLAUDE.md` at 261a44e, or on disk where it lives outside the repo.

| Item | Where it was found | Check |
|---|---|---|
| Q1 permission allow, ask and deny lists | `.claude/settings.local.json` | deny has `git push *`, `flutter install *`, `flutter run *`, both uninstall forms, three screencap forms; allow has `flutter pub get *`, `supabase db push --dry-run *`, `supabase migration list *`; the ask list is present |
| Q2 one-page scope | Rules, "One page at a time" | present, with reason |
| Q3 branch per prompt, no worktrees | Rules, "Branches" (worktree half now in NEVER) | present; `git worktree list` shows the main folder only |
| Q4 Ponytail, commit subjects, `docs/` and `dev/` | Rules, last three lines | present, each with reason |
| Q5 no standing hold on commits | memory `feedback_diff_review_format.md` | says so, dated 2026-11-12 |
| Q6 `db push` allowed after a clean dry run | Migrations | present |
| Q7 commit-your-own-work scope | Rules; commits 44db24a and 23856ab | present |
| Q8 theme rule | Rules, "Theme work" | present, with reason |
| Q9 four clean-ups | `~/.claude/CLAUDE.md` is 0 bytes; `.claude-backup/CLAUDE.md.bak`; no `.agents/`; `dev/audits/audit-2026-09-29.md` | all four hold |
| Q10 claude-mem disabled | `~/.claude/settings.json` line 8 | `false` |
| Q11 five gap rules (G1, G2, G3, G5, G8) | Rules (G1, G2, G3) and Supabase rules (G5 "Grant traps", G8 "Replacing a function") | all five present, each with reason |

Step 2 items that needed no change:

- "Stop at the first error", "never retry", "always confirm": no such line exists in `CLAUDE.md`, `.claude/` or the memory folder. The Working style "Obstacles" line states the new behaviour.
- The tap rule, the heredoc rule, the theme rule and the two `migration repair` and MCP-tool rules already had a scope and a reason. They are unchanged.

## 5. The three items the task's keep-list did not name

The prompt's own NEVER list has three items that step 1's keep-list leaves out. The owner decided each on 2026-11-12 (answer 4):

- **Screenshots.** Stay in the NEVER tier. The permission file also denies `screencap`.
- **Unquoted heredocs with backticks.** Stay NEVER. The rule and its reason are in Rules, where the audit round put them, and the NEVER tier's pointer line links to it.
- **Emojis in pushes, toasts or dialogs.** Moved from the NEVER tier to Rules.

## 6. The permission file

`.claude/settings.local.json` is gitignored, so these changes are on disk only.

Added on owner answer 1:

- allow: `Bash(deno test *)`, `Bash(dev/hygiene/suite/run.sh *)`
- deny: `Bash(git worktree add *)`

Added on the owner's follow-up answer, same day:

- deny: `Bash(git -C * push *)`, `Bash(git -c * push *)`, and then the bare forms `Bash(git -C * push)`, `Bash(git -c * push)`
- Accepted side effect: other commands of that shape are blocked too, for example `git -C <dir> stash push`.
- No rules were added for other forms (`--git-dir`, `env git push`), by the owner's decision: the NEVER line and the missing credentials cover those. The owner closed the list of push forms here; no further variants are to be added.

The file parses as JSON and now holds 60 allow, 26 ask and 25 deny entries.

### What the deny list does to `git push`

The deny entries that name push are `Bash(git push --force*)`, `Bash(git push -f*)`, `Bash(git push * --delete*)`, `Bash(git push * --force*)`, `Bash(git push * -f*)`, `Bash(git push *)`, `Bash(git -C * push *)`, `Bash(git -c * push *)`, `Bash(git -C * push)` and `Bash(git -c * push)`. No allow or ask entry names push.

Checked against the Claude Code permissions page (code.claude.com/docs/en/permissions) on 2026-11-12, without running a push:

- `Bash(git push *)` matches `git push` followed by any arguments, and also the bare `git push`. A trailing `*` with a space before it matches the bare command.
- Deny is evaluated before ask and allow, so no allow entry can carve an exception out of it.
- It also applies when the push is one part of a compound command (`&&`, `;`, `|`), is inside a subshell or command substitution, or sits behind `timeout`, `time`, `nice`, `nohup`, `stdbuf` or `command`.
- `Bash(git push *)` alone does not match a push written with an option before the subcommand, such as `git -C . push origin main` or `git -c push.default=current push origin main`. The two entries added in the follow-up now deny those.
- `git -C <dir> push` or `git -c <setting> push` with nothing after `push` needed its own entries. The page says a trailing `*` matches the bare command only when it is the rule's only wildcard, and the two `push *` rules have two. `Bash(git -C * push)` and `Bash(git -c * push)` now deny the bare forms.
- Not denied, by the owner's decision: `--git-dir` and `env git push`. They match no rule and fall to the default permission prompt.
- The page says a deny rule "isn't a security boundary around the program".

Second backstop, read without printing any values: `origin` is an HTTPS URL, no git credential helper is configured, there is no `~/.git-credentials` file, and `gh` is not installed. That agrees with the owner's note that Claude Code has no push credentials.

### Where the tiers and the file still differ

| FREE in `CLAUDE.md` | Permission file | Effect |
|---|---|---|
| read-only `supabase db query` | in `ask` | always prompts (owner's Q1 decision; answer 6 says to approve it) |
| read-only SQL through the Supabase MCP `execute_sql` | no entry | prompts |

## 7. The three rules I was least sure about loosening

1. **"Plan first, wait for approval" became "post the plan, then proceed".** The old line was written for UI. The new Working style line covers every plan, so a migration design or a refactor plan now proceeds without a wait unless it contains an owner decision or an ASK FIRST action. Applying the migration still asks.
2. **The default for unlisted actions.** "Local to the repo and reversible is FREE" is new policy that no file stated before. It covers, for example, deleting a local branch that is already merged. A merge into `main` is not an example: the owner made it ASK FIRST on 2026-11-12.
3. **Read-only `supabase db` queries as FREE.** The prompt's ASK FIRST list says "any `supabase db` command" and its FREE list says "read-only Supabase queries". `CLAUDE.md` now says read-only is FREE and everything else under `supabase db` is ASK FIRST. Nothing tells a `SELECT` from a write except the agent's own reading of the SQL, which is why the permission prompt stays.

## 8. Audit questions left open

None of questions 1 to 11 is open. Three things the audit recorded are still as it left them, and one was noticed in this pass:

- Branch `style/dark-only` is unmerged, 3 commits ahead of `main` (audit section 8, Q3, option 2).
- The Q1 limit: a `supabase db push` written with an unlisted flag first gets the default prompt, not a forced one.
- `dev/hygiene/06_report.md` line 34 names the tracker's old path, on purpose.
- Noticed now, not changed: the header of `dev/pre_vc_schema_baseline_20260720.sql` points at a `CLAUDE.md` section called "Migration history & schema baseline (Group F)". That heading no longer exists; the content is the Migrations paragraph.

## 9. Owner answers, 2026-11-12

| Answer | Decision | Where it landed |
|---|---|---|
| 1 | Add the two allow entries and the worktree deny entry; confirm the push deny | `.claude/settings.local.json`; section 6 |
| 2 | Replace the fallback reason with recorded reasons for `git push`, `flutter run`, `flutter install` and uninstall, screenshots, subagents and avatar raw hex. Keep the fallback for emojis and the orange primary CTA only | `CLAUDE.md` NEVER tier, Working style and Rules; sections 2.5, 3.1 and 3.2 |
| 3 | Merging a branch into `main` is ASK FIRST | `CLAUDE.md` ASK FIRST; sections 3.3, 3.5 and 7 |
| 4 | Emojis move to Rules; screenshots and unquoted heredocs stay NEVER | `CLAUDE.md`; sections 3.6 and 5 |
| 5 | "Known gap" moves to the tracker; "Known residual" stays | `CLAUDE.md` and `dev/audits/audit-2026-09-29.md` (not in git); section 2.10 |
| 6 | Add "(the permission prompt still appears; approve it)" to the read-only query line | `CLAUDE.md` FREE; section 3.4 |

After these answers, "owner preference, no recorded cause" appears on two lines of `CLAUDE.md`: the orange primary CTA and the emoji rule.
