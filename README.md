# PhotoNook

> *Your gallery, clean and cozy.*

An iOS app for cleaning up your iPhone photo library with Tinder-style gestures:
swipe left to discard, swipe right to keep.

`com.kevinknear.photonook` · iOS 17+ · SwiftUI · English and Spanish

## Features

**Start anywhere.** Picking a section opens it as a grid, not as a deck. Tap any photo — the
4,532nd if you like — and the deck starts there. Go back to the grid whenever you want, pick a
different spot, keep going. With a 12,000-photo library, forcing a linear pass from photo one
makes an app useless for exactly the people who need it most.

Decisions are tracked per photo rather than by position, so reviewing in any order, across
several sittings, keeps the counters honest. Already-decided photos are dimmed in the grid with
a heart or a trash icon.

**Card deck.** The current photo with a peek at the next one, tilt on drag, and "DELETE" / "KEEP"
stamps that fade in as you commit to a direction. Photos are shown whole rather than cropped —
you can't decide what to delete from a crop.

**Explore.** The library laid out as cover cards with counts, grouped by:

- *By type* — screenshots, videos, selfies, bursts, Live Photos, panoramas, portraits, slo-mo,
  time-lapse, GIFs, favorites. These come from the smart albums iOS maintains.
- *By app* — WhatsApp, Instagram, Telegram… detected from the album names those apps create.
- *My albums* — the ones you made yourself.
- *Recent / By year / By month* — today, this week, this month, each year, and the last 12 months.

**The "To delete" tray.** Everything you swipe left lands in a staging grid instead of being
deleted immediately. Each photo has three exits:

- **Tap** to unmark it → it counts as kept (decision made).
- **Press and hold → Send back to the deck** → returns to the end of the carousel with no decision
  recorded. For when you're unsure and want to see it again later.
- Leave it marked → it goes with the batch.

Deleting the batch takes **a single iOS confirmation** for the whole thing.

**Counters.** Live progress ("X of Y"), kept, discarded, and space recovered in MB/GB.

**Undo** the last swipe.

**Three deletion modes** (Settings tab):

- `End of session` (default) — nothing is deleted until you review the tray.
- `In batches` — fires automatically every N discards (adjustable, 5–100).
- `Every swipe` — deletes immediately, with one system alert per photo.

**Cozy design.** Warm paper palette in light and dark mode, rounded typography, Dynamic Type
support, and VoiceOver labels on the icon-only controls.

> Nothing is deleted permanently. Everything goes to **Recently Deleted** in the Photos app,
> where iOS keeps it for 30 days.

### About the iOS confirmation alert

Every call to `PHAssetChangeRequest.deleteAssets` triggers a system alert ("Allow PhotoNook to
delete this photo?"). **It cannot be suppressed** — there is no parameter, entitlement, or
permission level that disables it, and it has nothing to do with granting full library access.
It is a deliberate iOS protection so no app can empty your gallery without you intervening.

The only available lever is to make fewer calls by grouping photos into a single `deleteAssets`,
which is exactly what the batch modes do. That constraint is the reason the tray exists.

## Project structure

```
Config/
  Shared.xcconfig            committed; optionally includes Local.xcconfig
  Local.xcconfig             gitignored; your DEVELOPMENT_TEAM

Sources/
  PhotoNookApp.swift         entry point, system bar appearance
  Theme.swift                palette, metrics, typography, Dynamic Type mapping
  Models/
    FilterOptions.swift      photo sources, date ranges, sort order, catalog types
  Services/
    PhotoLibraryService.swift  the only place that touches the Photos framework
  ViewModels/
    SwipeViewModel.swift     session state, undo, counters, deletion
  Views/
    RootView.swift           tabs, permissions, empty state, summary
    ExploreView.swift        section catalog with cover thumbnails
    GalleryGridView.swift    the section as a grid; pick where to start
    SwipeDeckView.swift      the deck, drag gesture, action bar, haptics
    PhotoCardView.swift      a single card (photo + metadata)
    TrashTrayView.swift      staging grid and batch deletion
    StatsBar.swift           progress and space recovered
    FilterView.swift         settings: date, order, appearance, deletion mode

Scripts/
  make-icon.sh               renders an alternative icon (writes icon-generado.png)
  make-landscapes.sh         synthetic landscapes with spread EXIF dates
  reset-demo.sh              numbered test images for the simulator
  stress-library.sh          thousands of small photos to test at scale
```

The architecture is MVVM: views hold no data logic, the view model owns session state, and a
single service encapsulates every `PHAsset` call.

## Getting started

```bash
open PhotoNook.xcodeproj
```

The project is fully configured: iOS 17.0 deployment target, `NSPhotoLibraryUsageDescription`
in `Sources/Info.plist`, asset catalog with the app icon, privacy manifest, and string catalogs.

### On the simulator

1. Pick any iPhone simulator from the destination selector at the top of Xcode.
2. Press ▶︎ (`⌘R`).
3. The simulator starts with an almost empty gallery. Generate test photos:

   ```bash
   chmod +x Scripts/reset-demo.sh
   ./Scripts/reset-demo.sh 60
   ```

   This renders 60 numbered images in mixed formats (screenshot-tall, landscape, square) and
   loads them into Photos with `simctl addmedia`. The numbering lets you verify exactly which
   photos were deleted and which were kept. Add `--erase` to wipe the simulator first.

   You can also just drag images from Finder onto the simulator window.

4. Accept the photo permission dialog.

Deletion works on the simulator, confirmation alert included, so you can validate the whole flow
before touching a real library. If you run out of photos, they're recoverable: Photos →
Albums → Recently Deleted → Select → Recover All.

> `simctl addmedia` does not tag images with the `photoScreenshot` subtype, so the Screenshots
> section won't find them. To test that one, take real screenshots inside the simulator with `⌘S`.

### On a physical device

1. Create `Config/Local.xcconfig` with your Team ID (see below).
2. Connect your iPhone and enable Settings → Privacy & Security → **Developer Mode**, then restart.
3. Select your device in Xcode and press ▶︎.
4. The first launch will be blocked. Go to Settings → General → VPN & Device Management → your
   certificate → **Trust**, then run again.

With a free Apple ID the app expires after 7 days; re-run from Xcode to renew it.

### Code signing

`DEVELOPMENT_TEAM` is deliberately **not** in the `.xcodeproj`. It lives in
`Config/Local.xcconfig`, which is gitignored and never reaches the repository.

Create that file with your own Team ID:

```
DEVELOPMENT_TEAM = XXXXXXXXXX
```

Find it in Xcode → Settings → Accounts → your Apple ID (in parentheses), or at
developer.apple.com → Membership.

Without that file the project still builds for the **simulator** — it's only needed to sign for a
device or to archive. `Config/Shared.xcconfig` pulls it in with `#include?`, an optional include
that doesn't fail when the file is missing.

> **Watch out:** if you change the team from Xcode → Signing & Capabilities, Xcode writes
> `DEVELOPMENT_TEAM` back into the `.xcodeproj`. If you see it there, remove it and put it in
> `Local.xcconfig` instead, or it ends up committed. A `git diff` before each commit catches it.

### If Xcode complains

- *"Signing for PhotoNook requires a development team"* → only when building for a device.
  Create `Config/Local.xcconfig`.
- *"Cannot find 'X' in scope"* → a file isn't in the target. Select it and check
  *Target Membership* in the inspector.
- Concurrency (`Sendable`) errors → confirm **Swift Language Version** is **5**, not 6, in the
  target's build settings.

## Localization

English (source) and Spanish, via String Catalogs. iOS picks based on the device language.

- `Sources/Localizable.xcstrings` — the interface. English is the source language: keys are the
  English text itself, Spanish is stored as a translation.
- `Sources/InfoPlist.xcstrings` — the display name and the Photos permission prompt.

To add a language, open the catalog in Xcode and press `+` next to the language list. Xcode
extracts keys from the code on every build.

Two rules when editing code:

- `Text("literal")` localizes automatically. `Text(variable)` does **not** — build that variable
  with `String(localized: "…")`.
- Inside a ternary in `Text`/`Button`, wrap each branch in `String(localized:)`. With two bare
  literals, Swift may pick the non-localizing overload.

## Accessibility

- **Dynamic Type.** `Font.cozy(_:_:)` maps point sizes onto the system's semantic text styles, so
  everything scales with the user's text size setting. `Font.fixed(_:_:)` is the deliberate
  opt-out, used only for glyphs and badges living inside fixed-size frames. Capped at
  `.accessibility2`, above which the deck and grid stop fitting on screen.
- **VoiceOver.** The icon-only deck controls carry explicit accessibility labels.

## Shipping to the App Store

Requires the Apple Developer Program ($99/year). Already prepared in this repo:

- **App icon** — `Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (1024×1024, no alpha).
  `Scripts/make-icon.sh` renders a purely programmatic alternative into `icon-generado.png`
  (it deliberately does not overwrite the one in use); the palette lives in the `color(0x…)`
  calls inside the script.
- **Privacy manifest** — `Sources/PrivacyInfo.xcprivacy`, in the resources build phase. Declares
  `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, required because `@AppStorage`
  uses `UserDefaults`, which is on Apple's Required Reason API list.
- **Export compliance** — `ITSAppUsesNonExemptEncryption` is set to `false` in `Info.plist`, so
  uploads skip the encryption questionnaire.
- **Privacy policy** — `PRIVACY-EN.md` and `PRIVACY.md`. Both need to be published at public URLs
  and referenced in App Store Connect.
- **Store copy** — `STORE.md` has the name, subtitle, description, keywords, and promotional text
  in both languages, within Apple's character limits.

Still to do outside the repo: register the Bundle ID, create the App Store Connect record, upload
2–8 screenshots per device size taken from real screens, fill in App Privacy Labels as
*Data Not Collected*, and Archive → Distribute App from Xcode.

Since April 28, 2026, builds must use the iOS 26 SDK or later, which means Xcode 26 or later.

## Technical notes

- **Swift 6 strict concurrency.** `PHAsset` is not `Sendable`, so fetching runs on the `MainActor`.
  File size computation — the genuinely slow part — crosses to a background task passing only
  `localIdentifier` strings, then merges results back on the main actor.
- **File size** comes from `PHAssetResource.value(forKey: "fileSize")`. It's the common approach
  and widely accepted on the App Store, but it isn't public API and it's slow, so sizes are
  computed in the background and appear progressively.
- **`PHCachingImageManager`** prefetches the next 6 photos so the deck doesn't flicker.
- **Requeued photos are appended** to the end of the asset array rather than moved back to their
  original index. The deck advances by index and the undo history stores indices, so reordering
  would invalidate both. Appending is harmless — the original position is already behind you.

## Ideas for v2

- "Move to album" mode: swipe up to file a photo instead of deleting it.
- Duplicate and near-duplicate detection via perceptual hashing.
- Resumable sessions by persisting the `localIdentifier`s already reviewed.
- Support for `.limited` photo access, which currently works but reports confusing counts.

## License

All rights reserved.
