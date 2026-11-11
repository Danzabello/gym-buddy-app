# Deleting an account by hand (requests that arrive by email)

For someone who cannot use the app. The in-app route (Profile, Account, Delete Account) calls the `delete-account` Edge Function, which needs
the account holder's own sign-in, so it cannot be used for a request that arrives by email. This does the same two steps by hand, in the same order:
the `user_profiles` row first, then the sign-in account.

Promise made on the public page: deleted within 30 days, and we tell them when it is done.

**Never put the email address in this repo, a commit, a file or an issue.** The commands below read it into a shell variable and nothing else.
`read -r` keeps it out of your shell history. Close the terminal when you are done.

## 1. Check the request

- It must come from the email address of the account. For a Google account that is the Google email address. A request from another address:
  reply to the address on the account and ask them to confirm from there. Do not delete on an unverified request.
- Never delete Coach Max (`00000000-0000-0000-0000-000000000001`) or any account that is not the requester's.

## 2. Find the account

```bash
read -r EMAIL
```

Paste the address, press Enter. Then:

```bash
supabase db query --linked "SELECT u.id, u.created_at, u.last_sign_in_at, (p.id IS NOT NULL) AS has_profile, p.onboarding_completed FROM auth.users u LEFT JOIN public.user_profiles p ON p.id = u.id WHERE lower(u.email) = lower(\$\$${EMAIL}\$\$);"
```

Expect exactly one row. Zero rows: tell them no account was found for that address (it may be deleted already, or they used another address).
More than one row: stop and look. Copy the `id` for the next steps. Ids are not personal text, but still keep them out of the repo.

If the address contains `$$`, do not use this command; type the lookup by hand.

## 3. Delete the profile row, then the sign-in account

Same order as `delete-account`: `user_profiles` has no foreign key to `auth.users`, so deleting only the sign-in account would leave the profile behind.

```bash
read -r ACCOUNT_ID
```

Paste the `id` from step 2. Then:

```bash
supabase db query --linked "DELETE FROM public.user_profiles WHERE id = '${ACCOUNT_ID}'::uuid RETURNING id;"
```

One row back is the usual answer. No row is fine when the account never had a profile.

Then delete the sign-in account in the Supabase dashboard: Authentication, Users, find the id, "Delete user". That calls the Auth admin API, the same
call `delete-account` makes, and it removes the sign-in identities (including the Google name and picture address stored with a Google account).
Everything else that points at the account cascades or is set to NULL, exactly as for an in-app deletion.

A SQL `DELETE FROM auth.users` is not the supported way in this project; use the dashboard.

## 4. Check

```bash
supabase db query --linked "SELECT (SELECT count(*) FROM auth.users WHERE id = '${ACCOUNT_ID}'::uuid) AS auth_rows, (SELECT count(*) FROM public.user_profiles WHERE id = '${ACCOUNT_ID}'::uuid) AS profile_rows;"
```

Both must be 0.

## 5. Tell them

Reply on the same email thread: the account and its data were deleted, with the shared-record exceptions listed on the deletion page
(a team's streak record stays with the remaining members; a workout a buddy created stays on the buddy's account). Then clear the variables:

```bash
unset EMAIL ACCOUNT_ID
```

## Notes

- Keep a private note of the date a request arrived and the date it was completed (no email in it), so you can show it was within the 30 days.
- A request for a copy of the data, or a correction, is handled by hand too, within one month (privacy policy, section 8). There is no export tool.
- Unfinished accounts are deleted on their own after 30 days by the `stale-accounts-cron` job (`supabase/migrations/20261111190000_stale_accounts.sql`).
