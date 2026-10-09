# Top Off: release checklist

Status when this was written: the app is feature-complete for v1, builds in Release for iPhone and iPad (iOS 17+), and all engine tests pass. What is left needs a person, an Apple or Google account, or a real device.

## 1. Playtest on a real iPhone (about 30 minutes)

Nothing below can be judged from a simulator or from code.

- [ ] Play levels 1 to 12 in order. Note any level that feels too easy, too hard, or unfair. Levels 7, 9, 11 and 12 are the tense ones.
- [ ] Pour feel: does the timing, tilt and stream feel good? Does the sound match the pour?
- [ ] Haptics: pour, select, invalid move, bottle complete, solve.
- [ ] Hidden layers (levels 5, 8, 9, 10, 11): is the "?" idea clear without explanation?
- [ ] Stuck banner: reach a dead end (level 12 is easiest), confirm the banner appears and Undo/Restart work.
- [ ] Daily puzzle and Endless: play one of each; check the streak and the result badge.
- [ ] Kill the app mid-level and relaunch: progress resumes at your first unsolved level (a half-played level restarts, by design).
- [ ] VoiceOver on: can you play a level by ear? Bottle labels read from the top down, concealed layers say "unknown", pours are announced.
- [ ] Reduce Motion on: no bottle travel, no confetti, no shake.
- [ ] Settings: sound, haptics and colour symbols switches take effect immediately and persist.
- [ ] iPad: portrait only, full screen. Play one level.
- [ ] Dark mode only by design; check the launch screen colour matches.

## 2. Accounts and store setup

- [ ] **Name and trademark:** check that "Top Off" is available as an App Store name and is not someone's trademark.
- [ ] **Bundle ID:** `ai.knowlly.topoff` registered under team `4XD74F27J2`, and an app record created in App Store Connect.
- [ ] **URLs:** a support URL and a privacy policy URL (both required, neither exists yet).
- [ ] **Age rating questionnaire:** expected 4+.
- [ ] **App Privacy:** while no ads ship, "Data Not Collected" is accurate and matches `TopOff/PrivacyInfo.xcprivacy`. Revisit when ads are enabled (see `docs/ADS.md`).
- [ ] **Metadata:** copy from `Marketing/AppStore/LISTING.md` (name, subtitle, promo text, description, keywords, review notes).
- [ ] **Screenshots:** `Marketing/AppStore/6.9in/` (iPhone 6.9") and `Marketing/AppStore/iPad-13in/` (iPad 13"), five each. App Store Connect scales these down for smaller sizes.

## 3. Build and upload

Version is 1.0.0, build 1. Increment the build number for every upload.

1. In Xcode choose "Any iOS Device (arm64)" and Product, Archive. Signing is automatic with team `4XD74F27J2`.
2. Distribute App, App Store Connect, Upload.
3. Wait for processing, then add the build to a TestFlight group and install it. Repeat section 1 on that build.
4. Submit for review with the notes from `LISTING.md`.

## 4. Ads (after launch, or before if wanted)

Release builds ship **no ad units**: the ad SDK does not start and hints and the extra bottle are free. To turn ads on, follow the seven steps in `docs/ADS.md` (AdMob app and two rewarded units, unit ids in `TopOffAds.productionConfiguration`, real `GADApplicationIdentifier`, consent message, SKAdNetwork list, privacy answers and manifest, device test). Tap through the rewarded video once on a device to confirm the booster is granted: that step has never been exercised.

## Known limitations (decisions, not bugs)

- **No mid-level save.** Quitting mid-level restarts that level. Levels are short; revisit after playtesting.
- **Progress is local only.** No iCloud sync; a new phone starts fresh.
- **English only.**
- **Fixed text sizes.** HUD and menu text does not scale with Dynamic Type. VoiceOver, Reduce Motion and colour symbols are supported.
- **Endless repeats after 364 boards;** the daily puzzle repeats yearly.
- **Level difficulty is measured, not playtested.** `DifficultyProbe` says how easy a board is to win by luck and how often it dead-ends. It cannot say whether a level is fun.
- **Not built:** Game Center, analytics, diagnostics.
- **iPad** is portrait, full screen, with phone-style layout scaled up.

## Verification commands

```bash
swift test    # engine, solver, levels, daily and endless seeds (about 1 minute; slower on a busy machine)
xcodebuild -project TopOff.xcodeproj -scheme TopOff -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Debug builds only (never in Release): `TOPOFF_LEVEL=n`, `TOPOFF_AUTOPLAY`, `TOPOFF_AUTOPLAY_ALL`, `TOPOFF_RANDOMPLAY`, `TOPOFF_MENU`, `TOPOFF_DAILY`, `TOPOFF_ENDLESS=n`, `TOPOFF_DEMO_PROGRESS`, `TOPOFF_SKIP_ONBOARDING`, `TOPOFF_UNLOCK_ALL` set through `SIMCTL_CHILD_` on `xcrun simctl launch`.
