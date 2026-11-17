# Dove Hunt — Project Overview

A running explanation of how the Dove Hunt project is set up. Update this file as the project evolves.

_Last updated: 2026-11-16_

---

## 1. Concept

Dove Hunt is a retro, pixel-art iOS **home screen widget game** inspired by Nintendo's *Duck Hunt*, with a visual style modeled on the *Pixel Pals* widget: a mini handheld console (blue shell, black-bordered screen) showing a pixel landscape. Doves fly through the sky; tapping a dove "shoots" it. The shotgun at the bottom center fires, the dove bursts into a puff of feathers, and the score in the top-right corner goes up.

Supported widget sizes: **small, medium, large**.

---

## 2. Targets

| Target | Type | Bundle ID | Notes |
| --- | --- | --- | --- |
| `doveHunt` | iOS app | `com.ColdCodeBliss.doveHunt` | Companion app: pixel hunting scene, hamburger menu, top scores, settings. Hosts and embeds the widget. |
| `DoveHuntWidgetExtension` | Widget extension | `com.ColdCodeBliss.doveHunt.DoveHuntWidget` | The game itself. |

### Key settings

| Setting | Value |
| --- | --- |
| Deployment target | iOS 27.2 |
| Swift language version | 6.0 (both targets) |
| Display name | "Dove Hunt" (both targets) |
| App category | Arcade Games (`public.app-category.arcade-games`) |
| Widget platforms | iPhone and iPad only (`iphoneos iphonesimulator`, device family `1,2`) |
| Default actor isolation | App: `MainActor` · Widget: `nonisolated` |
| Signing | Automatic, team `86MW3ZP4BF` |

### App Group

Both targets have the App Group entitlement **`group.com.ColdCodeBliss.doveHunt`**. The game state lives in this group's `UserDefaults`, so the companion app can read the same score as the widget.

The project uses **folder-based target membership**:

| Folder | Compiled into |
| --- | --- |
| `doveHunt/` | App target |
| `DoveHuntWidget/` | Widget target |
| `Shared/` | **Both** targets (code shared by the app and the widget) |
| `Markdowns/`, `Tools/` | No target (docs and tooling only) |

---

## 3. Folder layout

```
doveHunt/
├── doveHunt/                    App target
│   ├── doveHuntApp.swift            @main app; injects HuntRecords into the environment
│   ├── ContentView.swift            Home screen: hunting scene, title, score, hamburger menu + drawer
│   ├── MenuScreens.swift            Top Scores, How to Play, Settings, About sheets
│   ├── HuntRecords.swift            @Observable app-side view of GameStore
│   ├── AppPixelArt.swift            Palette, AppArt sizes, AppSprite, 5x7 PixelText font, panel/button styles
│   └── Assets.xcassets/PixelArt/    Generated app art (do not hand-edit)
├── Shared/
│   └── GameStore.swift              Shared (App Group) game state, stats, top scores
├── DoveHuntWidget/              Widget extension target
│   ├── DoveHuntWidgetBundle.swift   @main widget bundle entry point
│   ├── DoveHuntWidget.swift         Model, wave layout, timeline provider, views
│   ├── PixelArt.swift               Art sizes (ArtSpec), Sprite catalog, PixelSprite view
│   ├── AppIntent.swift              Landscape enum + widget configuration intent
│   ├── ShootDoveIntent.swift        App Intent run when a dove is tapped
│   └── Assets.xcassets/PixelArt/    Generated pixel art (do not hand-edit)
├── Tools/
│   └── generate_pixel_art.py    Pixel art generator (source of truth for all art)
└── Markdowns/
    └── Project_Overview.md      This file
```

---

## 4. How the game works (widget architecture)

Widgets don't run a live game loop. Each state is a SwiftUI snapshot, and the system moves between snapshots. The game is built on that model:

1. **Timeline provider** (`Provider` in `DoveHuntWidget.swift`) reads `GameStore` and builds a `DoveHuntEntry` containing the score, the doves still alive, and an optional dove that was just shot (`poofDoveID`).
2. **Waves.** `WaveFactory` places doves using a **seeded RNG** (`SplitMix64`) keyed on the wave number, so a wave always has the same layout. Wave size: small = 2, medium = 3, large = 5. Placement avoids the score plate, the shotgun, and the other doves.
3. **Tapping a dove** is a `Button(intent: ShootDoveIntent(...))`. The intent calls `GameStore.registerHit`, which:
   - adds 100 points and counts the dove toward the current hunt and lifetime totals,
   - records the dove as shot and saves the hit time,
   - starts the next wave once every dove in the current wave is down (and counts a lifetime wave cleared).
4. When the intent finishes, WidgetKit **reloads the timeline** automatically. If the last hit was under 2 seconds ago, the provider returns two entries: one showing the **feather poof + firing shotgun**, then one 0.8 s later with the poof cleared.
5. **Configuration.** Long-press → Edit Widget lets you choose a landscape (`ConfigurationAppIntent.landscape`).
6. **Hunts and top scores.** A "hunt" is the score built up since the last reset. Settings → *Start New Hunt* calls `GameStore.startNewHunt()`: it archives the hunt as a `HuntRecord` (top 10 kept, highest first), zeroes the score, starts a fresh wave, and reloads all widget timelines.

### Platform limitations (by design)

| Limitation | Impact / Workaround |
| --- | --- |
| Widgets can't play audio | No gunshot sound in the widget. Sound requires the app (or a Live Activity). |
| No continuous animation | Doves don't flap or glide in real time. They appear in new spots each wave, and the poof and recoil play as entry transitions. |
| Taps go through App Intents | Each shot takes a moment to land, since the widget reloads after every tap. |
| Reload budget | Reloads triggered by intents don't count against the budget. Passive refresh is every 15 min. |

---

## 5. Pixel art pipeline

All art is **generated procedurally** by `Tools/generate_pixel_art.py` (Python 3, standard library only; no Pillow needed). The script writes native-resolution PNGs (1 PNG pixel = 1 art pixel) as single-scale image sets into:

- `DoveHuntWidget/Assets.xcassets/PixelArt/` (widget art)
- `doveHunt/Assets.xcassets/PixelArt/` (app art; the dove frames are written to both catalogs)

**Regenerate the art** (from the repo root):

```sh
python3 -I Tools/generate_pixel_art.py
```

### Rendering rules (what keeps it crisp)

- Images are drawn with `.resizable().interpolation(.none)`, i.e. nearest-neighbor scaling, so no blurring.
- The view computes one **pixel scale** (points per art pixel) from the screen size, and every sprite uses it, so everything shares one pixel grid.
- Sprite positions are whole art-pixel coordinates.
- `.widgetAccentedRenderingMode(.fullColor)` keeps the art in full color when the Home Screen is tinted.

### Screen art sizes (`ArtSpec`, must match `SCREEN_SIZES` in the script)

| Family | Art size (px) |
| --- | --- |
| Small | 64 × 64 |
| Medium | 144 × 60 |
| Large | 144 × 152 |

**Shotgun scaling.** On the large widget the shotgun is drawn at a whole-number **2×** (`ArtSpec.gunMultiplier`), so it stays in proportion to the taller screen while still landing on the pixel grid. Recoil and dove placement scale with it.

### Asset inventory

| Asset | Size (px) | Description |
| --- | --- | --- |
| `meadow_{small,medium,large}` | per family | Sunny day: dithered blue sky, clouds, rolling hills, big tree on the left, bush, grass with flowers |
| `nightWoods_{small,medium,large}` | per family | Grey and yellow night: stars, glowing crescent moon, layered pine silhouettes, dry golden field, fireflies |
| `sunsetMarsh_{small,medium,large}` | per family | Purple-to-orange sunset, striped retro sun, water with reflections, reeds and cattails |
| `dove_wings_up`, `dove_wings_down` | 16 × 14 | Dove flight frames (face right; flipped in code to face left) |
| `feather_poof` | 16 × 14 | Hit effect: puff and scattered feathers |
| `shotgun_idle`, `shotgun_fire` | 9 × 24 | Shotgun from behind; the fire frame adds a muzzle flash. Kicks down 1 px when firing. |
| `digit_0` … `digit_9` | 4 × 6 | 3×5 pixel font with a 1 px drop shadow, used for the 6-digit score |
| `app_background` (app) | 90 × 196 | Dithered deep-to-light blue sky, clouds, low hills, grass strip |
| `hunter` (app) | 38 × 48 | Vintage hunter: blaze-orange cap with ear flap, mustache, red plaid jacket, khakis, boots, shotgun angled at the sky. Auto-outlined. |

### Editing the art

- **Sprites** (dove, poof, shotgun, digits) are text grids near the bottom of the script. Each character is a palette color (`K` outline, `W` white, `G`/`S` greys, `O` beak, etc.; `.` is transparent).
- **Landscapes** are functions (`meadow`, `night_woods`, `sunset_marsh`). Each is seeded per landscape and size, so output stays the same between runs.
- To add a landscape: write a painter function, register it in `LANDSCAPES`, and add a matching `case` to the `Landscape` enum in `AppIntent.swift`. The raw value must match the asset name prefix.
- If you change a sprite's dimensions, update `Sprite.size` in `PixelArt.swift` (widget) or `AppArt` in `AppPixelArt.swift` (app).

---

## 6. Companion app

**Home screen** (`ContentView`):
- Full-screen pixel scene (`HuntingScene`): the background and hunter are scaled to fill the screen on one pixel grid. Three doves float ahead of the hunter's aim, bobbing and flapping via a `TimelineView` at 12 fps. Offsets snap to whole art pixels for retro motion.
- The animation pauses when **Reduce Motion** is on or the *Animated doves* setting is off.
- "DOVE HUNT" title, the 6-digit score, and an "ADD THE WIDGET TO HUNT!" hint while the score is 0.
- Stats refresh whenever the app becomes active, because the widget writes from its own process.

**Hamburger menu** (top-left) opens a slide-in pixel drawer:

| Item | Contents |
| --- | --- |
| Top Scores | Current hunt (score, doves), lifetime stats (doves bagged, waves cleared), top 10 archived hunts |
| How to Play | Adding the widget, choosing a landscape, shooting, banking a hunt |
| Settings | *Animated doves* toggle, *Start New Hunt* (confirmation), *Clear Top Scores* (destructive confirmation), version |
| About | Hunter art, blurb, version |

**UI kit** (`AppPixelArt.swift`):
- `PixelText` is a Canvas-drawn 5×7 bitmap font (A–Z, 0–9, common punctuation) with a drop shadow. It scales with Dynamic Type (capped at 1.5×) and exposes a VoiceOver label.
- `pixelPanel()` and `PixelButtonStyle` give square-cornered navy panels and buttons with chunky cream borders and offset ink shadows.
- Long body copy uses the system monospaced font so it stays readable and fully Dynamic Type–friendly.

---

## 7. Roadmap

- [x] Project setup: widget target, App Group, build settings
- [x] Pixel art: 3 landscapes × 3 sizes, dove frames, feather poof, shotgun idle/fire, pixel digits
- [x] Companion app: pixel home scene, hamburger menu, Top Scores, How to Play, Settings, About
- [ ] Companion app: optional full-screen play mode with sound
- [ ] Polish: console shell details (Pixel Pals–style side buttons on medium), app icon
- [ ] Gameplay: miss handling, combo/streak scoring, high score

---

## 8. Changelog

- **2026-11-16** Initial setup: added the `DoveHuntWidgetExtension` target, the App Group, Swift 6, display names, and the game skeleton (`GameStore`, `ShootDoveIntent`, timeline provider).
- **2026-11-16** Added the pixel art pipeline (`Tools/generate_pixel_art.py`) and all generated art. Wired the art into the widget on a shared pixel grid, with the pixel-font score, shotgun recoil/flash, and the feather poof transition.
- **2026-11-16** Large widget shotgun now drawn at 2× to match the taller screen. Dove placement avoids the full shotgun sprite (including the muzzle flash).
- **2026-11-16** Moved `GameStore` into `Shared/` (compiled into both targets) and added hunt/lifetime stats and top scores. Built the companion app: generated `app_background` and `hunter` art, animated home scene, hamburger drawer, and the Top Scores, How to Play, Settings and About screens.
