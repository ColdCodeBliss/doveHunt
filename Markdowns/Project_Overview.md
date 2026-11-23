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
| 4. Meadow past the cabin | Tree, bushes, and **5 doves**. |
| 5. The pond | A fisherman in rubber waders casting into a small pond, with his big brown dog **Max** sitting beside him. See the pond scene below. |
| 6. Foothills | Snowy mountains on the horizon, pines, a bush, and a tree. **5 doves and 1 mallard**. |
| 7. Mountain pass | Two mountain ranges, two pines, and a bush. **4 doves and 2 mallards**. |
| 8. The fisherman again | He stands mid-meadow holding his **tackle box**, with Max sitting beside him. See the tackle box scene below. After the box is picked up, **3 doves and 1 mallard** fly in. |
| 9. The leash | The fisherman, now with Max on a **leash**, stands by a tree. They walk up to the hunter for a conversation. See the leash scene below. |
| 10. Karma | Three doves fly over the hunter (they can't be shot) and poop on him. See below. |
| 11. The bear | A brown bear in the pines: rears up, bluff-charges, roars. Two warning shots send it off, and dusk falls. See below. |
| 12. The stream | A doe and her fawn drink at a stream with **2 mallards** floating on it. The deer bolt, the mallards take off, and you shoot them. See below. |
| 13. The fork | Two paths: a wooden **"Campgrounds"** sign, and a chain-link fence with a locked gate and a **"Restricted Access"** sign with an alien head. A lone mountain rises behind the gate, with a dirt trail switchbacking up it. Tap a sign to choose. See below. |
| Campground route: 14. Campsite | An RV, a campfire, and a dad and kid in camp chairs roasting marshmallows. A proceed arrow appears after 3 s. |
| Restricted route: 14. The night trail | It's night now. A bare dirt trail with no trees or bushes, a gusting wind (streaks, blowing dust, and a wind sound). The hunter pauses 3 s, then walks on by himself. |
| Restricted route: 15. The UFO | Same eerie trail. The hunter walks to the middle, a UFO swoops in overhead, he goes wide-eyed, and green rings come down its beam as he's lifted up and fades away. The UFO flies off to the left, then fade to black. |
| The alien console | A full-screen mini game: Simon says on a 4×4 grid. Match **3** sequences to win; **2** misses trigger **SYSTEM LOCKDOWN** and a reboot. A win shows **ACCESS GRANTED**. |
| Aboard the UFO | Inside the saucer, his shotgun gone: "Whoa... where am I? This sure isn't the campgrounds." then "I hope they have a bathroom on this thing, that pickle sandwich is fighting back.." His stomach gurgles, he clutches it wide-eyed, and he walks on. |
| The aliens' lab | Two aliens at a metal table (with his shotgun on it) spot him ("!"), turn, and walk over chattering in alien. He goes "?", a squeaky fart slips out, he glances behind him... "Seriously man, manners?" / "Nice." They leave, he takes his shotgun back and walks on. |
| The specimen vats | A dove and a mallard float belly-up in two vats of green goo. On instinct, he shoots both: the glass shatters, the alarms flash, and the birds drop to the deck. A lab-coat scientist runs in, the birds rise as skeletons, he drops his clipboard and screams, and the skeletons chase him off. Tap the **clipboard** (under a bobbing arrow) to pick it up; the inventory opens on it, and closing it sends the hunter on. |
| The wrecked lab | Smashed by the chase: a toppled table, a knocked-over vat, goo, papers, smoking scorch marks, cracks, a flickering panel, and a sparking cable. The hunter walks to the middle, looks left and right, scratches his head ("?"), and walks on. |
| The pristine lab | The scientist floats in a vat; the two skeletons, now in lab coats with clipboards, observe. The hunter goes wide-eyed, the skeletons look over, the scientist says something alien. The hunter puts his shotgun away, whistles his way over with the clipboard, leaves it on a table, and walks out. Fade to **TO BE CONTINUED…**. |
| Campground route: 15 | Placeholder for the next scenes: it fades to **TO BE CONTINUED…** (tap to return to the start). |

- **Mallards** (`BirdKind.mallard`, art `mallard_wings_up` / `mallard_wings_down` / `mallard_hit`, 19×14 px). A mallard takes **two shots**. The first shot wounds it: a small puff, a **quack**, and for 0.45 s (`AdventureGame.woundDuration`) the hit sprite (feathers ruffled, eye squeezed shut, tumbling) knocked down a few pixels and shaking. The second shot downs it with a full poof and a lower double **quack_down**. A mallard is worth **200 points** (2 doves). Doves and mallards share the scene's `doves` list; each entry has a `kind`.
- **Landscape on phones.** On an iPhone held in portrait (`ContentView` checks for a phone with a screen taller than wide and under 600 pt across), the home screen still shows with an extra **ROTATE YOUR DEVICE AND** line above **SHOOT THE DOVES TO BEGIN!**, but doves can't be shot. Rotating mid-quest shows a **ROTATE YOUR DEVICE / TO KEEP HUNTING** card (`RotateDeviceCard`) that blocks taps. iPads and the open Duo play in any orientation. Short (landscape phone) screens use a compact title header.
- **Tackle box scene** (`TackleStep`, `AdventureGame.TackleTiming`, `TackleLayout`, `TackleCast`):
  1. **Fleeing:** when the hunter arrives, Max stands, a **"!"** pops up, and he bolts off to the right. **"Max, wait!"** shows over the fisherman as he turns to chase him, and the tackle box **slips out of his hand** and drops into the grass.
  2. **Waiting:** a bobbing orange **arrow** points down at the box. Tap the box (or its arrow) to pick it up. Nothing else happens until you do.
  3. **Collected:** "Tackle box added to inventory!" shows over the spot for about 2 s (with a success haptic). Then the **inventory opens on its own** with the tackle box's description showing (`AdventureGame.inventoryRequest`, handled in `ContentView`), and **3 doves and a mallard fly in** from the right edge, the same way the pond doves do (`releaseDoves()`, `AdventureScene.dovesFlyIn`). Shoot them all and the hunter walks on.
- **Leash scene** (`ReunionStep`, `AdventureGame.ReunionTiming`, `ReunionLayout`, `ReunionCast`):
  1. **Approaching:** the fisherman starts by the tree and walks over (2.8 s) with Max just ahead of him on a red **leash**. The leash is drawn live, one pixel wide, from his hand to Max's collar with a slight sag. Their run frames, played slowly, serve as a walk.
  2. **Talking:** three speech bubbles, **tap to continue** (each shows "> TAP"). Lines are in `AdventureGame.reunionLines`:
     - Fisherman: "Oh great, it's YOU. You scared off every fish in that pond, and Max ran two miles before I caught him. TWO. MILES. I just wanted some peace and quiet!"
     - Hunter: "Relax, I found your tackle box! ...I did eat the other half of your pickle sandwich, though." (The tackle box leaves the inventory here: it's been returned.)
     - Fisherman: "You're a real piece of work. That sandwich fell on the floor, by the way. You'll probably be pooping your pants soon."
  3. **Returned:** after the last tap the tackle box leaves the inventory and a **"Tackle box removed from inventory"** pop-up (with the box's sprite) shows for 2.4 s. Then the hunter walks on.
- **Poop scene** (`AdventureGame.PoopTiming`, drawn in `poopCast`): three doves cross from right to left above the hunter, 0.6 s apart. Each drops a `poop_drop` straight down onto his clothes (shoulder, chest, sleeve), where a `poop_splat` stays for 0.8 s and then fades over 3.2 s. Then: "I guess I deserved that... there sure have been a lot of poop references today." The doves can't be shot.
- **Bear scene** (`AdventureGame.BearTiming`, `BearCast`):
  1. The bear (`bear_standing`, 36×58) rears up on its hind legs while the hunter does a wide-eyed, jaw-dropped double take (`hunter_shocked`, about 1 s). Then it drops to all fours (`bear_four`, 54×32).
  2. It bluff-charges about 46 px toward the hunter (`bear_run_a/b`), then **roars** (`bear_roar`, a "ROAR!" bubble, a little shake, and a generated `roar` sound).
  3. The hunter fires **two warning shots** (muzzle flash, gunshot, haptic) and the bear scampers off to the right.
  4. "Wow, Smokey Bear put on some weight.." over the hunter.
  5. **Dusk:** the hunter tilts his head up at the sky (`hunter_look_up`) while the sky and scenery shift toward sunset over 3 s (a purple-to-orange gradient multiplied over the background and props; characters stay bright). It stays dusk for the rest of the run (`AdventureGame.duskStart`).
  6. "It's getting dark. Probably time to head back to camp soon." Then the hunter walks on.
- **The fork and its routes** (`QuestRoute`, `ForkStep`, `AdventureGame.ForkTiming`, `ForkLayout`, `CampsiteLayout`):
  - **Routes:** the main trail (`AdventureScenes.all`) ends at the fork. Choosing a path sets `AdventureGame.route`, and that route's scenes (`AdventureScenes.campgroundRoute` / `restrictedRoute`) follow the fork in the world strip. Everything looks scenes up through `AdventureGame.spec(_:)` and `sceneCount`.
  - **Layout:** the campground sign sits near the right edge, clear of the camera cutout. The fence (98 px: the gate plus three panels) is placed from the board's real width on each screen (`ForkLayout(sceneWidth:scale:)`), so there's always at least 20 px of grass between them, even on the Duo's inner display. Behind the gate stands `prop_far_mountain` (130×76), whose dirt trail starts right behind the gate and switchbacks up its face. The sign board is placed in the scene, centered on its post, so it scrolls in with the fork rather than appearing early pinned to the screen. It's nudged in from the edge so it clears the camera cutout.
  - **Choosing:** "Which way should I go?" with "> TAP A SIGN" shows over the hunter. The signs are drawn live in the pixel font (the font gained "(" and ")").
  - **Campgrounds:** the hunter walks on past the fence to the campsite.
  - **Restricted Access** (tap its sign or the fence): the hunter walks up to the gate. The padlock **flashes slowly** (a yellow rim every 1.2 s) until you **shoot it**. It drops, the gate swings open (`fence_open`), and he steps through, fading to black. The next restricted-route scene then fades in.
  - **Night on the restricted route:** stepping through the gate sets `AdventureGame.isNight`. The scenes there (`isEerie`) get a deep-blue night tint multiplied over the sky and scenery, with 40 twinkling pixel stars, a tiled `prop_dirt_path`, and a wind overlay (pale streaks and dust motes rushing across in slow gusts; hidden with Reduce Motion). A generated `wind` sound plays on arriving at each eerie scene. An empty scene's wait before walking on comes from `AdventureScene.linger`.
  - **Abduction** (`AdventureGame.AbductionTiming`): the hunter walks to the middle (2.2 s). The saucer (`ufo_a/b`, blinking rim lights) swoops in from the top right with a `ufo_arrive` whine. He goes wide-eyed (`hunter_shocked`). At 4.8 s the tractor beam switches on with a pulsing `ufo_beam` warble: a soft green cone plus `beam_ring` rings sliding down and widening (drawn in front of him). He's lifted 46 px and fades out, then the scene fades to black and on to the end screen.
  - **The alien console** (`ConsoleView.swift`; rules and state in `ConsoleState` and `AdventureGame`, timings in `ConsoleTiming`):
    - **Look:** a brushed-metal panel with seams and rivets. A bezelled green-phosphor monitor (with scanlines) sits in the middle, between side panels of blinking LEDs, turning knobs, chunky push buttons, and alien glyph labels. Everything snaps to one chunky pixel unit.
    - **Play:** after a boot-up ("INITIALIZING..." then "MATCH THE SEQUENCE"), random cells flash random colors one at a time (0.5 s each, with a tone per grid row). Then "YOUR TURN": tap the cells in the same order. Each sequence is one step longer than the last matched one (3, 4, then 5). Three slots in the header fill green per match; two fill red per error.
    - **Lose:** two errors show **SYSTEM LOCKDOWN** (flashing red, hazard stripes, a jolt, all LEDs red, a siren), then fade to black and reboot for another try.
    - **Win:** three matches show **ACCESS GRANTED** (pulsing green, all LEDs green, a rising chime), then fade to black.
    - **Sounds:** `console_beep_0…3`, `console_correct`, `console_error`, `console_alarm`, `console_granted`.
  - **Aboard the UFO** (`AboardView`, `AboardTiming`; the shared room is `UFOInteriorBackground` / `UFOInteriorLayout`): purple-black bulkheads, three portholes onto twinkling stars, glowing wall panels, and a deck with a glowing edge strip.
    - The aliens took his shotgun (`AdventureGame.hasShotgun`), so he's drawn with the unarmed sprites (`hunter_unarmed`, `hunter_unarmed_walk_a/b`, `hunter_unarmed_shocked`).
    - He starts wide-eyed and has two remarks. Then a `gurgle` sound plays while he clutches his stomach (`hunter_stomach`), and he walks off to the right, straight into the next room.
  - **The aliens' lab** (`AlienLabView`, `AlienTiming`), in the same room:
    1. The hunter walks in. Two aliens (`alien`, `alien_walk_a/b`) stand with their backs to him at a `metal_table` holding his `shotgun_item`.
    2. They get a "!" and turn around, and he goes wide-eyed. They walk to the middle and chatter in alien symbols (`alien_gibberish` sound).
    3. A "?" over him, then a `squeaky_fart`. Four little `gas_puff` clouds puff out from the seat of his pants (`AppArt.hunterRear`), drifting back and up as they swell and fade over about 1.5 s. He glances behind him at them, and back.
    4. "Seriously man, manners?" then "Nice." The aliens walk off to the right.
    5. He walks to the table and takes his shotgun back (it leaves the table, he's armed again, success haptic), then walks off to the right and the screen fades.
  - **The specimen vats** (`VatLabView.swift`; `VatStep`, `VatTiming`), in the same room:
    1. He walks in. Two vats on metal bases with blinking LEDs (`vat_back` / `vat_front`, with the bird drawn belly-up between the two layers so it reads as submerged) hold a bobbing dove and mallard. An alarm light sits dark on each cap.
    2. He fires twice: each vat shatters (`vat_broken`, the metal frame survives) with a `glass_shatter`, and its alarm starts flashing (with the console siren). Goo gushes out into a spreading puddle and the bird drops to the deck.
    3. A scientist alien in a lab coat with a clipboard (`scientist*`) runs in. With a puff and a `bone_rattle`, the birds rise as skeletons (`skeleton_dove*`, `skeleton_mallard*`) and the hunter goes wide-eyed.
    4. The scientist drops the clipboard, goes wide-eyed (`scientist_scared*`), and lets out an "EEEEEEEK!" (`alien_scream`). The skeletons reach out their wing bones and shuffle after him as he flees off to the right.
    5. **Waiting:** a bobbing arrow over the dropped clipboard. Tap it: "Clipboard added to inventory!", then the inventory opens on its description. Closing it (`AdventureGame.inventoryClosed()`, called from `ContentView`) moves to `.leaving`: he walks off to the right and the screen fades.
  - **The wrecked lab** (`LabsView.swift` → `WreckedLabView`, `WreckedTiming`): the same room under flickering lights, with zigzag wall cracks, a flickering broken panel, and a cable dangling from the ceiling spitting pixel sparks. On the deck: a toppled `metal_table`, a knocked-over `vat_broken`, spilled goo, a scorch mark with grey smoke curling up, and scattered papers. He walks to the middle, looks left and right, scratches his head (`hunter_scratch`, shotgun hanging at his side) with a "?", then walks off to the right, straight into the next room.
  - **The pristine lab** (`PristineLabView`, `PristineTiming`): a spotless room with a metal table and a big vat (drawn at 1.5× scale) holding the scientist (`scientist_bare`), flanked by the skeletons in lab coats (`skeleton_dove_coat`, `skeleton_mallard_coat`).
    1. He walks in and goes wide-eyed. The skeletons look over at him, and the scientist says something alien (`alien_gibberish`).
    2. His shotgun goes away (unarmed sprites), and he carries the clipboard to the table, whistling (`whistle`, with little pixel music notes). He sets it down and it leaves the inventory.
    3. Shotgun back, he walks off to the right. Fade to the end screen (`finishesFromBlack`).
  - **Clipboard** (`InventoryItem.clipboard`): "An alien scientist dropped this while fleeing his own experiment. It's all squiggles, except a doodle of a dove with a big X on it... and a little drawing of a pickle sandwich. Probably important."
  - **Campsite:** `rv`, a flickering `campfire_a/b`, `camper_dad`, and `camper_kid` (mirrored to face dad across the fire). After 3 s a bobbing **proceed arrow** (`arrow_right`) appears at the right edge. Tap it to walk on.
- **Stream scene** (`AdventureGame.StreamTiming`, `StreamLayout`, `StreamCast`): a doe and her spotted fawn (`deer_*` 44×40, `fawn_*` 30×28) drink at the far end of a winding stream (`prop_stream`, 150×18), while two mallards float on it (`mallard_float`) bobbing gently. Both deer look up with a **"!"** and bound off to the right. Then the mallards **take off from the water** (with a quack) and hover; each takes two shots. Once both are down, the hunter walks on.
  - Speech bubbles over 90 characters use a wider box (40 columns instead of 30) so they take fewer rows.
  - **Art:** `tackle_box` (16×12), `arrow_down` (9×10), and the fisherman and dog sprites from the pond.
- **Inventory** (`InventoryItem` in `Adventure.swift`, `InventoryView.swift`):
  - **Button:** a wooden **crate** (`crate_icon`) in the top-right corner, styled like the menu button. An orange dot marks a new item until the inventory is opened. The HUD keeps clear of it.
  - **Panel:** a 4×2 grid of pixel slots. Tap an item to read its description; on short (landscape phone) screens the description sits beside the grid.
  - **Tackle box:** "The fisherman dropped this while chasing Max. Hooks, lures, and half a pickle sandwich. We should probably return it... it's the least we can do after ruining his peace and quiet."
  - **Lifetime:** items last for the current run; restarting the quest clears them. New items are added as cases of `InventoryItem`.
- **Cabin interior cut-scene** (`InteriorView.swift`; steps are `InteriorStep`, timings are `AdventureGame.InteriorTiming`):
  1. **Arriving:** fade in. The hunter steps in from the front door (wooden footsteps). Anna, in raggedy blue overalls with patches, a white apron, and a bonnet, faces away, then turns toward him.
  2. **Speaking:** an "ANNA:" speech box with a stepped tail. Tap for her second line, then tap again. Her lines are in `AdventureGame.annaLines`.
  3. **Anna leaving:** she walks to the kitchen's back door. It opens, she slips out, and it closes.
  4. **Puzzled:** the hunter looks left, then right, and a "?" bubble appears over his head.
  5. **Leaving:** he walks back out the front door and the screen fades to black. Back outside it fades in, with the hunter at the cabin door and the chimney dove waiting.
- **Pond scene** (`PondStep`, `AdventureGame.PondTiming`, `PondLayout`, `PondCast`). All of it plays on timers; nothing needs a tap.
  1. **Greeting:** "Ahh, finally some peace and quiet." shows over the fisherman for about 3 s.
  2. **Doves:** **3 doves fly in from the right edge**, one every 0.3 s (`doveFlyInStagger`), each gliding down into place over the water in 1.6 s (`doveFlyIn`, ease-out). Shoot them.
  3. **Max startled:** he stands, a **"!"** pops over his head, and he runs off to the right.
  4. **The yell:** "I'm fishing here man, are you crazy! MAX, come back buddy!" When it ends, the rod and line disappear and he turns and runs after Max.
  5. **Whoops:** a **"Whoops"** bubble appears over the hunter, then he walks on.
  - **Art:** `prop_pond_large` / `prop_pond` / `prop_pond_small`, `fishing_rod` / `fishing_rod_short`, `fisherman` with two run frames, and `dog_sit` / `dog_stand` with two run frames. The fishing line and the red bobber are drawn live from the rod tip to the water.
  - **Layout:** the fisherman stands on the far bank facing left. On wide screens (every phone in landscape) the **large pond** (88×24 px, a full oval drawn as a superellipse) reaches left from his feet, with the line landing in the water. Where it would crowd the hunter, the 52×15 pond is used instead, centered under the rod tip.
  - **Narrow screens** (scene < 120 art px wide, i.e. iPhone portrait) use a compact layout: a smaller pond and shorter rod, Max sitting in front of the fisherman, pond doves hovering 14 px higher, and the hunter framed 12 px past the left edge (`PondLayout.hunterOffset`). Hunter positions per scene come from `AdventureFrame.restOffset`: the cabin door, the pond framing, or the left edge.
- **Room layout.** The room (`interior_door_closed` / `interior_door_open`, 240×130 px) has plank walls, floorboards, a box TV with rabbit ears on a stand, a couch, a painting, a window with gingham curtains, a table with two chairs, a white fridge, a kitchen island, and the back door.
  - **Fit:** it's drawn as a stage, fit to the screen without cropping. On tall screens the dialog sits in the black space above the room.
  - **TV:** the screen is drawn live (`TVStatic`), flipping between random color scenes (bars, snow, checks, bands) every 0.8 s, with scanlines.
- **Flow.** When every dove in a scene is down, the title fades (a **BAGGED n** counter replaces it) and the hunter walks to the next scene.
- **World.** The world is a strip of screen-wide scenes laid end to end over the background, which **tiles seamlessly** because the hills use whole-number wave counts across the width. Everything is in art pixels, snapped to the grid.
- **Walking.** The hunter walks one scene at a steady pace (`walkDuration` 3.6 s, 4-frame walk cycle at 8 fps). The camera lets him stride toward the middle (`hunterX − 0.3·W·sin(πp)`), then catches up so he arrives at the left of the next scene.
- **Timing.** Walking, scrolling, and fades are computed from the phase's start date each frame inside a `TimelineView`. Phase changes (arrive, cabin, inside) are scheduled tasks, guarded by a generation counter so a restart cancels pending ones.
- **Data-driven scenes.** `AdventureScenes.all` lists each scene's doves (as fractions of the screen width and heights above the grass) and props (`tree`, `bush`, `pine`, `mountains`, `cabin`, `pond`). Scripted scenes are flagged with `hasPondEvent`, `hasTackleBoxEvent`, `hasReunionEvent`, `hasPoopEvent`, `hasBearEvent`, or `hasStreamEvent`. New scenes are added there.
- **Adapts to every screen.** Doves stay inside the screen edges, the cabin always fits fully on screen, and the dialog box wraps to the screen width.
- **Art.** New generated sprites: `hunter_walk_a` / `hunter_walk_b`, `feather_poof`, `muzzle_flash`, `prop_tree`, `prop_bush`, `cabin_closed` / `cabin_open`.
- **Separate records.** **The Hunter's Quest** is the companion app's game. Its score (100 per dove), BAGGED count, and records are completely separate from the widget game.
  - **Storage:** `QuestStore` (app-only `UserDefaults.standard`) holds lifetime doves, cabin visits, and best score. The widget's numbers stay in the shared App Group `GameStore`.
  - **Home screen:** shows "THE HUNTER'S QUEST" and the quest's **BEST** score.
  - **HUD:** shows this run's **SCORE** and **BAGGED**.
  - **Top Scores:** has separate **THE HUNTER'S QUEST** and **WIDGET HUNT** sections.
- **Sound effects** (`SoundEffects.swift`, generated by `Tools/generate_sounds.py`, files in `doveHunt/Sounds/`):
  - **Sounds:** gunshot (noise crack plus falling boom, light bit-crush), bear roar (a wobbling low sawtooth in rumbling noise), dove squawk (falling, vibrato square tone), mallard quack and a lower double quack when it goes down (a buzzy sawtooth through two band-pass "formants"), grassy footsteps (3 variants), and wooden footsteps (3 variants, for the cabin interior).
  - **Footsteps** play on each stride frame of the walk cycle. Each scene's `surface` (`.grass` / `.wood`) picks the sound.
  - **Playback:** an `.ambient` audio session (mixes with music, respects the silent switch) and a pool of 3 voices per sound so shots can overlap.
  - **Off the main thread:** all audio work (session setup and activation, loading, `prepareToPlay`, and playback) runs on a private serial queue inside `SoundEffects`. Doing it on the main thread triggered Xcode's runtime **"AVAudioSession Hang Risk"** warnings.
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
- **2026-11-21** Moved all audio work off the main thread, fixing the 24 "AVAudioSession Hang Risk" runtime warnings. Verified on the simulator: no warnings at launch or while shooting and walking.

- **2026-11-21** Added 5 doves to scene 4 and the pond scene (fisherman, Max, rising doves, the "!" and runaway, the yell and chase, "Whoops"), plus placeholder scene 6. Added a compact pond layout for narrow screens after a simulator play-through showed the pond under the hunter. The full run reaches BAGGED 16.

- **2026-11-21** Added scenes 6 and 7 (mountains, pines, bushes, a tree; 5 doves + 1 mallard, then 4 doves + 2 mallards). Added the **mallard**: two shots to down, a wounded hit animation and quack on the first shot, and a double quack on the second, for 200 points. Added generated `prop_pine` and `prop_mountains` art. Phones now must be in **landscape** to play: portrait shows a rotate prompt on the title screen and a rotate card mid-quest. Added a compact title header for landscape phones.
- **2026-11-21** Made the pond bigger for landscape (new `prop_pond_large`, 72×19 px, reaching left from the fisherman's bank). The pond scene's doves now fly in from the right edge one after another instead of rising out of the water.
- **2026-11-21** Added scene 8: the fisherman and Max bolt when the hunter arrives, and the fisherman drops his tackle box under a bobbing tap arrow. Added a simple **inventory**: a crate button in the top-right corner opens a slot grid, and tapping the tackle box explains (comically) that we should return it. Generated `tackle_box`, `arrow_down`, and `crate_icon` art.
- **2026-11-21** Made the landscape pond bigger and a fuller oval (88×24 px). Added "Max, wait!" to the tackle box scene, plus 3 doves and a mallard that fly in once the box is picked up. Added scene 9: the fisherman walks Max over on a leash for a tap-through conversation, and the tackle box is returned (it leaves the inventory).
- **2026-11-21** The inventory now opens on its own to the tackle box's description after the pickup. The tackle box is handed back after the fisherman's last line, with a "removed from inventory" pop-up. Added scene 10 (doves poop on the hunter), scene 11 (the bear: rear up, bluff charge, roar, two warning shots, dusk falls), and scene 12 (deer at a stream bolt, then two floating mallards take off to be shot). Generated bear, deer, fawn, floating mallard, stream, and poop art, plus a roar sound.
- **2026-11-21** Bear scene: added "Wow, Smokey Bear put on some weight.." after the bear runs off, then the hunter looks up at the sky as dusk falls before his remark. Added scene 13, a fork in the trail with branching routes. **Campgrounds** leads to a campsite (RV, campfire, dad and kid roasting marshmallows, proceed arrow). **Restricted Access** leads to a chain-link gate whose flashing padlock must be shot before the hunter can step through. Added `(` and `)` to the pixel font.
- **2026-11-21** The hunter now does a wide-eyed double take on reaching the bear. The fork's campground sign is fixed to its post in the scene, so it no longer shows up early on screen and slides into place. Added more space between the restricted gate and the campground sign.
- **2026-11-21** Fork tidy-up: the sign now just says "Campgrounds", the pine is gone, and the fence is shorter and placed from the sign's real size so they never touch. Added a distant mountain behind the restricted gate with a dirt trail leading up it.
- **2026-11-22** The restricted route now plays at night. Scene 14 is an eerie, windswept dirt trail the hunter walks through on his own. Scene 15 is a UFO abduction: he walks to the middle, the saucer swoops in, he goes wide-eyed, green rings come down the tractor beam, and he's lifted away before the fade to black. Added generated wind, UFO arrival, and tractor-beam sounds, plus `ufo_a/b`, `beam_ring`, and `prop_dirt_path` art.
- **2026-11-22** After the abduction the UFO flies off to the left before the fade. Added the alien console mini game: Simon says on a 4×4 grid, 3 matches to win, and 2 misses trigger a SYSTEM LOCKDOWN and reboot. A win shows ACCESS GRANTED and leads to a scene aboard the UFO. Generated console sounds.
- **2026-11-22** Aboard the UFO the hunter has lost his shotgun (new unarmed sprites). He adds the bathroom line, then his stomach gurgles and he clutches it. Added the aliens' lab: two aliens notice him, chatter in alien, react to his squeaky fart ("Seriously man, manners?" / "Nice.") and leave, and he takes his shotgun back from their table. Generated alien, table, and shotgun art, plus gurgle, gibberish, and fart sounds.
- **2026-11-22** Replaced the generated stomach gurgle and fart with recorded sounds (converted from MP3 to `gurgle.wav` and `squeaky_fart.wav`). `generate_sounds.py` no longer writes those two files.
- **2026-11-22** Added a little gas cloud (pixel `gas_puff` art) that puffs out behind the hunter as the fart plays in the aliens' lab.
- **2026-11-23** Added the specimen-vat lab after the aliens' lab. The hunter shoots a dove and a mallard out of their vats of green goo, the birds rise as skeletons and chase off a screaming scientist, and the dropped clipboard can be picked up as a new inventory item. Generated vat, skeleton, scientist, and clipboard art, plus glass-shatter, scream, and bone-rattle sounds.
- **2026-11-23** The clipboard now opens the inventory on pickup, and closing it moves the story on. Added the wrecked lab (debris, smoke, sparks; the hunter looks around and scratches his head) and the pristine lab (the scientist in a vat, the skeletons in lab coats; the hunter whistles over and leaves the clipboard on a table). Generated head-scratch, coated-skeleton, and scientist art, plus a whistle.
