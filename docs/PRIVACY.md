# Privacy

This is a plain-language draft that describes how the app actually behaves. Before publishing it as your privacy policy, add your contact details and have it reviewed for the countries you operate in.

## Privacy policy (draft)

**TWELVE collects only what it needs to work.**

**If you use TWELVE as a guest**, everything stays on your iPhone. We receive nothing.

**If you create an account**, we store, linked to your account:

- your email address (or the private relay address Apple provides), to sign you in;
- your chosen interests, preferences and calendar time zone;
- the activity you log toward each month — for example session lengths, pages read, words learned, and the text of entries you write;
- which puzzles you have solved and games in progress;
- which discoveries you have viewed, answered, saved or dismissed;
- your achievements.

**What never leaves your iPhone:** photos you add, and anything from Apple Health beyond the length and date of walking workouts you choose to import.

**What we never do:** sell your data; show advertising; use your writing for advertising or profiling; include third-party analytics or tracking; record your location.

**Health data.** Connecting Apple Health is optional. If you do, TWELVE reads walking workouts so they can count toward the walking challenge. Health data is not used for marketing and is not shared with third parties.

**Notifications** are optional, are scheduled on your device, and can be changed at any time.

**Where data is stored.** Account data is stored with our database provider, Supabase, in the region chosen for the project, encrypted in transit and at rest.

**Your choices.** In **Profile** you can export your data, erase the app's data from your iPhone, or delete your account. Deleting your account permanently removes your data from our servers.

**Children.** TWELVE is not directed at children under 13.

**Contact:** *[your name or company, and a contact email]*

## App Store "App Privacy" answers

For a build with accounts enabled. (A guest-only build with an empty `SupabaseConfig.plist` collects nothing.)

| Data type | Collected? | Linked to the person | Used for tracking | Purpose |
|---|---|---|---|---|
| Email address | Yes | Yes | No | App functionality (sign-in) |
| User ID | Yes | Yes | No | App functionality |
| Other user content (written entries) | Yes | Yes | No | App functionality (backup and sync) |
| Fitness (session durations for plank and walking) | Yes | Yes | No | App functionality |
| Product interaction (discoveries viewed/saved, puzzle progress) | Yes | Yes | No | App functionality |
| Photos | **No** — stored on the device only | — | — | — |
| Health (HealthKit) | Read on device; only workout date and duration are stored if imported | Yes | No | App functionality |
| Location, contacts, identifiers for advertising, diagnostics | **No** | — | — | — |

"Does this app track?" — **No.**

## Permissions the app may ask for

| Permission | When | Why |
|---|---|---|
| Notifications | Only after you choose a reminder type | To deliver the reminders you chose |
| Camera | Only when you tap Camera in a challenge | To take a photo for that challenge |
| Health (read) | Only when you tap Connect Health | To import walking workouts |

The photo picker does not need permission: TWELVE receives only the photos you select.
