# Light of Kirana

Godot 4.4 third-person movement prototype using a rigged Quaternius humanoid
and CC0 motion clips exported by KinemIQ.

## Character and animation

The player model is `assets/characters/light_of_kirana_animated.glb`. It contains
the rigged Quaternius Standard male model and seven animation clips:

- `Idle_relaxed`
- `Walk_forwards`
- `Run_jog_forwards`
- `Run_sprint`
- `Jump_take_off`
- `Jump_in_the_air`
- `Jump_landing`

Walk/run/sprint clips are in-place so the `CharacterBody3D` controller owns
world movement and collision. The controller scales animation cadence against
movement speed to reduce foot sliding.

See `assets/characters/THIRD_PARTY_LICENSES.txt` for asset sources and CC0 terms.

## Controls

- Desktop: WASD / arrow keys, Shift to run, Space to jump, drag mouse to orbit
- Android: virtual joystick, LARI and LOMPAT buttons, drag elsewhere to orbit

## Movement targets

- Walk: 2.0 m/s
- Run: 5.5 m/s
- Jump uses physics gravity and a one-shot take-off / airborne / landing animation sequence.

## Test

```sh
godot --headless --editor --path . --import --quit
godot --headless --path . --script res://tests/test_animated_character.gd
```

A passing headless test confirms the GLB imports and all seven named clips exist.
It does not replace a visual test on the target Android device.

## Android build

The workflow `.github/workflows/android-build.yml` remains manual-only.
No GitHub Actions workflow is triggered by this patch.
