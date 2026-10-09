# Ads in Top Off

Rewarded ads only, through the shared GameTimeKit adapter (`GameTimeAdMob`) and coordinator (`MonetizationCoordinator`). Rules come from the platform docs: nothing during the teaching flow, ad trouble never blocks play, only an earned reward counts.

## How it behaves

| Situation | Result |
|---|---|
| Levels 1 and 2 not both solved (teaching flow) | Hint and extra bottle are free; no ad is offered |
| An ad is ready | Player sees "Watch Video"; the booster is granted only if the reward is earned |
| Player closes the ad early | Nothing granted |
| No ad ready (offline, no fill), consent withheld, or the 30 s rewarded cooldown | Booster is granted free; play is never blocked |
| Release build with no ad units configured | The ad SDK is not started; every booster is free |

Hint maps to `rewardedHint`; extra bottle maps to `rewardedContinue`. Each reward opportunity has a stable id (`level-<id>.<booster>-<n>`), and receipts persist in `UserDefaultsRewardReceiptStore`.

## Debug versus release

- **Debug** builds use Google's public sample ad units (`AdMobConfiguration.testing`), which are safe to tap.
- **Release** builds use `TopOffAds.productionConfiguration`, which is empty on purpose. A release can never serve test ads.

## Before shipping ads

1. Create the AdMob app and two rewarded ad units (hint, extra bottle) in the AdMob console.
2. Put the unit ids in `TopOffAds.productionConfiguration`.
3. Replace `GADApplicationIdentifier` in `TopOff/Info.plist` with the real AdMob app id (it currently holds Google's sample id).
4. Configure the consent message in AdMob (Privacy & messaging) so the consent form appears where required.
5. Add Google's recommended `SKAdNetworkItems` list to `TopOff/Info.plist`.
6. Update the App Store privacy answers: AdMob collects device identifiers and usage data for advertising.
7. Test on a real device with your device id in `testDeviceIdentifiers` before submitting.
