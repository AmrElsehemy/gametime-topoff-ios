# Top Off analytics

## What this is, and what it is not

Top Off records a small, fixed set of gameplay events **on the device**. Nothing is sent anywhere today: no analytics SDK, no network calls, no backend. That keeps the App Store privacy answer at "Data Not Collected" and `PrivacyInfo.xcprivacy` accurate.

The point is to answer, once real players (or TestFlight testers) exist: where do they finish, struggle and quit? It follows the event vocabulary in `gametime-ios/docs/ANALYTICS_AND_EXPERIMENTS.md`.

## Where the data lives

- Events are appended, one JSON object per line, to `Application Support/TopOff/events.jsonl` on the device.
- The file is trimmed to the newest 5,000 events, so it cannot grow without bound.
- **Debug builds and TestFlight** show a "Tester tools" section at the bottom of the level menu: a summary of this device's play, an **Export log** share button, and **Clear**. App Store builds show players nothing.

## Privacy by construction

- Identity is a random install id created on first launch. It is not derived from the device, the player or any advertising identifier, and it disappears when the app is deleted.
- Events carry only coarse gameplay facts. The full list of property keys is `TopOffEvent.allowedPropertyKeys`, and a test fails if any event ever carries a key outside it. There is no free text, no name, no email, no location, no IDFA.
- Forwarding to any remote client is gated by `AnalyticsPipeline.setSharingEnabled`, which is **off by default**, and no client is attached.

## Schema (version 1)

Every event also carries: `schema`, `app_version`, `build`, `install_id`, `session_id`, `seq`, `ts` (ms since epoch), `platform`, `idiom` (phone or pad), `os_major`, `lang`.

| Event | When | Properties |
|---|---|---|
| `first_open` | first ever launch | none |
| `session_start` / `session_end` | a gap of over 30 minutes starts a new session | end: `duration_s`, `levels_completed` |
| `level_started` | a level appears | level facts + `attempt` |
| `level_completed` | level solved | level facts + run stats + `stars`, `streak` (daily) |
| `level_abandoned` | left a level after playing it, or backgrounded mid-level | level facts + run stats + `reason` (`left_level`, `session_end`, `backgrounded`) |
| `level_restarted` | restart used | `level_id`, `moves_before` |
| `undo_used` | undo used | `level_id`, `moves` |
| `stuck_shown` / `stuck_resolved` | the board proves unsolvable / the first action after | `level_id`, `moves` / `via` (`undo`, `restart`, `bottle`) |
| `booster_offered` / `declined` / `cancelled` | rewarded-video prompt outcomes | `booster`, `level_id` |
| `booster_granted` | hint or extra bottle given | `booster`, `level_id`, `via_ad`, `free_reason` |
| `menu_opened` | level menu opened | none |
| `setting_changed` | sound, haptics or symbols toggled | `name`, `enabled` |
| `tutorial_completed` | first two campaign levels solved | none |
| `campaign_completed` | level 12 solved | `total_stars` |

**Level facts:** `mode` (campaign, daily, endless), `level_id`, `level_number`, `bottles`, `colors`, `capacity`, `hidden`, `par`.
**Run stats:** `attempt`, `moves`, `duration_s` (time in the background is excluded), `undos`, `restarts`, `hints`, `bottles_added`, `stuck_seen`.

Changing an event or property means editing `TopOffEvent` and bumping `schemaVersion`.

### Definitions that are easy to get wrong
- **Abandoned** means the player played (made a move, undo or restart) and then left. Opening a level and leaving without a pour is browsing and is not recorded.
- Backgrounding mid-level records a `backgrounded` abandon *marker*, because we cannot know whether the player returns. Analysis counts an attempt as abandoned only if that attempt (install, level, attempt number) is **never completed**. `AnalyticsSummary` and `Tools/analyze_events.py` both do this.
- **Stuck** is only reported when the solver searched the whole reachable space and found no solution. Running out of search budget reports nothing.
- `stuck_resolved.via` is the **first action** after the banner, not proof that it fixed the board.

## Reading the data

```bash
python3 Tools/analyze_events.py events.jsonl [more-testers.jsonl ...]
```

Prints, per level: starts, finish rate, quits, stuck count, moves relative to par, average seconds, average stars and hints. Several files are combined. The same numbers come from `AnalyticsSummary` inside the app (the Tester tools section).

What to look for after a playtest:
- **Finish rate well under 100% or many quits:** the level is too hard or unclear (this is the check on the difficulty calibration, which is measured from random play and has never been tried by people).
- **Moves/par far above 1.5 with high stuck counts:** the level is a wall, or concealed layers are unfair.
- **Hints and undos clustered on one level:** the same.
- **Boosters offered but mostly declined or cancelled:** the ad prompt is too early or too frequent.

## Decision: stay local for the first TestFlight round

Decided on 2026-10-09. Reasons: the studio docs put telemetry aggregation under "only when justified", Top Off's PRD lists a custom backend as out of scope for v1, and the exported-log route gives per-level numbers with no infrastructure.

For when that changes: the studio's common backend is the `gametime-backend` repo (a small FastAPI control plane for remote config, kill switches and support intake). As of the date above it has **no event endpoint, no database, and no deployment** (nothing on Vercel, nothing on Supabase, no hosting config or deploy step in the repo). Using it for analytics means, in order: pick a host and deploy it, give it a data store, add a validated `POST /v1/events` that enforces `TopOffEvent.allowedPropertyKeys`, then do the client steps below. Decide the host once, for the whole studio.

## Adding a remote backend (not done, deliberately)

Everything needed is in place. The remaining decisions are the backend, consent and the store privacy answer:

1. **Choose a backend** and write an `AnalyticsClient` (the protocol in `GameTimeServices`) that posts `AnalyticsEvent`s. Attach it where `AnalyticsPipeline.standard()` is built (`StandardSetup.swift`).
2. **Ask the player.** Add a "Share anonymous usage data" switch bound to `AnalyticsPipeline.setSharingEnabled`, with the default decided deliberately (EU rules and the Apple privacy label both care). Forwarding stays off until it is on.
3. **Update the privacy declarations together:** the App Store Connect App Privacy answers (usage data, identifiers) and `TopOff/PrivacyInfo.xcprivacy`, and the privacy policy.
4. **Batch and retry** uploads on the client, and make the backend's `install_id` + `seq` pair idempotent so retries cannot double-count.
