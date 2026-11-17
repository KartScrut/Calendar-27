# Setting up TWELVE

A step-by-step guide for someone who has never built an app. You can stop after step 3 and have the app running on your Mac in guest mode; later steps add accounts, a real iPhone, TestFlight and the App Store.

**What needs what**

| To do this | You need |
|---|---|
| Run in the iPhone simulator (steps 1–3) | A Mac. Nothing else — it's free |
| Sign-in and cloud backup (steps 4–5) | A free Supabase account |
| Sign in with Apple, widgets on a real iPhone, TestFlight, App Store (steps 6–11) | An Apple Developer Program membership (paid, yearly) |

---

## 1. Install the software

1. On your Mac, open the **App Store**, search for **Xcode**, and install it. You need **Xcode 26 or later** (the app targets iOS 26). It is a large download.
2. Open Xcode once and accept the prompts to install the **iOS** platform.

## 2. Open the project

1. Download this repository: on its GitHub page choose **Code → Download ZIP**, then unzip it. (Or use `git clone` if you know how.)
2. Double-click **`Twelve.xcodeproj`**.
3. Wait a moment while Xcode reads the project. The first time, it may show "Resolving package graph" — let it finish.

## 3. Run it in the iPhone simulator

1. At the top of the Xcode window, click the device name next to **Twelve** and pick an iPhone, for example **iPhone 17**.
2. Press the **▶ Run** button (or **⌘R**).
3. The simulator opens and TWELVE launches. Complete onboarding and choose **Explore as a guest**.

**Seeing 2027 today.** Before 1 January 2027 the app shows a countdown, because real progress can't be earned early. To try everything now:

1. Go to the **Profile** tab and scroll to **Preview mode**.
2. Pick a date in 2027 and tap **Preview this date**.
3. Use **Stamp earlier months (demo)** to see a fuller collection, and **Return to today** when you're done.

Preview mode keeps its own demo data, never syncs, and is not included in App Store builds.

**Adding widgets in the simulator:** long-press the Home Screen → **Edit → Add Widget** → search for **TWELVE**.

## 4. Create and configure the Supabase project

Supabase is the service that stores accounts and backups.

1. Go to [supabase.com](https://supabase.com), create an account, and click **New project**. Choose a name, a strong database password (save it in a password manager), and a region near your users.
2. When the project is ready, open **SQL Editor** in the left sidebar. You will run three files from this repository, in this order. For each: open the file on your Mac in TextEdit, select all, copy, paste into the SQL Editor, and click **Run**.
   1. `supabase/migrations/20261117000000_initial_schema.sql` — creates the tables and security rules.
   2. `supabase/seed/content_seed.sql` — adds the twelve challenges and the discovery cards.
   3. `supabase/seed/sudoku_seed.sql` — adds the Sudoku puzzles and their solutions.

   Each should finish with "Success". Do **not** run anything from `supabase/tests/`; those files are only for automated testing.
3. Turn on email codes: **Authentication → Sign In / Providers → Email**. Make sure **Email** is enabled.
4. Make the email contain a code instead of a link: **Authentication → Emails → Templates → Magic Link**. Replace the body with something like:

   ```html
   <h2>Your TWELVE code</h2>
   <p>Enter this code in the app: <strong>{{ .Token }}</strong></p>
   <p>It expires shortly. If you didn't ask for it, you can ignore this email.</p>
   ```

   Do the same for the **Confirm signup** template, so first-time users also receive a code.
5. Before real users arrive, set up your own email sender under **Authentication → Emails → SMTP Settings** (Supabase's built-in sender is only for testing and is heavily limited). Use a proper email provider and add the **SPF**, **DKIM** and **DMARC** records it gives you to your domain.
6. Optional but recommended: **Authentication → Attack Protection** → enable **CAPTCHA** and review **Rate Limits**.

## 5. Put the configuration values in the app

1. In Supabase, open **Project Settings → API** (also shown as **Data API / API Keys**).
2. Copy the **Project URL** (it looks like `https://abcdefgh.supabase.co`).
3. Copy the **anon / publishable** key.

   > Never copy the **service_role / secret** key into the app. That key bypasses all security and must stay on the server.
4. In Xcode, in the left sidebar, open **Twelve → Resources → SupabaseConfig.plist**.
5. Paste the URL as the value of `SUPABASE_URL` and the key as the value of `SUPABASE_ANON_KEY`.
6. Run the app again. On the account step of onboarding (or **Profile → Sign in to back up**), **Continue with email** now works.

Both values are designed to be public — the database's own rules decide what each signed-in person may see — so it is safe for them to be in the app.

## 6. Enable Sign in with Apple

Requires an Apple Developer Program membership ([developer.apple.com/programs](https://developer.apple.com/programs)).

1. **Choose your app's identifier.** The project uses the placeholder `com.twelve.app`. Pick your own, such as `com.yourname.twelve`, and change it in these places:
   - In Xcode, click the blue **Twelve** project icon → target **Twelve** → **Signing & Capabilities** → **Bundle Identifier**.
   - Target **TwelveWidgets** → set its Bundle Identifier to yours plus `.widgets` (for example `com.yourname.twelve.widgets`).
   - `Config/Twelve-Info.plist`: replace `com.twelve.app` wherever it appears (the URL name and the four quick-action types — keep the endings `.spark`, `.challenge`, `.timer`, `.year`).
2. In **Signing & Capabilities** for both targets, tick **Automatically manage signing** and choose your **Team**.
3. In Supabase: **Authentication → Sign In / Providers → Apple** → enable it, and in **Client IDs** enter your app's bundle identifier (for example `com.yourname.twelve`). For a native iPhone app you do not need the secret key or callback fields.
4. Run on a real iPhone (step 9) and tap **Continue with Apple**. (It also works in the simulator if the simulator is signed in to an Apple Account.)

## 7. Configure App Groups and widgets

The app and its widgets share a small storage area called an App Group.

1. The project uses the placeholder `group.com.twelve.app`. Choose your own, such as `group.com.yourname.twelve`.
2. In Xcode, target **Twelve → Signing & Capabilities → App Groups**: remove the placeholder and add yours with the **+** button. Do the same for target **TwelveWidgets**. Xcode registers the group with Apple for you.
3. Open `Packages/TwelveCore/Sources/TwelveCore/WidgetSnapshot.swift` and change the line

   ```swift
   public static let identifier = "group.com.twelve.app"
   ```

   to your group's name. It must match exactly.
4. The capabilities **Sign in with Apple**, **HealthKit** and **App Groups** should all be listed for the **Twelve** target; **App Groups** for **TwelveWidgets**.

## 8. Run the automated tests

- **In Xcode:** press **⌘U**. The app tests and core logic tests run in the simulator; green ticks mean success.
- **Core logic only (Terminal):** `swift test --package-path Packages/TwelveCore`
- **Database tests (optional, needs PostgreSQL installed):** `bash supabase/tests/run_local.sh`
- **On GitHub:** every change runs all of these automatically — see the **Actions** tab.

## 9. Install on a physical iPhone

1. Complete steps 6 and 7 (identifier, team, App Group).
2. Connect the iPhone to the Mac with a cable and unlock it. Tap **Trust** if asked.
3. On the iPhone: **Settings → Privacy & Security → Developer Mode** → turn on, and restart when prompted.
4. In Xcode, choose your iPhone at the top of the window and press **▶ Run**.

Live Activities, the camera and Health only work fully on a real device.

*Without a paid membership* you can still install on your own iPhone with a free Apple Account, but you must first remove the **Sign in with Apple** capability (free accounts can't use it), and the app expires after seven days.

## 10. Distribute a beta with TestFlight

1. Sign in at [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps → + → New App**. Choose iOS, a name, your bundle identifier, and any SKU.
2. In Xcode, choose **Any iOS Device (arm64)** as the destination, then **Product → Archive**.
3. When the Organizer window appears: **Distribute App → TestFlight & App Store → Distribute**.
4. After processing (often 10–30 minutes), open the app's **TestFlight** tab in App Store Connect. Add **Internal Testers** (immediate) or create an **External** group (needs a short beta review).
5. Testers install the **TestFlight** app and accept the invitation.

For each new upload, raise the **Build** number (target **Twelve → General → Identity**).

## 11. Prepare the App Store submission

1. **Screenshots**: run in the simulator (use Preview mode to show real content) and press **⌘S** to save screenshots. App Store Connect lists the sizes required.
2. **Privacy policy URL**: publish the text in [docs/PRIVACY.md](PRIVACY.md) on a web page, after reviewing it with whoever is legally responsible for the app, and enter its address.
3. **App Privacy** answers: use the table in [docs/PRIVACY.md](PRIVACY.md).
4. **Sign-in for reviewers**: because the app uses email codes, provide a test email address whose inbox the reviewer can read — or note that **Explore as a guest** gives full access without an account.
5. **Account deletion**: required by Apple, and already built in (**Profile → Delete Account**). Mention it in the review notes.
6. **Health**: in the review notes, explain that Health access is optional and read-only, used for walking workouts in the September challenge.
7. **Age rating, category (Lifestyle), description, keywords** — fill these in App Store Connect.
8. Choose the build you uploaded in step 10 and click **Submit for Review**.

Before launch, also read the backup checklist in [docs/SECURITY.md](SECURITY.md).

---

## If something goes wrong

| What you see | What to do |
|---|---|
| "Signing for 'Twelve' requires a development team" | Target → **Signing & Capabilities** → choose your **Team** (step 6). Simulator runs don't need it |
| Sign-in buttons say cloud backup isn't set up | `SupabaseConfig.plist` is empty or the URL doesn't start with `https://` (step 5) |
| The email contains a link, not a code | Edit the Supabase email templates (step 4.4) |
| The widget is blank on a real iPhone | The App Group name must be identical in both targets and in `WidgetSnapshot.swift` (step 7) |
| The app shows only a countdown | That's correct before 1 January 2027. Use Preview mode (step 3) |
