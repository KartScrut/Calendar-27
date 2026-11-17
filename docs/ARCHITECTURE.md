# Architecture and design

## The shape of the app

```
┌────────────────────────── iPhone ──────────────────────────┐
│  Screens (SwiftUI)                                         │
│     Today · Calendar · Collection · Profile · Onboarding   │
│     Challenge modules · Spark                              │
│                    │ read / ask                            │
│  AppModel  ── the one place that derives state and decides │
│     │          when a month is complete                    │
│     ├─ DataStore ─────── SwiftData (on-device database)    │
│     ├─ TimerController ─ timed sessions, Live Activity     │
│     ├─ NotificationService                                 │
│     ├─ AuthService ───── Keychain                          │
│     └─ SyncService ───── SupabaseClient ──── HTTPS ───┐    │
│                                                       │    │
│  TwelveCore (no screens): calendar, streaks, progress,│    │
│     Sudoku engine, timer maths, content + selection   │    │
│                                                       │    │
│  Widgets ◄── App Group snapshot (written by AppModel) │    │
└───────────────────────────────────────────────────────│────┘
                                                        ▼
                        Supabase: Auth · PostgreSQL with Row Level Security
                        Server functions verify rewards
```

**Pattern:** modular MVVM. Screens hold no rules. `AppModel` is the observable view model; services do one job each; `TwelveCore` holds every rule as plain, independently tested Swift with no dependency on screens, storage or the network.

**Why it is arranged this way**

- **Progress is never stored — it is recomputed.** The app keeps a log of what you did (`ActivityEntry`). "3 of 5 puzzles" is calculated from that log every time by `ProgressCalculator`. A number that is derived can't drift out of step or be double-counted.
- **Achievements are stored once and never removed.** The first time a month's goal is reached a `StampRecord` is written. Its month is unique, so awarding it again does nothing.
- **Days are fixed when they happen.** Every entry stores the calendar day it belongs to, in the profile's chosen time zone. Travelling later can't move an entry into another month.
- **Nothing ticks.** A timed session is a list of timestamped start / pause / resume / finish events. Elapsed time is calculated from them, so it is exact after backgrounding, locking, or quitting and reopening.
- **The device comes first.** Everything works with no network. Sync is a resumable copy with client-generated ids, so sending anything twice is harmless.
- **The server decides rewards.** For signed-in users the server recomputes progress from the uploaded log before recording an achievement; the app can only ask it to look.
- **Ready for 2028.** Challenges live in a catalog (`challenges.json` / the `challenge_definitions` table) keyed by year and month. A new year is new catalog entries, not new code.

## Screen map

```
Onboarding (first launch)
  1 Welcome → 2 How it works → 3 Interests → 4 Personalise* → 5 Feeling
  → 6 Reminders → 7 Account (Apple · email code · guest) → 8 Your year
  (* only if a chosen interest has a follow-up question)

Tabs
  Today ──────── date · current challenge · Today's Spark · small extra · year so far
                 (before 2027: countdown + two demonstrations; after: archive)
  Calendar ───── Month view (day markers, day detail) ⇄ Year overview (12 stamps)
  Collection ─── stamps · Year in Review · saved discoveries · your words
  Profile ────── name · interests · reminders · account · data · accessibility · privacy

Sheets
  Challenge ──── reveal → story → how it works → activity module → reflection
  Spark ──────── article · source · one interaction · Save · Not interested
  Celebration ── stamp · "One more month made meaningful." · optional reflection
  Year in Review, Sign in
```

## Challenge modules

One reusable module per kind of activity, chosen by the catalog entry:

| Module | Used by | Completion is measured by |
|---|---|---|
| Reflection | January, July, August, December | distinct days, or number of entries |
| Sudoku | February | distinct puzzles correctly solved |
| Timer | March, September | total active minutes |
| Photos | April | number of photos |
| Reading | May | total pages |
| Vocabulary | June | twelve words studied **and** a passed recall exercise |
| Creative | October | three distinct stages |
| Focus | November | sessions that reach the full ten minutes |

## Design system

**Colour tokens** (`TwelveCore/UI/Theme.swift`)

| Token | Light | Dark | Use |
|---|---|---|---|
| `paper` | `#F5EEE3` | `#1C1512` | Screen background |
| `card` | `#FCF8F1` | `#2A201B` | Reading surfaces |
| `feature` | `#30231E` | `#3A2B23` | The most important card on a screen |
| `ink` / `inkSoft` | `#282522` / `#6E6157` | `#F2EADD` / `#B8AB9B` | Text |
| `terracotta` | `#CC8062` | same | Primary accent, calls to action |
| `gold` | `#D5B47A` | same | Achievement, progress |
| `sage` | `#A2B09B` | same | Calm confirmation |
| `accentText` etc. | darker variants | lighter variants | Accent-coloured text with sufficient contrast |

Dark mode is its own palette (a lamp-lit study), not an inversion.

**Type.** Two voices: the system serif (New York) for numerals, months, titles and statements; San Francisco for controls, labels and explanation. Text uses Dynamic Type styles; only display numerals use fixed sizes, with scaling limits.

**Materials.** Paper for content. Liquid Glass only for things that float above content: the tab bar, buttons, toolbars and control clusters.

**Components** (`Twelve/DesignSystem/Components.swift`, `TwelveCore/UI/Stamp.swift`): `PaperCard`, `FeatureCard`, `PrimaryButton`, `SecondaryButton`, `ProgressRing`, `ProgressBar`, `SectionLabel`, `Tag`, `RollingNumber`, `EmptyNote`, `InfoBanner`, `MonthStamp`, `Postmark`, `TwelveDots`, `PaperGrain`.

**Motion.** Springs for navigation and progress; a card flip for the monthly reveal; a pressed stamp for completion; a page slide between months. Every animation has a Reduce Motion alternative, and nothing animates continuously.

**Haptics.** Light tap for selection, a firm thud for a stamp or a starting timer, success for completion, a gentle warning for a wrong answer.

## Widgets

The app writes a small `WidgetSnapshot` into the shared App Group whenever something changes and asks WidgetKit to reload. Widgets read only that snapshot — never the database or network.

- **Home Screen:** small (date + count), medium (date + twelve-mark dial), large (date, twelve months, current challenge, Spark, and a button to tick off the day's small extra).
- **Lock Screen:** circular, rectangular and inline accessories, drawn for the system's monochrome style.
- **Timeline:** one entry now and one at each of the next three midnights. Widgets are not refreshed every second and don't need to be.
- **No leaks:** a snapshot's challenge details are shown only while they belong to the month on screen, so a widget that hasn't refreshed never shows last month's card as current.

## Sync, in order

1. Push profile and interests if changed.
2. Push activity (timed sessions, journal entries) — in batches, falling back to one-by-one so a single refused row can't block the rest.
3. Push Sudoku: solved boards go to a server function that checks them against the stored solution.
4. Push discovery interactions.
5. Pull activity from other devices since the last cursor; pull solved puzzles, achievements, and (once) discovery history.
6. Ask the server to verify any completed month it hasn't verified yet.
7. Pull editorial copy updates for months already revealed.

Failures leave everything on the device untouched and are retried later.

## Regenerating generated files

| Command | Produces |
|---|---|
| `python3 tools/build_content.py` | The bundled content JSON and `supabase/seed/content_seed.sql` from `tools/content/*.py` |
| `python3 tools/generate_sudoku.py` | The validated puzzle library and `supabase/seed/sudoku_seed.sql` |
| `python3 tools/generate_xcodeproj.py` | `Twelve.xcodeproj` (only needed if targets or build settings change) |

To add discovery cards, edit the files in `tools/content/` and run the first command. It refuses to build if a card is outside 50–120 words, lacks an `https` source, or lacks an interaction.
