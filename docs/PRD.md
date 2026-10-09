# Game #002 — Top Off

> **Status:** Feature-complete for v1 and in release preparation. The remaining work is human: a device playtest, the AdMob account, store checks and submission. See `docs/RELEASE_CHECKLIST.md`.
> **Mechanic:** Stack/container family (see `gametime-ios/docs/GAME_MECHANIC_TAXONOMY.md`). Game #001 (Exactly One) is a constraint puzzle, so there is no mechanic overlap.
> **Gate:** Per `gametime-ios/docs/DECISIONS.md`, Game #001 submission stays the priority. #002 must not displace anything #001 needs, including App Review follow-ups.

## Purpose

Top Off has two jobs:

1. Be a polished, easy-to-learn, replayable game on its own.
2. **Prove (or disprove) that GameTimeKit makes a second game materially faster to ship.** The reuse table below is how we measure that.

## Product summary

Pour matching liquid between containers until every container is full of one colour or empty. Calm, tactile, one-thumb, offline.

- **Name:** Top Off (the final satisfying pour).
- **Platform:** iOS 17+, portrait, native Swift/SpriteKit, no third-party gameplay or rendering dependency.
- **Players:** casual puzzle players who want a short, relaxing session.
- **Session:** 2–5 minutes, 3–8 levels.

## Core loop

1. Tap a container to lift its top run of liquid.
2. Tap another container to pour.
3. A pour is legal if the target is empty, or its top colour matches and it has capacity.
4. A level is solved when every container is full-and-uniform or empty.
5. Next level, with a small new idea every few levels.

First interaction must happen within seconds of launch, and the tutorial is the first level: no text walls, no modal tutorials (`ONBOARDING_AND_LEARNING.md`).

## Design principles

- **Logic independent of rendering.** A pure Swift `TopOffEngine` owns state, rules, undo, and solved-detection. SpriteKit only presents it.
- **Deterministic.** Level generation takes a seed (`SeededRandomSource`), so any level can be replayed from its seed.
- **Always solvable.** Generator builds levels by reverse-pouring from a solved state, and a solver verifies each level before shipping.
- **Never manufacture frustration.** No fake dead-ends, no pressure timers. A stuck board offers free undo/restart.
- **Reward-led monetization only.** Rewarded hint or extra container; never a paywall on normal play.
- **Accessible.** Colour-blind-safe palette plus a pattern/symbol overlay, Reduce Motion support, VoiceOver labels for containers.

## Scope

**In (v1):**
- Level progression, solver-verified levels
- Undo, restart
- Rewarded hint and rewarded extra container
- Remove-ads entitlement
- Settings: sound, haptics, colour-blind mode
- Game Center (optional identity, simple leaderboard/achievement at most)
- Offline-first local saves

**Out (v1):**
- Daily challenges and LiveOps
- Social features
- Custom backend
- Cosmetic store
- Remote config beyond data-only tuning

## Mechanic-specific code (stays local)

Per the extraction rule, nothing below is extracted into GameTimeKit until a *third* use proves it, or until two games demonstrably duplicate it.

- `TopOffEngine`: containers, top-run detection, transfer, undo, solved detection
- Level generator and solver
- SpriteKit scene, liquid rendering, pour animation
- Level data and difficulty curve

## Reuse table

Based on the current state of `Sources/` (about 780 lines; see the audit in conversation history). Update the **Actual** column during development. This table is the deliverable that answers "does the platform pay off?".

| Capability | GameTimeKit today | Plan for Top Off | Actual |
|---|---|---|---|
| Reward offers, requests, transactions | `GameTimeCommerce`: `RewardOffer`, `RewardRequest`, `RewardTransaction` | **Reuse as-is** | **Reused as-is.** `TopOffBoosterService` builds `RewardOffer`/`RewardRequest` ids per level and booster. |
| Rewarded ad flow, serialized presentation | `MonetizationCoordinator`, `RewardedAdCoordinator` | **Reuse as-is** | **Reused as-is** (`MonetizationCoordinator`). Added the missing concrete AdMob provider to the kit as `GameTimeAdMob`. |
| Eligibility, cooldowns, consent, remove-ads gating | `MonetizationPolicy`, `MonetizationPlacement` | **Reuse**; likely uses `rewardedHint`, `bonusReward`, `betweenLevels`; check whether an "extra container" placement needs a new case | **Reused as-is.** Extra bottle uses `rewardedContinue`, so no new placement. Remove Ads not built: rewarded-only, per Exactly One's decision. |
| Idempotent reward receipts | `RewardReceiptPersisting`, `InMemoryRewardReceiptStore` | **Reuse protocol; build persistent store.** Candidate to extract (also needed by #001) | **Protocol reused; persistent store built locally** (`UserDefaultsRewardReceiptStore`). Extraction candidate once Exactly One needs the same. |
| Ad provider, entitlements, event tracking | Protocols plus no-op implementations | **Reuse protocols; write concrete adapters** (ad SDK, StoreKit). Candidate to extract | **Protocols reused; AdMob adapter built and moved into GameTimeKit** (`GameTimeAdMob`, with UMP consent). Entitlements and tracking not needed in v1. |
| Semantic feedback events | `GameFeedbackEvent`: `placement`, `invalidMove`, `conflict`, `hint`, `undo`, `solve`, `milestone`, `pour` | **Reuse**; `pour` added to the platform (it is a shared semantic action in `GAME_MECHANIC_TAXONOMY.md`), so no aliasing needed | **Reused as-is.** `pour` already existed; `hint` doubles as the hidden-layer reveal cue and `milestone` as a bottle completing. |
| Haptics and audio controllers | Protocols and no-ops only | **Write concrete Core Haptics/AVFoundation adapters.** Strongest extraction candidate | **Built, then extracted into GameTimeKit** (`CoreHapticsController`, `SynthAudioController`, `HapticPattern`, `SynthSound`). Top Off keeps only its cue tables. Exactly One has a near-identical engine and has not migrated. |
| SpriteKit effects (staggered timing, accessible feedback) | `GameTimeExperience/SpriteKitEffects` | **Reuse** for solve/milestone celebrations; liquid and pour rendering stays local | **Not used.** Celebration, splash and slosh were written locally against the liquid renderer. |
| Clock and seeded randomness | `GameTimeCore` | **Reuse** (deterministic generator and replays) | **Rebuilt (small).** The engine has its own seeded generator instead of `GameTimeCore`'s; worth reconciling. |
| Build info | `GameTimeCore` | **Reuse** | **Not needed.** |
| Save state with versioning, settings | Not provided | **Build locally**, compare with #001's, then extract | **Built locally** (`TopOffProgressStore`, versioned key). Compare with Exactly One's, then extract. |
| Analytics events | Monetization events only | **Build locally**; align event naming with #001 | **Built locally, on-device only:** typed versioned events, a local store, session and level tracking, an in-app tester summary and a log analyser (`docs/ANALYTICS.md`). It forwards to the kit's `AnalyticsClient` when one is attached, but ships none. Extraction candidate once #001 needs it. |
| Game Center | `GameTimeServices` is a stub | **Build locally**, compare with #001 | **Not built.** |
| Onboarding/tutorial scaffolding | Not provided | **Build locally**, compare with #001 | **Built minimally, locally:** the first two levels teach and are ad-free, plus a first-run hint. |
| Replay and diagnostics | Not provided | Seed-based replay only; full tooling is post-v1 | **Not built.** Seeds make replay possible. |

### How to score reuse

At the end of the build, record for each row: **reused as-is / reused with change / rebuilt / not needed**, plus approximate hours saved or spent. Then extract anything *duplicated* between #001 and #002 with stable semantics, and nothing else.

**Success bar for the platform:** most of the monetization and feedback rows reused as-is or with small additive changes, and at least three rows (persistent receipts, haptics/audio adapters, save/settings versioning) identified as real extractions.

## Milestones

1. **Engine: COMPLETE.** `TopOffEngine` with rules, undo, concealed layers, a shortest-solution solver, a seeded generator and `DifficultyProbe`.
2. **Playable: COMPLETE.** SpriteKit scene with glass bottles, real pours, haptics and sound, solve celebration, level select, stars, saved progress.
3. **Generator and solver: COMPLETE.** Levels are chosen by measured playability, not solution length. The daily puzzle and Endless draw from a table of vetted seeds.
4. **Monetization: COMPLETE, ads off.** Rewarded hint and extra bottle through the shared coordinator and the new `GameTimeAdMob` adapter, with persistent receipts. Release builds ship no ad units until the AdMob account exists.
5. **Polish and ops: MOSTLY COMPLETE.** Done: VoiceOver, Reduce Motion, colour-blind symbols, stuck-board nudge, icon, launch screen, privacy manifest, store screenshots, listing draft. Not done: Game Center, analytics, diagnostics.
6. **Reuse retrospective: DONE** (the table above). Extracted so far: the AdMob adapter and the haptics and audio engines.

## Open questions

- Mechanic family is frozen as **stack / container** for Game #002; the earlier path-engine idea is superseded for #002 and remains available for a future title.
- App Store name and trademark check for "Top Off", and bundle ID `topoff`.
- ~~Rewarded "extra container": a new placement or a variant of `rewardedContinue`?~~ Resolved: it reuses `rewardedContinue`; no new placement needed.
- ~~Which ad network?~~ Resolved: Google AdMob, as decided in Exactly One's PRD. The shared adapter is `GameTimeAdMob` in GameTimeKit; Top Off consumes it through `TopOffMonetization`.
- Does #001 already have a persistent receipt store, save format or tutorial scaffold that #002 should adopt or extract from first?
