# Game #002 — Top Off

> **Status:** Draft. Canonical PRD for Game #002; the pointer in `gametime-ios/docs/GAME_002_TOP_OFF_PRD.md` refers here.
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
| Reward offers, requests, transactions | `GameTimeCommerce`: `RewardOffer`, `RewardRequest`, `RewardTransaction` | **Reuse as-is** | _TBD_ |
| Rewarded ad flow, serialized presentation | `MonetizationCoordinator`, `RewardedAdCoordinator` | **Reuse as-is** | _TBD_ |
| Eligibility, cooldowns, consent, remove-ads gating | `MonetizationPolicy`, `MonetizationPlacement` | **Reuse**; likely uses `rewardedHint`, `bonusReward`, `betweenLevels`; check whether an "extra container" placement needs a new case | _TBD_ |
| Idempotent reward receipts | `RewardReceiptPersisting`, `InMemoryRewardReceiptStore` | **Reuse protocol; build persistent store.** Candidate to extract (also needed by #001) | _TBD_ |
| Ad provider, entitlements, event tracking | Protocols plus no-op implementations | **Reuse protocols; write concrete adapters** (ad SDK, StoreKit). Candidate to extract | _TBD_ |
| Semantic feedback events | `GameFeedbackEvent`: `placement`, `invalidMove`, `conflict`, `hint`, `undo`, `solve`, `milestone`, `pour` | **Reuse**; `pour` added to the platform (it is a shared semantic action in `GAME_MECHANIC_TAXONOMY.md`), so no aliasing needed | _TBD_ |
| Haptics and audio controllers | Protocols and no-ops only | **Write concrete Core Haptics/AVFoundation adapters.** Strongest extraction candidate | _TBD_ |
| SpriteKit effects (staggered timing, accessible feedback) | `GameTimeExperience/SpriteKitEffects` | **Reuse** for solve/milestone celebrations; liquid and pour rendering stays local | _TBD_ |
| Clock and seeded randomness | `GameTimeCore` | **Reuse** (deterministic generator and replays) | _TBD_ |
| Build info | `GameTimeCore` | **Reuse** | _TBD_ |
| Save state with versioning, settings | Not provided | **Build locally**, compare with #001's, then extract | _TBD_ |
| Analytics events | Monetization events only | **Build locally**; align event naming with #001 | _TBD_ |
| Game Center | `GameTimeServices` is a stub | **Build locally**, compare with #001 | _TBD_ |
| Onboarding/tutorial scaffolding | Not provided | **Build locally**, compare with #001 | _TBD_ |
| Replay and diagnostics | Not provided | Seed-based replay only; full tooling is post-v1 | _TBD_ |

### How to score reuse

At the end of the build, record for each row: **reused as-is / reused with change / rebuilt / not needed**, plus approximate hours saved or spent. Then extract anything *duplicated* between #001 and #002 with stable semantics, and nothing else.

**Success bar for the platform:** most of the monetization and feedback rows reused as-is or with small additive changes, and at least three rows (persistent receipts, haptics/audio adapters, save/settings versioning) identified as real extractions.

## Milestones (proposed, adjust to the 50-day roadmap)

1. **Engine:** `TopOffEngine` plus unit tests (rules, undo, solved) in the game repo, no UI.
2. **Playable:** SpriteKit scene, one-tap interaction, tutorial level, feedback hooked to `GameFeedbackController`.
3. **Generator and solver:** seeded, solver-verified levels, difficulty curve.
4. **Monetization:** rewarded hint and extra container via `MonetizationCoordinator`, persistent receipts, remove-ads.
5. **Polish and ops:** accessibility pass, Game Center, diagnostics, TestFlight.
6. **Reuse retrospective:** fill the **Actual** column, open extraction PRs against GameTimeKit.

## Open questions

- Confirm the mechanic family against Game #001's actual mechanic, so overlap is minimal.
- App Store name and trademark check for "Top Off", and bundle ID `topoff`.
- Rewarded "extra container": a new `MonetizationPlacement` or a variant of `rewardedContinue`?
- Which ad network, and is it already integrated for #001?
- Does #001 already have a persistent receipt store, save format or tutorial scaffold that #002 should adopt or extract from first?
