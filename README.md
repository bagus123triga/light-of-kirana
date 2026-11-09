# Light of Kirana — Procedural Walking Experiment

Procedural humanoid walking in Godot 4.4, no animation clips, no mocap.

Reference: **Procedural Humanoid Locomotion — Benjamin J Singer**
https://procedural-humanoid.benjaminjsinger.com/

Architecture (followed from the reference):
1. **Step planner** — stance target projected from velocity, land bias 0.47
2. **Spring-damped body** — hip stiffness 260 / damping 26
3. **Two-bone IK** — analytic, knee bends forward, feet stay planted

Numbers from the reference tuning panel: walk 1.75 m/s, run 4.4 m/s,
swing 0.38 s, foot clearance 0.17 m.

## Look

- World: flat grey map only (100 x 100 m plane), daylight sun + pale grey sky
- Humanoid: orange, built from primitives, all joints solved in code each frame
- Idle is a powered ragdoll (spring holds the body upright + breathing sway),
  not a limp collapse — like Zelda / Genshin idle

## Controls

- Desktop: WASD / arrows to walk, Shift to run, Space to jump, drag mouse to orbit camera
- Touch: left virtual joystick to walk, LARI button to run, LOMPAT button to jump,
  drag anywhere else to orbit camera

## Build (manual only)

GitHub Actions workflow `.github/workflows/android-build.yml` is
`workflow_dispatch` only — it never runs on push. To build, open
Actions > Android Build (Manual Only) > Run workflow, type `BUILD`,
download the debug APK from the run.

## Test (headless, local only)

```sh
godot --headless --editor --path . --import --quit
godot --headless --path . --script res://tests/test_procedural_walk.gd
```

A passing `WALK_TEST PASS` is a local check only — the tablet test is the verdict.
