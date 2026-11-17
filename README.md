# TWELVE

**Make the year count.** A native iPhone app built around 2027: one meaningful challenge each month, a daily discovery, and a collection of twelve stamps to show for the year.

| | |
|---|---|
| Platform | iPhone, iOS 26 or later, SwiftUI |
| Storage | On-device (SwiftData), with optional cloud backup (Supabase) |
| Accounts | Guest, Sign in with Apple, or an emailed one-time code — no passwords |
| Extras | Home Screen and Lock Screen widgets, Live Activities, Siri Shortcuts, quick actions |
| Third-party code | None. Apple frameworks only |

## Start here

- **Running the app for the first time?** Follow [docs/SETUP.md](docs/SETUP.md). It assumes no programming experience.
- **Want to see 2027 before it starts?** Run the app from Xcode, open **Profile → Preview mode**, and pick a date. (Preview mode exists only in development builds and uses separate demo data.)
- **How it is built:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Security, backups and restoring:** [docs/SECURITY.md](docs/SECURITY.md)
- **Privacy policy draft and App Store privacy answers:** [docs/PRIVACY.md](docs/PRIVACY.md)

The app works with no setup at all in **guest mode**: everything is saved on the iPhone. Sign-in and cloud backup switch on once you add your Supabase project's details (step 4 of the setup guide).

## What's in this repository

| Folder | What it holds |
|---|---|
| `Twelve/` | The app: screens, services, on-device data |
| `TwelveWidgets/` | Home Screen widgets, Lock Screen widgets, the timer Live Activity |
| `Shared/` | Code used by both the app and the widgets |
| `Packages/TwelveCore/` | All rules with no screen attached: calendar, streaks, progress, the Sudoku engine, timers, content selection — plus the challenge catalog, puzzles and discovery cards |
| `TwelveTests/` | App-level tests |
| `supabase/` | Database schema, security rules, seed content and database tests |
| `tools/` | Scripts that generate the puzzle library, content files and Xcode project |
| `Config/` | Info.plist files and entitlements |
| `.github/workflows/` | Automatic checks that run on every change |

## Checks that run automatically

Every push runs four jobs (see the **Actions** tab on GitHub):

1. **Core logic tests** — calendar rules, streaks, progress, Sudoku, timers, content.
2. **Database tests** — applies the schema to a fresh PostgreSQL and proves one person can't read or change another's data, future challenges can't be fetched early, and rewards can't be forged or duplicated.
3. **Content** — rebuilds the content files and checks every discovery card's source link.
4. **iOS build and tests** — builds the app and widgets and runs the app tests in an iPhone simulator.
