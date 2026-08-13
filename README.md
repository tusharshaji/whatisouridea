# whatisouridea

A Roblox flying game built with [Rojo](https://rojo.space/). An arcade-style
aircraft with a stable, forgiving flight model, a runway to take off from, and
moving control surfaces.

## Getting started

Requires [Aftman](https://github.com/LPGhatguy/aftman), which pins the Rojo
version in `aftman.toml`.

```bash
aftman install          # once, to get Rojo
rojo build -o "whatisouridea.rbxlx"
```

Open the resulting place file in Roblox Studio, then start the sync server:

```bash
rojo serve
```

and hit **Connect** in the Rojo Studio plugin.

> Editing a `.luau` file hot-reloads. Editing `default.project.json` does not --
> restart `rojo serve` and reconnect the plugin, or the change will never reach
> Studio.

## Flying

Sit in the pilot seat and a flight panel appears.

| Key | Action |
| --- | --- |
| `W` / `S` | Throttle up / down |
| `Up` / `Down` | Climb / descend |
| `A` / `D` | Bank and turn |
| `Q` / `E` | Rudder |
| `R` | Reset to the runway |

Hold `W`; once the panel reads `READY - PULL UP`, pull back.

## How the flight model works

It is deliberately **not** an aerodynamic simulation. An earlier version was --
lift coefficients, angle of attack, air density, propeller thrust curves -- and
it was unpredictable to fly and shed altitude badly in turns.

The controller instead keeps five numbers (throttle, speed, heading, bank, climb
rate), eases each toward what the pilot is asking for, and commands the result
through a `LinearVelocity` and an `AlignOrientation`. The aircraft has no
momentum of its own to fight, so it cannot spin, oscillate, sideslip or fall out
of a bank.

Turning and climbing are independent: heading comes from bank angle, height from
climb rate, and neither reads the other, so banking never costs altitude. Every
limit is a clamp, and every easing goes through one `approach()` helper that
steps toward a target without overshooting -- which is why nothing oscillates.

## Layout

| Path | Contents |
| --- | --- |
| `default.project.json` | The world and the aircraft, as real instances |
| `src/server/Airplane.server.luau` | Flight controller (server authoritative) |
| `src/client/PlaneControls.client.luau` | Keyboard input and the HUD |
| `src/shared/PlaneConfig.luau` | Every handling value, commented for tuning |

Tuning lives entirely in `PlaneConfig.luau` -- speed, turn rates, climb limits,
bank limits, control-surface travel -- with angles written as `math.rad()` so
they read in degrees.

### A note on editing the aircraft

Colours, materials, part sizes and extra decoration are all free: the controller
no longer reads the geometry, so shape and mass do not affect handling. Resting
height is measured from the model at startup, so the plane can be moved or given
taller gear and it still sits on its wheels.

Part *names* do matter. `Fuselage`, `RotorHub`, `PilotSeat`, `State`, the four
attachments and the three constraints are all found by `WaitForChild`, so a
rename does not error -- the script simply hangs at startup and the plane never
responds.
