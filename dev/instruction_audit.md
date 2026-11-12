# Instruction file audit, 2026-11-12

Branch `chore/instruction-audit`. Read-only until section 5.

**This file is in `dev/`, not `docs/` as the prompt asked.** `docs/` is the public GitHub Pages site; commit f44a77e (2026-11-11) moved every working file out of it for that reason. A file committed under `docs/` is published once the branch reaches `main`.

## 1. Summary

- **One high-severity conflict between a file and your rules.** `.claude/settings.local.json` pre-approves `git push origin main`, `flutter install`, `adb exec-out screencap`, `supabase db *` and `flutter pub *`. Your header lists the first three under NEVER and the last two cover ASK FIRST actions. Nothing instructs the agent to run them, but the prompt that would catch a slip is switched off. (C8)
- **One rule that stops long tasks.** "One page at a time: touch only the file asked about" has no scope. 49 of the last 60 commits touch more than one file, so the rule is broken by nearly every prompt you write. (C11)
- **CLAUDE.md had five stale facts**, all corrected in this branch. The important one: it said unfinished accounts are "never deleted automatically", but the `stale-accounts-daily` job is active on live and deletes them after 30 days. (S1 to S5)
- **Memory was behind the code.** Six memory files called branches "unmerged" that are all merged into `main`; one still warned not to apply the handshake Phase B lockdown, which is in live history. Corrected. (S8 to S14)
- **Most of the "known suspects" are not written down anywhere.** No file says "commits go to main", "branch per prompt", "screenshots required", or "no worktrees". Those conflicts are between your prompts and past practice, so the fix is to write the winner into CLAUDE.md once. (C2, C3, C7)
- **Attribution is consistent.** Global settings blank it, and the last trailer in history is from 2026-09-28. (C6)

Verified on 2026-11-12, read-only: `supabase migration list --linked` (136 local files, 136 live versions, no mismatch); `cron.job` (`stale-accounts-daily` active); security advisor (leaked-password warning still present); `git branch --merged main`.

## 2. What was read

| File | Dated | What it tells the agent | Does its reason still hold |
|---|---|---|---|
| `CLAUDE.md` | last edit 2026-11-11 | Commands, architecture, Supabase rules (grants, deletion, migrations, lock order), seven working rules | Mostly. Five stale facts fixed here. Three rules had no reason; one still has none. |
| `.claude-backup/CLAUDE.md` | 2026-09-29 | The pre-trim CLAUDE.md: includes `flutter run`, automatic orphan deletion, `docs/` paths | No. Superseded snapshot. See S7. |
| `.claude/settings.json` | 2026-07-23 | Hooks: `code-review-graph update` after each edit, `status` at session start | Yes. |
| `.claude/settings.local.json` | 2026-10-27 | 156 allow entries, 12 deny entries | Deny list yes. Allow list conflicts with the header. See C8. |
| `.claude/skills/*` (4) | 2026-09-29 | How to use the code-review-graph tools | Yes. Opt-in, no rules. |
| `.agents/skills/*` (9, tracked) | 2026-05-24 | caveman, cavecrew, impeccable skill text | Not read by Claude Code from here. See S16. |
| `~/.claude/CLAUDE.md` | 2026-10-09 | Use the graphify skill "before doing anything else" on `/graphify` | No. The skill is not installed. See S6. |
| `~/.claude/settings.json` | 2026-10-01 | Blank attribution; enables Ponytail and claude-mem | Yes. |
| `~/.claude/skills/*` | 2026-05 to 2026-09 | caveman set, cavecrew, find-skills, impeccable, security-and-hardening | Opt-in. See C10, S21, S23. |
| `~/.claude/references/*` (2) | 2026-09-23 | Accessibility and security checklists | Reference only, no agent rules. |
| `~/.claude/plans/` | none | Does not exist | n/a |
| Ponytail 4.8.4 (plugin, session hook) | installed 2026-07-22 | Simplest working solution; short output | Yes. Matches the header. |
| claude-mem 13.1.0 (plugin, session hook) | installed 2026-05-11 | Injects "recent context" at session start | No. Last observation 2026-10-28. See S15. |
| `karpathy-guidelines` (app skill bundle) | synced by the desktop app | Small changes, surface assumptions, test before done | Overlaps Ponytail. See C1. |
| Memory: `MEMORY.md` + 25 files | 2026-07-02 to 2026-11-06 | 4 feedback rules files, 21 project state files | Rules partly. State was stale in 14 files; fixed. |
| Tracker `docs/audits/audit-2026-09-29.md` | 2026-09-29, notes to 2026-10-29 | Finding list with a "Size / model" label per item | Findings yes. Model labels no. See C5, S19. |
| `dev/` reports, designs, runbooks (19 `.md`) | 2026-07-30 to 2026-11-11 | Records of past prompts; runbook and release steps | Yes. They record rules rather than set them. |

Not opened, because they can hold tokens: `~/.claude.json`, `~/.claude/.credentials.json`, `.claude-backup/claude.json.home`.

## 3. Findings

Severity: High = can cause an action you forbid, or stops a long task. Medium = misleads the agent or causes a needless question. Low = noise.

### 3.1 Conflicts

| ID | File | Section | Finding | Severity | Proposed fix |
|---|---|---|---|---|---|
| C1 | App skill bundle; `~/.claude/settings.json` | `karpathy-guidelines`; `enabledPlugins` | Two coding guides. Ponytail is always on (session hook). Karpathy loads only when invoked. They differ on tests ("write a test that reproduces it" vs "one runnable check") and dead code ("mention it" vs "deletion over addition"). | Low | Ponytail wins. Add one line to CLAUDE.md Rules. Q4. |
| C2 | none (practice) | n/a | No file states a branch policy. Up to 2026-10-13 each fix had its own branch (20 merged branches). From 2026-10-27 to 2026-11-11 commits went straight to local `main`. Today's header says "the working branch". | Medium | Write the policy into CLAUDE.md. Q3. |
| C3 | `.claude/settings.local.json` | `permissions.allow` | No file requires screenshots. `dev/hygiene/06b2_device_checks.md` and one memory agree with text-only checks. The only contradiction is the allow entry `adb exec-out screencap *`. | Medium | Text-only wins. Remove the entry (part of Q1). |
| C4 | memory `feedback_diff_review_format.md`, `project_timezone_rework.md`, `project_account_section_relocation.md` | "How to apply", "Process" | Three memories describe a hold: "don't commit until reviewed", "pending the user's go/no-go", "show client diffs before approval, one migration at a time". The header makes local commits FREE once analyze and tests pass; October has 147 commits. | Medium | Header wins. Scope the memories to "paste the diff when asked". Q5. |
| C5 | `docs/audits/audit-2026-09-29.md`; `dev/hygiene/checkin_rpc_design.md:17` | "Size / model" (33 item lines, 27 table cells) | Each item is labelled "Opus" or "Sonnet-medium", written when the models were Sonnet 5 and Opus 5.5. No settings file pins a model or effort. The header says subagents run on Sonnet. | Low | The session's model wins. Treat the label as history; use only the size. No file change needed. |
| C6 | `~/.claude/settings.json` | `attribution` | Blank commit and PR attribution, no session link. Set 2026-09-29. History has 110 trailers, the last on 2026-09-28. Agrees with the header. | None | No change. |
| C7 | memory `feedback_side_fixes_worktree.md` | whole file | "Side fixes go in a git worktree, never a branch switch in the main folder." No file says "no worktrees". One worktree exists (`../gym_buddy_dark`, `style/dark-only`, 3 commits ahead). This task's "commit on branch" in the main folder contradicts the unscoped "never". | Medium | Scope added (applied): the rule holds while other work is in flight in the main folder. Policy: Q3. |
| C8 | `.claude/settings.local.json` | `permissions.allow` | Pre-approved: `git push origin main`, `flutter install *`, `adb exec-out screencap *` (all NEVER in the header); `supabase db *` (covers `db push` and `db query -f`, which apply migrations: ASK FIRST); `flutter pub *` (covers `pub add`: ASK FIRST). | High | Header wins. Move the five entries out of `allow`. Q1. |
| C9 | `CLAUDE.md` | Supabase rules, Migrations | Says apply with `supabase db query --linked -f` then `migration repair`. Reports show `supabase db push` after a dry run for 05d, the check-in RPC and 07. Both avoid the MCP tool, which is the rule's reason. | Medium | Name `db push` as the default. Q6. |
| C10 | `~/.claude/skills/caveman-commit` | Rules | Conventional Commits, subject at most 50 characters, "auto-triggers when staging changes". The repo has used plain-sentence subjects with no prefix since October (0 of 49 November commits use a prefix; 36 of the last 100 subjects are over 72 characters). No file documents the style. | Low | Repo practice wins. Document it in CLAUDE.md. Q4. |
| C11 | `CLAUDE.md`; memory `feedback_rules.md` rule 3 | Rules | "One page at a time: touch only the file asked about", and in memory "if a fix touches another file, stop and ask first". 49 of the last 60 commits touch more than one file. Conflicts with "finish the whole task". | High | Scope it to single-page UI requests. Q2. |
| C12 | `CLAUDE.md`; memory `feedback_rules.md` rule 5 | Rules | "Commit before starting anything new", and in memory "if the tree is not clean, prompt to commit first". `macos/Flutter/GeneratedPluginRegistrant.swift` has been modified and uncommitted since Google sign-in landed (2026-11-11), so every session starts dirty. | Medium | Commit that file, or scope the rule to the agent's own work. Q7. |
| C13 | header; `lib/theme/app_theme.dart`; `CLAUDE.md` | Theme | Header: "Emerald Ink only". Code has three accent skins and an Accent Theme setting; CLAUDE.md says the Coach Max gradient "doesn't follow the accent skin". Unclear whether the other two skins must keep working. | Low | Q8. |
| C14 | `CLAUDE.md`; memory `feedback_rules.md` rule 4; header | UI approval | Three wordings of one rule. Only the header says to stop at the UI item and carry on with the rest. CLAUDE.md's "wait for approval" reads as stopping the whole task. | Low | Use the header's wording in CLAUDE.md. Part of Q2. |

### 3.2 Stale facts and stale cautions

| ID | File | Section | Finding | Severity | Proposed fix |
|---|---|---|---|---|---|
| S1 | `CLAUDE.md` | Non-obvious service facts | Documents `PresenceService`. It was deleted in 4a7591c. | Medium | **Applied.** Bullet removed. |
| S2 | `CLAUDE.md` | Account deletion | "Unfinished accounts … never deleted automatically." Migration 20261111190000 is in live history and `stale-accounts-daily` is active: they are deleted after 30 days. | High | **Applied.** Sentence now states both behaviours. |
| S3 | `CLAUDE.md` | Commands | The deploy list omits `stale-accounts-cron`. | Low | **Applied.** |
| S4 | `CLAUDE.md` | Architecture | Says `AuthWrapper` routes to `SplashScreen` or `HomeScreen`. It also routes unfinished accounts to `OnboardingHost`. | Low | **Applied.** |
| S5 | `CLAUDE.md` | Architecture | Tab order listed as Dashboard, Friends, Schedule. Code order is Schedule, Friends, Dashboard, Shop, Profile, opening on Dashboard. | Low | **Applied.** |
| S6 | `~/.claude/CLAUDE.md` | graphify | Points at `~/.claude/skills/graphify/SKILL.md`. No such skill exists, and no `graphify` command is installed. "Before doing anything else" has no reason. | Low | Delete the section or reinstall. Q9. |
| S7 | `.claude-backup/CLAUDE.md` | whole file | A stale CLAUDE.md that Claude Code would load if it read any file in that folder. It lists `flutter run` and the old automatic account deletion. | Medium | Rename or delete. Q9. |
| S8 | memory: 6 project files + index | status lines | "Unmerged" or "not pushed" for `feat/handshake-pushes`, `feat/handshake-card`, `fix/profile-visibility`, `fix/finish-guards`, `fix/credit-sweep-05b`, `fix/live-23-25-teams-streaks`, `fix/live-24-sessions-caps`. All are merged; `main` equals `origin/main`. | Medium | **Applied.** |
| S9 | memory `project_handshake.md` | Phase B | "NOT applied. Apply in H4 only after the new app is installed." Migration 20261012190000 is in live history. | Medium | **Applied.** |
| S10 | memory `project_supabase_live_drift.md` + index | whole file | "LIVE db ≠ repo migrations … never trust the repo migration alone." History was reconciled 2026-07-20 and matches today. | Medium | **Applied.** Scope added: still check grants, policies and pre-version-control objects on live. |
| S11 | memory `project_security_audit_remaining.md` + index | description | "Groups E/F/G still open + Delete Account UI needed." The body records all of them done; only leaked-password protection is open. | Low | **Applied.** |
| S12 | memory `project_account_section_relocation.md` + index | status | "NOT YET COMMITTED." It is commit e0d55f4 on `main`. | Low | **Applied.** |
| S13 | memory `project_checkin_rpc.md`, `project_27_notification_inbox.md`, `project_onboarding_rebuild.md`, `project_timezone_rework.md`, `project_naive_timestamp_sweep.md` | descriptions | Descriptions describe an earlier state than the body or the code (for example "Migration B waits", "mockups next", "in-flight", "~25 sites"; 6 remain). | Low | **Applied.** |
| S14 | memory: 8 files | paths | 16 references to `docs/…` paths that moved to `dev/`. | Low | **Applied.** |
| S15 | claude-mem plugin | SessionStart hook | Injects about 17,000 tokens of "recent context" per session. The newest observation is from 2026-10-28, and some lines are now false (for example "incomplete accounts are deleted on re-login"). It overlaps the file memory. | Medium | Disable it or repair capture. Q10. |
| S16 | `.agents/skills/` | 9 folders, tracked | Byte-identical to `~/.agents/skills`. Claude Code does not load `.agents/` from a repo. | Low | Remove from the repo. Q9. |
| S17 | `.claude/settings.local.json` | `permissions.allow` | About 60 one-off entries (fixed `sed` line ranges, old scratchpad paths, a `docs/architecture_map.md` grep). Harmless, but they bury the five entries in C8. | Low | Prune when editing for Q1. |
| S18 | session header (your pasted block) | FREE list; task text | `docs/hygiene/suite/run.sh` is now `dev/hygiene/suite/run.sh`. "Tracker and handoff files under docs/" are under `dev/`. The deliverable path was `docs/`. | Medium | Update the prompt template. |
| S19 | `docs/audits/audit-2026-09-29.md` | location | The only working file left under `docs/`. It is kept out of git by `.git/info/exclude`, so it is not published, but it sits in the public folder. | Low | Move to `dev/audits/` and update the exclude line. Q9. |
| S20 | `CLAUDE.md` | Rules | Three absolute rules had no reason. "Warm/orange is for the primary CTA only" has no reason recorded in any file. | Low | **Applied** for three, using the reasons recorded on 2026-09-22. The fourth is left as is. |
| S21 | `~/.claude/skills/security-and-hardening` | "Always Do (No Exceptions)" | Written for web servers (CORS, security headers, session cookies). Most items do not apply to Flutter on Supabase. Opt-in. | Low | No change. |
| S22 | Ponytail hook | Output | "At most three short lines" is a rigid style limit, but the same text exempts reports the user asked for, and the header asks for recaps. | Low | No change. |
| S23 | `cavecrew`; `claude-mem:do` | whole skill | Both delegate edits to subagents. The header says not to. Opt-in only. | Low | Header wins. No change. |
| S24 | memory `feedback_rules.md` | rules 1 to 5 | Restates five CLAUDE.md rules in different words and adds three stop-and-ask steps that CLAUDE.md does not have. The index says "5 hard rules"; CLAUDE.md now has seven. | Medium | Delete the memory file once Q2 and Q7 are answered; CLAUDE.md now carries the reasons. |

### 3.3 Gaps: mistakes on record that no instruction file covers

| ID | Evidence | Mistake | Proposed line for CLAUDE.md |
|---|---|---|---|
| G1 | f44a77e, 2026-11-11 | Working files (rollback SQL, the schema baseline, audit reports) sat in `docs/` and were served by GitHub Pages. | "`docs/` is the public website. Working files go in `dev/`." |
| G2 | `dev/hygiene/07_report.md`; memory `feedback_unquoted_heredoc.md` | An unquoted heredoc ran `supabase db push` and the suite. Separately, a `git commit -m` with backticks ran them as commands. Covered by memory and the header, not CLAUDE.md. | "Write reports with the Write tool. Commit messages with backticks go through `git commit -F <file>`." |
| G3 | memory `project_account_section_relocation.md` | Two real account deletions from guessed tap coordinates near the Delete button. The lesson lives only inside a project note, and `adb shell input *` is pre-approved. | "Before any `adb shell input tap`, read the element bounds from a `uiautomator dump`. Do not tap near destructive controls on a non-test account." |
| G4 | memory `project_handshake.md` | A test account was credited by the cron because a session was left `in_progress` with a backdated start. | "On test accounts, do not backdate `workout_started_at` or leave sessions `in_progress`; `process_stale_sessions` credits them." |
| G5 | memory `project_supabase_live_drift.md`, `project_live_23_25_teams.md`; d53802a | Two grant traps: a column-level `REVOKE` does nothing against a table-level grant, and `REVOKE INSERT, UPDATE (col)` revokes table-level INSERT. The second nearly broke onboarding. | Add both to "Table grants must be explicit". |
| G6 | `dev/hygiene/05d_report.md:66` | A cron job was called healthy from its run status without reading its command. Corrected in 05e. | "Judge a scheduled job by its command and its effect, not its run status." |
| G7 | `dev/hygiene/05e_report.md:75` | A race test ran one session only, because `&` backgrounded the line that set a variable. | "After a two-session race test, check that both output files exist before reading results." |
| G8 | cf7b7cb, 2026-11-05 | Migration 20261008200000 replaced `process_stale_sessions` and dropped its pushes. Solo check-ins had no push for four weeks. | "Before `CREATE OR REPLACE`, diff the new body against `pg_get_functiondef` on live and account for every removed line." |
| G9 | C2, C10 | Branch policy and commit message style are practice only. | See Q3 and Q4. |

None of the G lines are applied. They are new rules, so they need your yes. Recommendation: add G1, G3, G5 and G8; the others are already covered by the suite, the header or memory.

## 4. Resolution per conflict

| ID | Winner | Files that change | Status |
|---|---|---|---|
| C1 | Ponytail | `CLAUDE.md` (one line) | Needs Q4 |
| C2 | Your choice | `CLAUDE.md` (one line) | Needs Q3 |
| C3 | Text-only checks | `.claude/settings.local.json` | Needs Q1 |
| C4 | Header: local commits are free | memory `feedback_diff_review_format.md`, `project_timezone_rework.md` | Needs Q5 |
| C5 | The session's model | none | Closed |
| C6 | No conflict | none | Closed |
| C7 | Scoped worktree rule | memory `feedback_side_fixes_worktree.md`, `MEMORY.md` | Scope applied; policy needs Q3 |
| C8 | Header | `.claude/settings.local.json` | Needs Q1 |
| C9 | `supabase db push` after a dry run | `CLAUDE.md` (Migrations) | Needs Q6 |
| C10 | Repo commit style | `CLAUDE.md` (one line) | Needs Q4 |
| C11 | Header: finish the task | `CLAUDE.md` (Rules), memory `feedback_rules.md` | Needs Q2 |
| C12 | Scoped rule | the generated file, or `CLAUDE.md` (Rules) | Needs Q7 |
| C13 | Your choice | `CLAUDE.md` (Rules) | Needs Q8 |
| C14 | Header wording | `CLAUDE.md` (Rules) | Needs Q2 |

## 5. Applied in this branch

Only stale facts, and reasons or scope added without changing a rule's meaning.

`CLAUDE.md` (in the commit):
1. Commands: `stale-accounts-cron` added to the deploy list.
2. Architecture: `AuthWrapper` routing now names `OnboardingHost`.
3. Architecture: tab order corrected.
4. Service facts: `PresenceService` bullet removed.
5. Account deletion: states that sign-in never deletes an unfinished account and that the daily job deletes it after 30 days, with the three exclusions.
6. Rules: reasons added to "One page at a time", "UI changes" and "Commit before starting anything new".

Memory files (outside the repo, so not in the commit; originals copied to the session scratchpad):
1. `docs/` paths changed to `dev/`: 16 references in 8 files.
2. `MEMORY.md`: 13 index lines brought up to date.
3. A dated "Status checked 2026-11-12" line appended to 12 project files. The old text above it is kept.
4. 8 descriptions rewritten to match their bodies, including the scope on `feedback_side_fixes_worktree.md`.

18 memory files changed in total.

Nothing was deleted. No settings file, skill, plugin or file outside the repo and memory folder was changed.

## 6. Owner questions

Each has a recommendation. The exact change is ready for each.

1. **Remove the five risky allow entries?** In `.claude/settings.local.json`, delete `Bash(git push origin main)`, `Bash(flutter install *)` and `Bash(adb exec-out screencap *)`, and move `Bash(supabase db *)` and `Bash(flutter pub *)` to `ask`. Read-only `supabase db query` calls would then prompt. **Recommend yes**, plus allow entries for `supabase db push --dry-run` and `supabase migration list` so read-only checks stay silent.
2. **Scope "one page at a time"?** Proposed text: "A request about one page changes only that page. A prompt that spans files changes what it needs and nothing else. UI without an approved mockup: write the spec, stop at that item, carry on with the rest." **Recommend yes.**
3. **Branch policy?** Options: a branch per prompt, named in the prompt, in the main folder; or straight to local `main`. And: worktrees only when the main folder has work in flight, or never. **Recommend a branch per prompt and the scoped worktree rule.**
4. **Record three decisions in CLAUDE.md?** "Coding style: Ponytail, not karpathy-guidelines." "Commit subjects are one plain sentence, no type prefix, no attribution." "`docs/` is the public website; working files go in `dev/`." **Recommend yes.**
5. **Drop the commit hold from memory?** Reword `feedback_diff_review_format.md` to "paste the diff text when asked" with no standing hold on local commits, and mark the timezone "per-fix gate" as history. **Recommend yes.**
6. **Name `supabase db push` as the way to apply?** Proposed: "Apply with `supabase db push` after `--dry-run` lists only the new file. If push cannot be used, `db query --linked -f` then `migration repair --status applied`. Never the MCP tool." **Recommend yes.**
7. **Commit the generated macOS file?** `macos/Flutter/GeneratedPluginRegistrant.swift` gained the two `google_sign_in_ios` lines on 2026-11-11. **Recommend committing it on `main` as its own commit**, and scoping the rule to "commit your own work before starting something new".
8. **Does "Emerald Ink only" mean the other two skins may break?** **Recommend:** build and check in Emerald Ink, and keep Signal blue and Lime spark compiling through tokens, until you decide to remove them.
9. **Clean up four leftovers?** Delete the graphify section from `~/.claude/CLAUDE.md`; rename `.claude-backup/CLAUDE.md` to `CLAUDE.md.bak`; `git rm -r .agents`; move the tracker to `dev/audits/` and update `.git/info/exclude`. **Recommend yes to all four.** The first two are outside the repo, so they need your word.
10. **Turn off claude-mem?** It has recorded nothing for this project since 2026-10-28 and adds about 17,000 tokens of old context to every session. **Recommend disabling it** in `~/.claude/settings.json`; the file memory covers the same ground.
11. **Add gap rules G1, G3, G5, G8 to CLAUDE.md?** **Recommend yes.**
