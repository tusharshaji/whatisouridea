# whatisouridea

A Roblox flying game built with [Rojo](https://rojo.space/). Every pilot gets
their own aircraft and their own ring course threaded through a generated
mountain map, and spends what they earn on faster aeroplanes.

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

> **Build the place file once, then never again.** Terrain lives in the place,
> not in `default.project.json`, so re-running `rojo build` overwrites the saved
> place and the generated terrain is gone. After the first build, only ever
> `rojo serve` into the existing place and save from Studio.

> Editing a `.luau` file hot-reloads. Editing `default.project.json` does not --
> restart `rojo serve` and reconnect the plugin, or the change will never reach
> Studio.

## The map

Terrain is generated in Studio, not by this repo. The settings the flight model
is tuned around:

| Setting | Value | Why |
| --- | --- | --- |
| Map size | 4096 x 1024 x 4096 | 4096 is ~19 sec to cross at full throttle |
| Biome size | 300 | Default 100 gives features you cross in half a second |
| Biomes | Mountains, Canyons, Hills, Plains, Water | Canyons give walls to thread |
| Caves | off | Generation time you never see from a cockpit |

Delete the Baseplate before generating, and put the runway somewhere flat
afterwards. The map size is read from `Workspace.Terrain.MaxExtents` at runtime,
so a different size needs no code change -- the server prints the bounds it found
at startup, which is the first thing to check if courses appear somewhere odd.

## Flying

You are seated in your own aircraft automatically when you join.

| Key | Action |
| --- | --- |
| `Up` / `Down` | Throttle up / down |
| `W` | Nose up. Hold it and you loop. |
| `S` | Nose down |
| `A` / `D` | Roll, with no limit -- hold it and you barrel roll |
| `Q` / `E` | Rudder, deliberately weak |
| `R` | Restart the run, back at the runway |
| `B` | Hangar (only at the runway) |
| Right-drag | Look around; recentres itself after a moment |
| Scroll | Camera distance |

Set `InvertPitch` in `PlaneConfig.luau` to swap `W` and `S`, for a stick that
works the way a real one does.

Hold the up arrow; once the centre bar reads `ROTATE`, hold `W`. Watch
`AGL` rather than `ALT` -- `ALT` is height above sea level and says nothing about
the mountain immediately below you.

Fuel burns with throttle. Run dry and the engine quits, but you keep every
control and the aircraft glides exactly as it does with the throttle shut, only
slower. Losing height is then yours to solve by pointing the nose somewhere
sensible.

## The flight model

It is a full-attitude model. The aircraft carries an orientation, the controls
rotate it about its own axes, and velocity runs along wherever the nose ends up
pointing. Loops, rolls and inverted flight all fall out of that for free.

This replaced a model that kept heading, bank and climb rate as three separate
numbers. That one was beautifully stable and fundamentally incapable of being
upside down -- with bank as a scalar clamped to 45 degrees and height as a climb
rate rather than a direction, there was nowhere for a loop to live, which is why
pitch had to be clamped to a shallow cone.

What it costs is the old guarantee that a turn never lost altitude and that the
aircraft could never be pointed at the ground. Both were load-bearing for
"forgiving" and both had to go. What keeps it flyable is a weak auto-level that
gives up past 100 degrees of bank, so it settles you when you are nearly upright
and never fights you when you are deliberately inverted. How strong that is
varies per aircraft: the Trainer wants to fly level, the Delta does not care.

## The course

Fly through the lit gate. An arrow at the edge of the screen points at it when it
is off to the side or behind you.

Gates are worth more the smaller they are, more again for a centred pass, and
every consecutive gate raises a combo multiplier up to 5x. A gate fades out
behind you once flown.

**Crashing costs the whole run, and kills you.** The airframe comes apart, the
pilot goes with it, and you restart from the runway at gate one. `R` does the
same thing deliberately -- as a free reset it would just be an escape hatch from
every crash about to happen.

Two currencies, because a crash should cost a run and not an evening:

| | Wiped by a crash | What it is for |
| --- | --- | --- |
| **Score** | yes | The run you are flying, and your best |
| **Points** | no | Banked. Spent in the hangar. |

## The hangar

`B` opens it, **and only at the runway** -- fly off and it shows you the door.
The server enforces that too, not just the UI.

Four aircraft, each an actual different model rather than a recolour: the
Trainer is a high-wing propeller thing, the Sport a low-wing racer, the Jet has
swept wings and twin exhausts with fire, the Delta is a three-engined dart. They
are defined as part specs in `PlaneModels.luau` and built at runtime.

Four upgrade tracks, all in `UpgradeConfig.luau` -- the same table the server
validates purchases against, so what is on the button is what gets charged:

- **Engine** -> top speed
- **Wings** -> roll and yaw rate
- **Lift** -> pitch rate, so really how hard it pulls
- **Fuel Tank** -> how long you can stay up

Buying an aircraft rebuilds it and restarts the run. Buying an upgrade applies
immediately and tops up your tank. Nothing bought touches the crash rules or the
gate sizes, so a fully upgraded Delta is faster and sharper but still has to be
flown through the same rock.

> Purchases last for the session only. There is no DataStore yet, so a server
> restart resets everyone's bank.

## How courses are generated

A course is a walk across the map that drops a gate every few hundred studs, and
it is generated per pilot from a per-pilot seed. Nobody flies the same line.

The walk is steered by a **height grid sampled once at startup**
(`TerrainSurvey`). This matters: an earlier version asked the terrain questions
with raycasts around whatever position it had already picked, which meant it
could only see a few hundred studs and had no idea the mountains existed. It
circled the flat ground near the runway forever. With a grid, every question --
how high is it there, how broken up is that ground, am I below the ridge line --
is a free table lookup, so the generator can look at the whole map, pick a rugged
patch a couple of thousand studs away, and aim at it.

Each gate is chosen from twenty candidate bearings, scored on:

- **Wall score** -- what fraction of the surrounding neighbourhood stands *above*
  the gate. This is the measure that means "flying below the ridge line".
- **Aim** -- how well the bearing heads toward the current rugged target.
- A hard filter that the line straight through is actually flyable.

Two limits come from the aircraft rather than from taste:

- **Turn radius** `MaxSpeed / MaxTurnRate` = about 229 studs, so no two gates
  demand a corner tighter than the plane can fly.
- **Climb slope** `MaxClimbRate / MaxSpeed` = about 17.6 degrees, so no gate sits
  higher above the last one than that slope reaches across the gap.

Retune the aircraft in `PlaneConfig.luau` and the course retunes itself.

## Layout

| Path | Contents |
| --- | --- |
| `default.project.json` | The world and the aircraft, as real instances |
| `src/server/Main.server.luau` | Pilots, courses, scoring, purchases |
| `src/server/PlaneController.luau` | One aircraft, belonging to one pilot |
| `src/server/TerrainSurvey.luau` | The height grid the course is planned on |
| `src/server/CourseBuilder.luau` | Gate placement |
| `src/client/PlaneControls.client.luau` | Input and the flight panel |
| `src/client/RingHud.client.luau` | Score, gate marker, and drawing your rings |
| `src/client/ShopUi.client.luau` | The hangar |
| `src/shared/UiTheme.luau` | Fonts, palette and UI building blocks |
| `src/shared/PlaneConfig.luau` | Every handling value |
| `src/shared/PlaneModels.luau` | What each aircraft is made of |
| `src/shared/RingConfig.luau` | Every course and scoring value |
| `src/shared/UpgradeConfig.luau` | Aircraft, upgrades, prices |
| `src/shared/Ensure.luau` | Get-or-create, instead of waiting forever |
| `src/client/CameraRig.client.luau` | Chase camera |
| `src/client/DevPanel.client.luau` | Test panel, `F4` |
| `src/shared/DevConfig.luau` | Who is allowed to use it |
| `tools/MeasureMap.luau` | Measures your island. Not part of the game. |

## Dev panel

`F4`, in Studio or as the place owner. Grants points, unlocks aircraft and
upgrades, toggles invincibility, refuels, skips to the active gate, rolls a new
course, and wipes progress to test the ramp from zero.

Every button fires a remote the server re-authorises with `DevConfig` on
arrival. The `IsDev` attribute only decides whether the panel is drawn -- a
client can fire that remote whatever it was told, so the flag is presentation
and the check is the real gate. Add collaborators by user id in
`DevConfig.UserIds`.

### Things that are easy to break

**Never `WaitForChild` a state value or a remote from a server script.** Use
`Ensure.luau`, which creates it if missing. Those instances are declared in
`default.project.json`, and that file reaches Studio only when `rojo serve` is
restarted -- so adding one and forgetting the restart makes every script that
waits on it hang at startup, forever, with no error. The aircraft stops
responding, no course is generated, and the place looks like it is loading. Real
geometry still uses `WaitForChild`, because a missing wing should not be quietly
replaced with an empty Part.

**Height is measured against the ground below, not against world Y.** An earlier
version compared altitude to a fixed number taken off the runway, which was fine
on a flat baseplate and wrong the moment terrain existed: flying low over ground
near sea level made the plane decide it was parked, which locked the wings level
and refused all descent. Anything asking "is it airborne" must raycast.

**Gate parts must keep `CanQuery = false`.** A queryable gate registers as solid
rock in the crash sweep and as ground in the altitude probe.

**A rotated GuiObject is not clipped by its parent.** Not by `ClipsDescendants`,
and not by a `CanvasGroup` either -- both were tried. The artificial horizon used
to be two coloured Frames rotated against each other, and it sat neatly inside
its circle while level and painted itself across the screen the instant the
aircraft banked. It is a `ViewportFrame` looking at a real ground plane now,
which is always clipped to its own rectangle and has nothing to escape. If you
need rotating UI, rotate a camera in a ViewportFrame rather than rotating flat
UI inside a container.

**Panels that list things use `AutomaticSize`.** Fixed heights were smaller than
the content and the last few rows rendered outside the background.

**All UI goes through `UiTheme`.** Every screen used to build its own labels in
`Font.Code`, a monospace face meant for source listings, which combined with
terminal-style abbreviations made the game look like a debug overlay. The theme
holds the font stack, the palette and the building blocks -- panels, cards,
meters, buttons, pills -- so screens stay consistent and none of them reach for a
raw `Instance.new("TextLabel")` with a hand-picked colour.

**Rings are drawn by the client, for its own course only.** They were server
instances once, which meant everyone could see everyone's rings and one pilot
flying through one scored it for the whole room. The server still owns detection;
the client only draws.

**Respawning clones a new aeroplane rather than reassembling the wreck.** The
version that broke the welds, flung the parts and put the same parts back lost
pieces -- debris that fell past `FallenPartsDestroyHeight`, or through thin
terrain, was gone before reassembly ran and could not be recreated. A fresh clone
cannot be missing anything.

**Aircraft share a non-self-colliding collision group.** Without it one pilot can
swat another off the course.
