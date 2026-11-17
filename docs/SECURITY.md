# Security, backups and recovery

No single measure makes a system attack-proof. This document describes the layers TWELVE uses, what each one does, and what remains your responsibility as the operator.

## What is protected, and how

### Sign-in and sessions
- **No passwords.** Sign in with Apple (with a fresh, hashed nonce for every attempt, to prevent replay) or a one-time code sent by email.
- **Tokens live in the Keychain**, readable only on this device after first unlock. Nothing sensitive is written to UserDefaults.
- **Sessions refresh automatically.** If a refresh is rejected, the app signs out locally, keeps all on-device progress, and asks the person to sign in again.
- **The app contains only the public key.** The Supabase `service_role` key is never in the app or this repository.

### Database authorisation
- **Row Level Security is on for every table.** Each policy limits rows to `auth.uid()`.
- **Least privilege.** All default grants are revoked, then only what each role needs is granted — in places down to individual columns (for example, a client cannot write `profiles.joined_at`, or mark a Sudoku attempt as solved).
- **Rewards are written only by server functions** (`claim_month_completion`, `submit_sudoku_solution`). They ignore any totals the client might send and recompute from stored activity.
- **Idempotent by construction.** `achievements` has one row per person per month (primary key). Claiming twice changes nothing.
- **Future challenges are unreadable.** A policy on `challenge_definitions` hides every row whose reveal time has not passed.
- **Sudoku solutions are in a private schema** with no grants to client roles.
- **Server-side sanity limits** mirror the app's: implausible durations, future-dated activity, and active time longer than the session's wall-clock span are rejected by constraints and triggers.
- **Completion criteria are frozen** once a month has started (a trigger rejects such edits).
- **Rate limits** on the reward functions, per person per hour.

These rules are tested on every change by `supabase/tests/security_tests.sql`: cross-user reads and writes, anonymous access, early access to future content, forged achievements, duplicate claims, and account deletion.

### In the app
- HTTPS only; no arbitrary loads.
- Photos are stored on the device with file protection and are never uploaded.
- No third-party SDKs, analytics or advertising code. No third-party dependencies at all.
- Error messages shown to people never echo raw server responses.

### Honest limits
- Most challenges are **honour-based** (a plank, a kind act). The server enforces plausibility and timing, not truth. Sudoku is the exception: boards are verified against stored solutions.
- The bundled catalog means a determined person could extract future challenge text from the app file. The interface never shows it, and the server never serves it early; it is bundled so guests and offline users get their challenge on the 1st. If secrecy matters more than that, remove future months from `challenges.json` and ship them from the server after each reveal.
- **App Attest** is not enabled. It would make it harder for modified apps to call your backend, at the cost of extra server work. Consider it if you see abuse; it is one more layer, not a guarantee.

## What you must configure (operator checklist)

- [ ] Use a strong, unique database password and enable **two-factor authentication** on your Supabase and Apple accounts.
- [ ] In Supabase **Authentication → Attack Protection**: enable CAPTCHA and review rate limits for sign-in and code emails.
- [ ] Set a short one-time-code lifetime (for example 10 minutes) under the Email provider settings.
- [ ] Use your own SMTP provider with **SPF, DKIM and DMARC** before launch.
- [ ] Never paste the `service_role` key into the app, a chat, or a commit. If it is ever exposed, rotate it immediately (**Project Settings → API**).
- [ ] Keep `supabase/tests/00_stub_auth.sql` away from the real project — it is for local testing only.
- [ ] Review **Database → Security Advisor** in Supabase after applying the schema.
- [ ] Turn on GitHub **secret scanning** and **Dependabot alerts** for this repository.

## Backups

| Layer | What to do |
|---|---|
| Managed daily backups | Included on paid Supabase plans. Confirm under **Database → Backups** |
| Point-in-time recovery | Enable the PITR add-on before launch if losing up to a day of data is unacceptable |
| Independent copy | Weekly, export with `pg_dump` to encrypted storage you control (a different provider), and keep several generations |
| On the device | Progress is saved locally first and is not discarded when sync fails. Signed-in users' data is restored on a new device by signing in |
| For the person | **Profile → Export my data** produces a readable file at any time |

**An independent, encrypted copy** (run from a trusted computer; the connection string is in **Project Settings → Database**):

```bash
pg_dump "postgresql://postgres:[PASSWORD]@db.[PROJECT].supabase.co:5432/postgres" \
  --format=custom --no-owner --file "twelve-$(date +%F).dump"
```

```bash
gpg --symmetric --cipher-algo AES256 "twelve-$(date +%F).dump"
```

Store the encrypted file off-site and delete the unencrypted one.

## Restoring

1. **Small mistake, recent:** use PITR in the Supabase dashboard to restore to a moment before it.
2. **From a daily backup:** **Database → Backups → Restore**.
3. **From your own copy**, into a new project:

   ```bash
   pg_restore --clean --if-exists --no-owner \
     --dbname "postgresql://postgres:[PASSWORD]@db.[NEW-PROJECT].supabase.co:5432/postgres" twelve-2027-03-01.dump
   ```

   Then put the new project's URL and anon key in `SupabaseConfig.plist` and release an app update.

**Rehearse this.** Twice a year, restore your latest copy into a scratch project and run `supabase/tests/security_tests.sql`-style spot checks (row counts, a test sign-in). A backup that has never been restored is a hope, not a backup.

## A custom website or API later

Cloudflare is not needed for the app itself: it talks directly to Supabase's managed endpoints, which you should not proxy. If you add a marketing site or your own API, put that behind Cloudflare (DNS, CDN, WAF, rate limiting), send any email through a provider with SPF/DKIM/DMARC, and don't publish origin IP addresses or unused DNS records.

## Reporting a problem

If you find a security issue, contact the repository owner privately before disclosing it.
