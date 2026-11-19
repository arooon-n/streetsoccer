# Goal Digger

Offline 3D football for Android, built with Godot 4.7 (GDScript, Mobile renderer).
No internet permission, no ads, no purchases. Everything (stadiums, players, audio) is generated in code.

## Modes
- **Quick match** vs bots: 11v11 (Harbor Arena, Old Ground) or 5-a-side Street Cage, 5 difficulties, day/dusk/night, rain.
- **Cup & League**: 8-team knockout (extra time + penalties in the final), 14-matchday league with table and top scorers.
- **Hero challenges**: 60 draw-the-pass levels in 4 chapters, 1-3 stars each.
- **Training ground**: free kicks, penalties, corners, shooting gallery, dribble run, keeper reflexes. Daily drill.
- **Club / Kit room / Records / Settings**: crest + kit editor, unlockables, stats, graphics presets.

## Build the APK
```
# release keystore + password live in android/ (keep private, back them up)
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$PWD/android/goaldigger-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=goaldigger
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<password from android/keystore.properties>
godot --headless --path . --export-release "Android" build/GoalDigger.apk
```

## Tests (`scripts/dev/tests.gd`)
```
godot --headless --path . -- --test parse      # every script and shader compiles
godot --headless --path . -- --test physics    # ball flight / roll / curl
godot --headless --path . -- --test solver     # shot solver accuracy
godot --headless --path . -- --test levels     # all 60 hero levels solvable
godot --headless --path . -- --test sim 11     # full bot-vs-bot match (also: sim 5)
godot --headless --path . -- --test userplay 11  # scripted user controls through a match
godot --path . -- --test herobot 1-1 2-4 ...   # hero levels played through touch input
godot --path . -- --test drillbot              # all six drills played through
```

## Layout
- `scripts/autoload` game state/saves/settings (`game.gd`), synthesised audio (`sfx.gd`)
- `scripts/world/stadium.gd` venues; `shaders/` pitch, crowd, nets, LED boards, players, ball
- `scripts/actors` ball physics (`ball_sim.gd`, `ball.gd`), skinned player mesh, procedural animation rig
- `scripts/match` match director, team AI, touch controls, HUD, cameras, swipe shots
- `scripts/modes` hero challenges (sim, levels, solver, gameplay) and training drills
- `scripts/screens` menus; `scripts/ui` widgets (slanted buttons, segmented controls, crests, icons)
