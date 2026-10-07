# Top Off — Game Time Game #002

**Public product name:** Top Off
**Studio:** Knowlly Games
**Platform:** native iOS (Swift + SpriteKit)

Pour matching liquid between containers until every container is full of one colour or empty. Game #002 on the Game Time platform, and the test of whether GameTimeKit makes a second game materially faster to ship.

This repository owns everything specific to Top Off. Shared platform code lives in [`AmrElsehemy/gametime-ios`](https://github.com/AmrElsehemy/gametime-ios) and is consumed as GameTimeKit.

## Status

- `TopOffEngine`: pure-Swift rules engine (containers, pours, undo, solved detection) with unit tests.
- First 5 handcrafted levels are committed with reference solutions and regression tests.
- iOS app target / SpriteKit scene: next milestone; the rules core is ready to embed.
- Seeded generator + solver and monetization wiring follow only after the 5-level tactile prototype is playable.

See [`docs/PRD.md`](docs/PRD.md), including the GameTimeKit reuse table.

## Build and test the engine

```bash
swift test
```

## Creating the iOS app target

The Xcode project is created on a Mac (it can't be generated reliably from a Linux session). Keep this repo and GameTimeKit as siblings, as Exactly One does:

```text
~/Work/GameTime/
├── gametime-ios/
├── gametime-nine-ios/
└── gametime-topoff-ios/
```

1. In Xcode, create an iOS App named `TopOff` (SpriteKit, Swift) in this repo.
2. Add the local packages: `../gametime-ios` (GameTimeKit) and this repo's own package (`TopOffEngine`).
3. Mirror Exactly One's CI (`gametime-nine-ios/.github/workflows/ci.yml`), which checks out GameTimeKit as a sibling, once the app target exists.

Ship against a tagged GameTimeKit release, not `master` (see `gametime-ios/docs/DEVELOPMENT.md`).

## Rules

- Game logic is independent of SpriteKit rendering.
- Deterministic: levels come from seeds, and every level is solver-verified.
- Offline-first; no proprietary login.
- Rewarded monetization only; never manufacture frustration.
- Mechanic code stays here until a second game proves a shared abstraction (`gametime-ios/docs/ARCHITECTURE.md`).
