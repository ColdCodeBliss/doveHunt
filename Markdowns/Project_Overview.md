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
│   ├── GameStore.swift              Shared (App Group) game state, stats, top scores
│   └── ShootDoveIntent.swift        ShootDoveIntent + MissShotIntent (background-only)
├── DoveHuntWidget/              Widget extension target
│   ├── DoveHuntWidgetBundle.swift   @main widget bundle entry point
│   ├── DoveHuntWidget.swift         Model, wave layout, timeline provider, views
│   ├── PixelArt.swift               Art sizes (ArtSpec), Sprite catalog, PixelSprite view
│   ├── AppIntent.swift              Landscape enum + widget configuration intent
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
2. **Waves.** `WaveFactory` generates each dove's flight path using a **seeded RNG** (`SplitMix64`) keyed on the wave number, so a wave always flies the same way. Wave size: small = 2, medium = 3, large = 5. Doves fly behind the score plate and the shotgun, which ignore taps.
3. **Tapping a dove** is a `Button(intent: ShootDoveIntent(...))`. The intent calls `GameStore.registerHit`, which:
   - adds 100 points and counts the dove toward the current hunt and lifetime totals,
   - records the dove as shot and saves the hit time,
   - starts the next wave once every dove in the current wave is down (and counts a lifetime wave cleared).
4. When the intent finishes, WidgetKit **reloads the timeline** automatically. If the last hit was under 2 seconds ago, the provider returns two entries: one showing the **feather poof + firing shotgun**, then one 0.8 s later with the poof cleared.
5. **Configuration.** Long-press → Edit Widget lets you choose a landscape (`ConfigurationAppIntent.landscape`) and a difficulty (`ConfigurationAppIntent.difficulty`: Easy, Normal, or Hard).
6. **Hunts and top scores.** A "hunt" is the score built up since the last reset. Settings → *Start New Hunt* calls `GameStore.startNewHunt()`: it archives the hunt as a `HuntRecord` (top 10 kept, highest first), zeroes the score, starts a fresh wave, and reloads all widget timelines.

### Dove flight (`Flight` + `Dove.position(atTick:)`)

Widgets can't run a live game loop, so the doves' movement is **simulated with precomputed flight frames**:

- **Flight paths.** Each dove flies its own Lissajous loop (a figure-eight-style sweep) inside the sky band. `WaveFactory` gives every dove a random center, an amplitude that covers 55–100% of the sky's width, per-axis speeds, and a phase. All of it is seeded by the wave number, so a wave always flies the same way.
- **Speed.** Base sweep speeds are `Flight.horizontalSpeed` (0.09–0.16 rad/frame) and `Flight.verticalSpeed` (0.12–0.24 rad/frame). At Normal, a dove takes roughly 10–17 s to cross the sky and back.
- **Frames.** After every refresh, the timeline gets `Flight.duration` (30 s) of frames, one every `Flight.frameInterval` (1.5 s). After a shot it gets `ShotTiming.postShotFlight` (8 s), then reloads at the end for the full run. Each frame snaps the dove to a whole-pixel position on its path and alternates its wings. Then the flock rests on the last frame until the next tap or refresh.
- **Flight clock (`FlightClock`).** This maps time to the frame actually on screen. It pauses while the flock rests, and each new timeline continues from the frame showing at reload time, so doves never jump. It's stored per widget size in the extension's own `UserDefaults`.
- **Spacing.** Doves in a wave get evenly spaced phases (plus jitter), so a new wave starts spread out.
- **Flying through shots.** `FlightClock.continuing(_:at:shotTick:frames:)` keeps the **existing frame schedule** when a reload happens mid-flight. The new timeline starts on the frame that's showing, and the next frame lands when it was already due. Restarting the clock at reload time repeated the current frame for a full interval on every tap, which froze the flock during rapid shooting. If the saved clock and the tapped frame disagree by more than one frame, the tapped frame wins.
- **Smooth gliding.** Position changes animate with `.linear(duration: frameInterval)`, so doves glide continuously between frames. Wing beats and turns snap instantly (`contentTransition(.identity)`, `animation(nil)`). Doves face the direction they're flying.
- **Difficulty.** Speed = the widget's *Difficulty* setting (Easy 0.6×, Normal 1×, Hard 1.5×) × a ramp of +4% per wave cleared this hunt, capped at +80% after 20 waves. `GameStore.huntStartWave` marks where the current hunt began.
- **Hit accuracy.** A shot is mapped to the frame the *previous* timeline was showing at that moment (`previous.tick(at: shot.date)`), so the poof is drawn exactly on the dove, even a resting one. This was verified on the simulator: poofs landed 0–4 pt from the tapped dove. Each dove's tap target is padded by 4 art pixels, because a gliding dove's hit area can lead its drawn position by part of a frame.
- **Budget.** These frames are entries inside one timeline, not extra reloads. iOS may still throttle very frequent entries, especially when the widget isn't visible, so tune `frameInterval` and `duration` on a device.

### Shot feedback timing (`ShotTiming`)

Shot feedback is tuned for rapid taps:

| Element | Behavior |
| --- | --- |
| Shot dove | Disappears instantly (`removal: .identity`), and the poof appears on the same frame |
| Feather poof | Appears instantly, stays for `flashDuration` (0.25 s), then bursts outward and fades in `poofBurst` (0.15 s) |
| Shotgun | Flash and recoil snap on and off with no crossfade (`contentTransition(.identity)`, `animation(nil)`) |
| Score digits | Tick over instantly, arcade style |
| New wave | Doves fade in over `waveFadeIn` (0.15 s) |

The flash window is measured from the moment of the shot (`flashDuration`, 0.5 s), but always lasts at least `minimumOnScreen` (0.7 s) past the reload that shows it. The tap → intent → reload → render round trip takes a few hundred milliseconds, so an entry that's already stale at render time gets skipped. That was why the poof was invisible before. A shot counts as fresh within `freshShotWindow` (1.5 s), and a quick second shot simply replaces the first flash.

### Aiming shotgun (`GunAim`)

- **Three poses:** `left`, `front`, `right`. The angled sprites (`shotgun_left_*`, `shotgun_right_*`, 21×24) are the upright sprite **sheared** about 27° by the generator (`shotgun_aimed`), pivoting on the stock. `Sprite.stockOffset` aligns them so the stock never moves.
- **Aim rule:** `GunAim.toward(target)` measures the angle from the gun's grip to the target. Shots within `GunAim.frontTolerance` (18°) of straight up stay front; wider shots lean that way.
- **Target:** for a hit, the dove's position at the tapped frame. For a miss, the center of the tapped cell in the screen's invisible **3×2 miss grid**. Taps on the console shell have no target and stay front.
- **Sequence:** aimed and firing, then aimed without the flash, then back to front after `ShotTiming.aimHold` (2.5 s from the reload).
- **Exact frame:** every button carries the flight frame it was drawn in (`tick` on both intents, stored as `GameStore.lastShot.tick`). The poof and the next flight segment use exactly what was on screen.

### Performance and redraw cadence (measured on the iPhone 18 Pro simulator)

- **Render time:** WidgetKit renders **every timeline entry** before delivering a timeline, so cost per entry matters. A 36-cell miss grid × 61 entries made each reload take 2–4.6 s, and every shot effect was stale before it arrived. Now the grid is 3×2 and post-shot timelines carry only `ShotTiming.postShotFlight` (8 s). Reloads take about 0.1–0.3 s.
- **Redraw rate:** the Home Screen redrew the widget only about **every 1.4–1.8 s**, however close together the entries are. `Flight.frameInterval` is therefore 1.5 s, and speeds are defined per second (`Flight.horizontalSpeed` and `verticalSpeed` × `frameInterval`).
- **Flash length:** the muzzle flash stays on screen until the next redraw, so about 1–2 s in practice. This is a host limit, not a code setting.
- **Glide animation:** doves are drawn in a **non-interactive sprite layer** that glides with `.linear(duration: frameInterval)`. A separate layer of invisible **tap targets** sits underneath, each spanning the dove's previous → current frame positions, so shots land mid-glide. This separation is needed because interactive buttons don't animate their position. On the simulator the Home Screen logs `Ignored view update … (foreground: false)` and only shows snapshots about every 1.8–2 s, so the glide can't be seen there. **Verify on a physical device.**

### Console color (`ConsoleColor`)

- **Where to change it:** touch and hold the widget → **Edit Widget** → **Console Color**. It's stored on `ConfigurationAppIntent.consoleColor` and defaults to **NES**, which is listed first.
- **Solid colors:** Classic Blue, Cherry Red, Lime Green, Grape Purple, Sunny Yellow, Bubblegum Pink, Tangerine, Teal Wave, Charcoal, and Arctic White. These are drawn as the widget's `containerBackground`.
- **NES:** the original console colorway.
  - **Background (`NESShell`):** light grey lid on top, dark grey front below with a seam between them, and a wide black strip on the right that shows above and below the screen.
  - **Details (`NESDecorations`):** drawn in the widget content so they line up with the real border sizes, and set to ignore taps.
  - **Lid lettering:** red, slanted "ENTERTAINMENT SYSTEM" in an expanded italic system font with an extra shear, inset from the top-left corner. It shrinks to fit the small widget.
  - **Front panel:** a red power light, then POWER and RESET keys set into dark recessed slots, with dark red labels.
- **Tinted Home Screen:** the system replaces widget backgrounds with its own tint, so the chosen color doesn't show in that mode.

### No accidental app launches (`MissShotIntent`)

- A transparent full-widget `Button(intent: MissShotIntent())` sits behind the screen, so any tap that misses a dove (sky, ground, or the blue console shell) fires the shotgun instead of opening the app.
- `.contentMarginsDisabled()` lets the button reach the widget's edges. The view applies `widgetContentMargins` itself.
- Decorative layers (landscape, poof, border, score, shotgun) use `allowsHitTesting(false)`.
- `GameStore.registerMiss()` records the shot (`lastShotDate`) without a hit, so the flash plays with no poof.
- Both shot intents live in `Shared/`, compiled into the app **and** the widget as Apple recommends for interactive widgets, and declare `supportedModes = .background` so a shot never brings the app forward.
- **Simulator result (2026-11-18):** rapid taps (0.5 s apart), multi-finger taps, taps during reloads, and taps on the sky, ground, shell and doves never opened the app, with no intent errors. The widget's extreme outer corners register no action.
- Verified on the simulator: taps on empty sky and on the shell kept the Home Screen in front.

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
| `AppIcon` (app) | 32 × 32 → 1024 | Dove in a scope reticle over a pixel sky. Upscaled exactly 32× with nearest-neighbor. Light (blue day sky, red reticle), dark (night sky, yellow reticle), and tinted (grayscale on black) variants are written straight into `AppIcon.appiconset`. |
| `hunter` (app) | 38 × 48 | Vintage hunter: blaze-orange cap with ear flap, mustache, red plaid jacket, khakis, boots, shotgun angled at the sky. Auto-outlined. |

### Editing the art

- **Sprites** (dove, poof, shotgun, digits) are text grids near the bottom of the script. Each character is a palette color (`K` outline, `W` white, `G`/`S` greys, `O` beak, etc.; `.` is transparent).
- **Landscapes** are functions (`meadow`, `night_woods`, `sunset_marsh`). Each is seeded per landscape and size, so output stays the same between runs.
- To add a landscape: write a painter function, register it in `LANDSCAPES`, and add a matching `case` to the `Landscape` enum in `AppIntent.swift`. The raw value must match the asset name prefix.
- If you change a sprite's dimensions, update `Sprite.size` in `PixelArt.swift` (widget) or `AppArt` in `AppPixelArt.swift` (app).

---

## 6. Companion app

**Home screen** (`ContentView`):
- **Adapts to every screen shape.** `AppArt.background(for:)` picks whichever of four background widths (`app_background_90/140/280/420`, all 196 px tall with the same ground line) is closest to the screen's aspect ratio. The art fills the screen **anchored to the bottom**, so any cropping removes sky, never the grass or the hunter. The hunter stands at the left edge of the *visible* area, and doves are placed by visible-width fraction and height above the grass, clamped below the header. Verified in previews on iPhone portrait and landscape, iPad, and iPhone Duo (outer display, and inner display open).
- Full-screen pixel scene (`HuntingScene`): the background and hunter are scaled to fill the screen on one pixel grid. Three doves float ahead of the hunter's aim, bobbing and flapping via a `TimelineView` at 12 fps. Offsets snap to whole art pixels for retro motion.
- The animation pauses when **Reduce Motion** is on or the *Animated doves* setting is off.
- "DOVE HUNT" title, the 6-digit score, and an "ADD THE WIDGET TO HUNT!" hint while the score is 0.
- Stats refresh whenever the app becomes active, because the widget writes from its own process.

### The Hunter's Quest (side-scroller)

The home screen is the start of a side-scrolling RPG, built in `Adventure.swift` (model and scene data) and `AdventureView.swift` (rendering). There are no on-screen controls: you just tap.

| Scene | What happens |
|---|---|
| 1. Meadow (home screen) | Title, score, hunter, and **3 doves**. Tap a dove to shoot it: muzzle flash, feather poof, haptic. Tapping the sky fires the gun. |
| 2. Meadow with a tree and bushes | **4 doves** |
| 3. Log cabin | A floating dialog: "Enter the cabin? I'm sure they won't mind a total stranger barging in." plus a blinking **> TAP TO ENTER**. Tapping walks the hunter to the door, the door opens, he steps inside, and the screen fades to black. |
| Cabin interior (cut-scene) | The interior plays out (see below). Afterward the hunter is back outside at the cabin door with **a dove perched on the chimney**. Shooting it sends him walking past the cabin. |
| 4. Meadow past the cabin | Tree and bushes. Placeholder for the next scenes: it fades to **TO BE CONTINUED…** (tap to return to the start). |

- **Cabin interior cut-scene** (`InteriorView.swift`; steps are `InteriorStep`, timings are `AdventureGame.InteriorTiming`):
  1. **Arriving:** fade in. The hunter steps in from the front door (wooden footsteps). Anna, in raggedy blue overalls with patches, a white apron, and a bonnet, faces away, then turns toward him.
  2. **Speaking:** an "ANNA:" speech box with a stepped tail. Tap for her second line, then tap again. Her lines are in `AdventureGame.annaLines`.
  3. **Anna leaving:** she walks to the kitchen's back door. It opens, she slips out, and it closes.
  4. **Puzzled:** the hunter looks left, then right, and a "?" bubble appears over his head.
  5. **Leaving:** he walks back out the front door and the screen fades to black. Back outside it fades in, with the hunter at the cabin door and the chimney dove waiting.
- **Room layout.** The room (`interior_door_closed` / `interior_door_open`, 240×130 px) has plank walls, floorboards, a box TV with rabbit ears on a stand, a couch, a painting, a window with gingham curtains, a table with two chairs, a white fridge, a kitchen island, and the back door.
  - **Fit:** it's drawn as a stage, fit to the screen without cropping. On tall screens the dialog sits in the black space above the room.
  - **TV:** the screen is drawn live (`TVStatic`), flipping between random color scenes (bars, snow, checks, bands) every 0.8 s, with scanlines.
- **Flow.** When every dove in a scene is down, the title fades (a **BAGGED n** counter replaces it) and the hunter walks to the next scene.
- **World.** The world is a strip of screen-wide scenes laid end to end over the background, which **tiles seamlessly** because the hills use whole-number wave counts across the width. Everything is in art pixels, snapped to the grid.
- **Walking.** The hunter walks one scene at a steady pace (`walkDuration` 3.6 s, 4-frame walk cycle at 8 fps). The camera lets him stride toward the middle (`hunterX − 0.3·W·sin(πp)`), then catches up so he arrives at the left of the next scene.
- **Timing.** Walking, scrolling, and fades are computed from the phase's start date each frame inside a `TimelineView`. Phase changes (arrive, cabin, inside) are scheduled tasks, guarded by a generation counter so a restart cancels pending ones.
- **Data-driven scenes.** `AdventureScenes.all` lists each scene's doves (as fractions of the screen width and heights above the grass) and props (`tree`, `bush`, `cabin`). New scenes are added there.
- **Adapts to every screen.** Doves stay inside the screen edges, the cabin always fits fully on screen, and the dialog box wraps to the screen width.
- **Art.** New generated sprites: `hunter_walk_a` / `hunter_walk_b`, `feather_poof`, `muzzle_flash`, `prop_tree`, `prop_bush`, `cabin_closed` / `cabin_open`.
- **Separate records.** **The Hunter's Quest** is the companion app's game. Its score (100 per dove), BAGGED count, and records are completely separate from the widget game.
  - **Storage:** `QuestStore` (app-only `UserDefaults.standard`) holds lifetime doves, cabin visits, and best score. The widget's numbers stay in the shared App Group `GameStore`.
  - **Home screen:** shows "THE HUNTER'S QUEST" and the quest's **BEST** score.
  - **HUD:** shows this run's **SCORE** and **BAGGED**.
  - **Top Scores:** has separate **THE HUNTER'S QUEST** and **WIDGET HUNT** sections.
- **Sound effects** (`SoundEffects.swift`, generated by `Tools/generate_sounds.py`, files in `doveHunt/Sounds/`):
  - **Sounds:** gunshot (noise crack plus falling boom, light bit-crush), dove squawk (falling, vibrato square tone), grassy footsteps (3 variants), and wooden footsteps (3 variants, for the cabin interior).
  - **Footsteps** play on each stride frame of the walk cycle. Each scene's `surface` (`.grass` / `.wood`) picks the sound.
  - **Playback:** an `.ambient` audio session (mixes with music, respects the silent switch) and a pool of 3 voices per sound so shots can overlap.
  - **Settings:** toggle with **Sound effects** (`AppSettings.soundEffectsKey`).
  - **Regenerate:** `python3 -I Tools/generate_sounds.py`.
- **Simulator result (2026-11-20, iPhone 18 Pro):** the full flow worked: shooting, both walks, scene 2, the cabin prompt, entering, the end screen, and restarting.

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
- [x] Pixel app icon (light, dark, tinted)
- [ ] Polish: console shell details (Pixel Pals–style side buttons on medium)
- [ ] Gameplay: miss handling, combo/streak scoring, high score

---

## 8. Changelog

- **2026-11-16** Initial setup: added the `DoveHuntWidgetExtension` target, the App Group, Swift 6, display names, and the game skeleton (`GameStore`, `ShootDoveIntent`, timeline provider).
- **2026-11-16** Added the pixel art pipeline (`Tools/generate_pixel_art.py`) and all generated art. Wired the art into the widget on a shared pixel grid, with the pixel-font score, shotgun recoil/flash, and the feather poof transition.
- **2026-11-16** Large widget shotgun now drawn at 2× to match the taller screen. Dove placement avoids the full shotgun sprite (including the muzzle flash).
- **2026-11-16** Moved `GameStore` into `Shared/` (compiled into both targets) and added hunt/lifetime stats and top scores. Built the companion app: generated `app_background` and `hunter` art, animated home scene, hamburger drawer, and the Top Scores, How to Play, Settings and About screens.
- **2026-11-16** Added the generated pixel app icon (light, dark, and tinted). Tightened shot feedback for rapid taps: the flash now clears in 0.25 s (was 0.8 s), the shotgun, score, and dove removal are instant, and the poof bursts and fades in 0.15 s.
- **2026-11-16** Added the widget dove flight animation: wing flaps every 0.5 s with pixel-snapped bobbing and gliding for 30 s after each refresh or shot. The poof now lands at the dove's exact in-flight position.
- **2026-11-16** Doves now fly real paths around the sky (Lissajous loops, smooth linear gliding between 0.5 s frames, facing the direction of travel). Added a widget *Difficulty* setting (Easy, Normal, Hard) and a per-wave speed ramp within each hunt. Tap targets are padded for moving doves.
- **2026-11-16** Slowed dove flight about 2×. Taps that miss a dove now fire the shotgun (`MissShotIntent`) instead of opening the app. Fixed the invisible poof: the flash is anchored to the shot time with a minimum on-screen time. Added `FlightClock`, so the poof lands on resting doves and doves no longer jump after a shot. Waves now start spread out. Verified on the iPhone 18 Pro simulator.
- **2026-11-18** Added the aiming shotgun: sheared left and right sprites, aim by angle with an 18° front tolerance, and a 3×2 miss grid so misses aim too. Buttons now carry their drawn frame, so the poof is pixel-exact. Fixed slow reloads (a 36-cell grid × 61 entries took 2–4.6 s; now about 0.1–0.3 s) with a coarse grid and short post-shot timelines. Matched flight frames to the measured Home Screen redraw rate (1.5 s). Verified on the simulator.
- **2026-11-18** Moved the shot intents to `Shared/` (both targets) with `supportedModes = .background` so taps never open the app. Split doves into a gliding sprite layer and a stationary tap-target layer that covers each frame's path; hits on moving doves were verified. Rapid taps were verified not to open the app on the simulator. The glide still appears as steps on the simulator because of the Home Screen's snapshot cadence; it needs a device check.
- **2026-11-18** Fixed doves freezing while the player shoots: reloads now continue the flight frame schedule instead of restarting it. Verified on the simulator: 20 taps over 10 s and the doves kept moving at the normal ~1.5 s cadence throughout, hits still landed, and the app never opened.

- **2026-11-19** Added the **Console Color** widget setting (10 solid colors) and an **NES** colorway with lid lettering, POWER and RESET keys, a power light, and the black strip.
- **2026-11-19** Made **NES** the default console color, listed first in the picker. Classic Blue is still available.

- **2026-11-19** Fixed the companion app scene on wide screens. On the open iPhone Duo only the top of the hunter's head showed; the app now picks from four background shapes with a bottom-anchored crop. Also fixed a Swift concurrency warning by marking the NES colors `nonisolated`.

- **2026-11-20** Turned the companion home screen into the start of a side-scrolling adventure: shootable doves, walk cycle, a scrolling camera, seamless panorama tiling, scene 2 (tree, bushes, 4 doves), and scene 3 (log cabin, enter prompt, enter cut-scene, "TO BE CONTINUED…"). Played through on the simulator.

- **2026-11-20** Named the app game **The Hunter's Quest**, with its own score, BAGGED count, and records (`QuestStore`), shown separately from the widget's in Top Scores. Added generated sound effects (gunshot, squawk, grass and wood footsteps) with a Settings toggle. Fixed plain color backgrounds bleeding into the safe area, which made the cabin dialog's fill extend past its border on the Duo's inner screen.

- **2026-11-20** Added the cabin interior cut-scene (room art with a live TV, Anna with a walk cycle, two speech boxes, her exit through the back door, the hunter's puzzled look with a "?", the walk back out), the chimney dove outside, and scene 4 past the cabin. Fixed the HUD running under the menu button on narrow screens. Played through on the iPhone 18 Pro simulator.
