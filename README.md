# LAST DISTRICT

Original 3D open-world action / driving game for Android, set in the fictional Mediterranean city of **Santa Lucia**.
Godot **4.3-stable**, GDScript, Compatibility (OpenGL ES 3) renderer, ARM64 + ARMv7 (32-bit phones), landscape.

> **Honest status:** every system below is implemented and covered by an automated headless test suite
> (168 checks passing on Godot 4.3). Visuals are **procedural placeholder art** (boxes, cylinders, spheres,
> generated textures) - there are no authored 3D models, animations or recorded audio. The Android APK is
> produced by the GitHub Actions workflow in this repo; it has **not** been run on a physical device by the author.

## Get the APK
1. Push this folder to a GitHub repository (root of the repo = this folder).
2. Open **Actions > Android Build > Run workflow** (it also runs on every push to `main`/`master`).
3. When the run is green, open it and download the artifact **LastDistrict-android-apk** (contains `LastDistrict-debug.apk`).
4. Copy to the phone, allow "install unknown apps", install. Android 10/11+, 64-bit or 32-bit ARM phones (e.g. Cortex-A53 `armv7l`).

No signing credentials are needed for the debug APK. For a signed release APK add secrets
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_ALIAS`, `ANDROID_KEYSTORE_PASSWORD` (see `android/README.md`).
If the workflow fails, open the failed step; the build report on the run summary page lists test results and APK info.

## Controls (touch)
| Context | Control |
|---|---|
| Move | floating joystick (left half of screen) |
| Look | drag on the right side of the screen |
| On foot | FIRE, AIM, PUNCH, RELOAD, JUMP, SPRINT, CROUCH, USE |
| USE | enter/exit vehicle, talk, search clues, garage |
| In vehicle | GAS, BRAKE, steer `<` `>` (or joystick), HAND(brake), HORN, EXIT |
| Pause | `II` button top-right |

Keyboard (desktop testing): WASD/arrows, Shift sprint, Space jump/handbrake, E use, Enter/F fire, Q punch, R reload, C crouch, Tab aim, H horn, Esc pause.
Button size/opacity and camera sensitivity are adjustable in **Settings > Controls**.

## What is in the game
* **City:** ~800 m x 800 m grid, 100 procedurally generated blocks streamed in/out around the player (radius 2-3 blocks). Districts: downtown towers, residential, commercial (gas station, repair workshop, supermarket, car dealership), industrial (warehouses, containers, chimney), coast (beach + restaurants, marina, docks, crane), plus police station, hospital, player safehouse and garage. Roads, sidewalks, crosswalks, traffic lights, street lamps, palms, trees, benches, sea.
* **Player:** walk/run/sprint/jump/crouch, third-person camera with collision avoidance and aim zoom, articulated placeholder character.
* **Vehicles (8):** sedan, hatchback, sports car, SUV, pickup, police cruiser, motorcycle, off-road - each with its own handling config, handbrake drifting, damage, collision, lights, procedural engine audio.
* **Traffic and pedestrians:** pooled; pedestrians walk sidewalks, cross at crosswalks, flee from fast cars/danger; traffic follows lanes, obeys traffic-light phases, brakes for obstacles. Distance-throttled AI.
* **Police:** wanted levels 1-5 (1 unit -> 6 units, faster at 3, roadblocks at 4+, officers shoot an on-foot player from 3), sirens, search at last-seen position, arrest, escape/decay.
* **Missions:** 10 story missions + 3 side missions (`data/missions.json`): driving, delivery, exploration, chase, escape, character interaction (dialogue cutscenes), vehicle recovery, investigation. Objectives, time limits, fail + retry, rewards, vehicle unlocks, saving.
* **Combat:** pistol (raycast), reload/ammo, melee, enemy AI (chase, melee, shoot), health regen, hospital respawn.
* **Time & weather:** 20-minute day/night cycle, dynamic sky/sun/fog, lit windows and street lamps at night; clear, cloudy, light rain, heavy rain (optional), wet roads.
* **Collectibles:** 20 hidden packages (+$100 each).
* **Save/load:** `user://save.json` with checksum + validation; corrupt/tampered files are set aside and ignored. Autosave every 30 s, on mission complete, on pause/background.
* **UI:** main menu (Continue / New Game / Settings / Quit), loading screen, HUD (health, money, wanted stars, minimap, mission objective, speed, ammo), pause menu, settings (graphics, audio, controls).

## Performance design (3 GB RAM target)
* Rendering uses **Compatibility/GLES3**, no MSAA, orthogonal single-split sun shadow only, filmic tonemap, colour ambient (no sky radiance updates), 2048 shadow atlas.
* **Dynamic resolution:** the 3D scene renders in a SubViewport whose size adapts to FPS (Low 360p / Balanced 540p / High 720p base, scaled down to 55-60 % when below target), HUD stays native resolution. Manual resolution slider and FPS cap (30/60) in settings. Never renders above the device's native height.
* **Presets** Low / Balanced / High control stream radius, draw distance, shadows, fog, NPC/traffic counts, rain particles. **Performance mode** forces Low.
* **Streaming:** blocks built one per frame and freed when out of range; props use `visibility_range_end` distance culling; materials and meshes cached/shared; textures are tiny generated 64-128 px tiles.
* **Pooling:** pedestrians and traffic are reused/relocated, never re-instantiated each frame; far NPCs run at reduced tick rate.
* **Memory watchdog:** if process memory exceeds ~1.1 GB the stream radius is reduced automatically.
* **Battery:** FPS capped at 30 by default; game pauses and saves when the app is backgrounded.
* **Diagnostics:** Settings > "Developer diagnostics overlay" shows FPS, render size, memory, draw calls, objects, blocks, vehicles.

## Project layout
```
project.godot  export_presets.cfg
scenes/main.tscn            entry scene (everything else is built in code)
scripts/                    game.gd (autoload) world.gd city.gd player.gd vehicle.gd ped.gd police.gd
                            missions.gd hud.gd menu.gd main.gd settings_panel.gd ui_theme.gd gfx.gd sfx.gd
assets/shaders/water.gdshader
data/missions.json          mission definitions
tests/                      headless test suite (run_tests.gd)
.github/workflows/android-build.yml
android/README.md
```

## Run the tests locally
```
godot --headless --path . --import
godot --headless --path . res://tests/test_runner.tscn
```
Exit code 0 = all checks passed. (Godot's dummy headless renderer prints harmless `mesh_get_surface_count` errors.)

## Performance settings guide
* Phone is hot/laggy -> **Settings > Graphics > Preset = Low** or turn on **Performance mode**.
* Want smoother image -> leave **Automatic resolution scaling** on; or turn it off and set **Manual resolution scale**.
* Rain heavy on GPU -> set **Weather = Clear/Cloudy**.
* 60 FPS needs a stronger phone: **FPS cap = 60** (higher battery use).

## Troubleshooting
| Problem | Fix |
|---|---|
| Workflow fails at "Install Godot" | GitHub release download blocked/transient - re-run the job. |
| Workflow fails at "Import ... validate scripts" | A GDScript error; the log lists file and line. |
| "App not installed" on phone | Uninstall any older build signed with a different key; phone must be ARM (64 or 32-bit) and Android 10+. |
| Black screen / crash on launch | Capture `adb logcat -s godot` and open an issue; try Preset = Low. |
| Touch buttons too big/small | Settings > Controls > Button size. |
| Save seems lost | A corrupt save is renamed `save.json.corrupt`; use New Game. |

## Known limitations
* Placeholder art only (primitive meshes, procedural textures); no baked lightmaps, no occlusion culling, no authored LODs (distance visibility ranges are used instead).
* Humanoid animation is simple procedural limb swinging; no ragdoll, no enter-vehicle animation.
* Vehicle physics is arcade (CharacterBody3D), not a wheel/suspension simulation; "suspension" is visual body lean.
* Audio is synthesised procedurally (engine, siren, shots, footsteps, ambience, pad music) - functional, not studio quality.
* Pedestrians cannot enter buildings; there are no building interiors; parking spaces and parked cars are not modelled.
* Not tested on real hardware by the author; real-device FPS/memory numbers are unmeasured. Use the diagnostics overlay to measure on your phone.
* Mission 1 starts automatically when a new game begins (the first marker is at the spawn point).
