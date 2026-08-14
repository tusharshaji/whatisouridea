--!strict

-- Arcade flight tuning.
--
-- Every value here is a plain quantity you can reason about on its own: studs
-- per second, degrees, or seconds. There are no lift coefficients, angles of
-- attack or air-density curves.
--
-- The model is now a full-attitude one. The aircraft carries an orientation and
-- the controls turn it: pitch about its own right axis, roll about its nose,
-- yaw about its up. Velocity then runs along wherever the nose ends up pointing.
-- That is what makes loops, rolls and inverted flight work at all -- the earlier
-- model kept heading, bank and climb as three separate numbers and could not
-- represent being upside down, so pitch had to be clamped to a shallow cone.
--
-- The cost of that freedom is that a turn now costs altitude like a real one,
-- and it is possible to fly into the ground pointing the wrong way. Which is the
-- point.
--
-- Angles are written with math.rad() so you can edit them in degrees.

return {
	--------------------------------------------------------------------------
	-- Speed
	--------------------------------------------------------------------------
	MaxSpeed = 220, -- studs/sec at full throttle
	MinFlightSpeed = 55, -- airborne floor, so the aircraft never hangs still
	TakeoffSpeed = 50, -- ground speed before the nose will come up
	Acceleration = 80, -- studs/sec^2 while speeding up
	Braking = 60, -- studs/sec^2 while slowing down
	ThrottleRate = 0.6, -- throttle travel per second while W or S is held

	-- Pointing uphill costs speed and pointing downhill gains it. This is the
	-- only concession to real flight in the whole model, and it exists so that
	-- looping has a cost and diving has a reward.
	GravityDrag = 90, -- studs/sec^2 of speed change at straight up or straight down

	--------------------------------------------------------------------------
	-- Attitude rates. These are how fast the aircraft rotates about its own
	-- axes, and they are the whole of the handling model.
	--------------------------------------------------------------------------
	PitchRate = math.rad(85), -- nose up/down, arrow keys. Unlimited travel: hold
	-- it and the aircraft loops.
	RollRate = math.rad(150), -- A/D. Also unlimited, so it barrel rolls.
	YawRate = math.rad(35), -- Q/E in the air
	GroundSteerRate = math.rad(45), -- Q/E while taxiing

	-- With no roll input the wings drift back toward level, which keeps the
	-- aircraft flyable without constant correction. It is deliberately weak
	-- enough that it never fights a deliberate roll, and it gives up entirely
	-- past AutoLevelLimit so it cannot flip you out of inverted flight.
	AutoLevelRate = math.rad(45),
	AutoLevelLimit = math.rad(100), -- past this much bank, you are on your own

	-- The nose is pulled toward the horizon when nothing is asking otherwise, so
	-- letting go settles into level flight rather than holding a climb forever.
	PitchSettleRate = math.rad(25),

	--------------------------------------------------------------------------
	-- Altitude
	--
	-- Everything here is measured against the ground directly beneath the
	-- aircraft, found by a raycast each frame, rather than against world Y.
	-- Over terrain the two are not the same: a valley floor can sit hundreds of
	-- studs below zero and a plateau hundreds above, so an absolute height test
	-- would call the plane "landed" in mid-air over low ground and "flying"
	-- while buried in a hillside.
	--------------------------------------------------------------------------
	GroundTolerance = 1.5, -- how far above resting height still counts as landed
	GroundProbeDepth = 6000, -- how far down to look for ground. Must exceed the
	-- ceiling plus the depth of the sea bed, or an aircraft high over a low map
	-- finds no ground beneath it and believes it is over the void.
	MaxAltitude = 4000, -- ceiling, measured in absolute world Y
	VoidHeight = -1400, -- genuinely fallen out of the world. Must sit below the
	-- sea bed of the generated map, or a dive into a valley counts as falling
	-- out of the world.

	--------------------------------------------------------------------------
	-- Fuel
	--
	-- Burn is proportional to throttle, so cruising economically is a real
	-- decision. Running dry does not kill you outright -- it cuts the engine and
	-- leaves you gliding, badly, which is usually fatal but occasionally is not.
	--------------------------------------------------------------------------
	FuelCapacity = 100, -- base tank, before upgrades
	FuelBurnRate = 2.6, -- units per second at full throttle
	FuelIdleBurn = 0.35, -- units per second at zero throttle, engine still running
	DeadStickGravity = 34, -- studs/sec^2 the nose drops with no engine
	DeadStickDrag = 26, -- studs/sec^2 of speed bled off with no engine
	FuelWarnFraction = 0.2, -- below this, the HUD starts shouting

	--------------------------------------------------------------------------
	-- Crashing
	--------------------------------------------------------------------------
	CrashEnabled = true, -- set false to fly through terrain while building courses
	CrashProbeDistance = 16, -- studs ahead of the nose to watch for terrain
	CrashRespawnDelay = 2.6, -- seconds of wreckage before the runway is restored
	CrashGracePeriod = 2, -- seconds after a respawn during which impacts are
	-- ignored, or terrain near the runway makes takeoff impossible
	CrashImpactDot = -0.35, -- how head-on an impact must be to count as a crash

	-- An impact unwelds the airframe and throws the pieces outward.
	CrashScatterSpeed = 42,
	CrashScatterLift = 26,
	CrashScatterSpin = 9,

	--------------------------------------------------------------------------
	-- Response
	--------------------------------------------------------------------------
	OrientationResponse = 45, -- AlignOrientation responsiveness
	ForceHeadroom = 5000, -- constraint strength as a multiple of the plane's mass

	--------------------------------------------------------------------------
	-- Control surfaces. Cosmetic.
	--------------------------------------------------------------------------
	MaxAileronAngle = math.rad(28),
	MaxElevatorAngle = math.rad(25),
	MaxRudderAngle = math.rad(32),
	SurfaceRate = 6,
	RudderTurnMix = 0.8,

	--------------------------------------------------------------------------
	-- Rotor. Cosmetic only -- the propeller does not produce the thrust.
	--------------------------------------------------------------------------
	MaxRotorSpeed = 90,
	RotorSpoolTime = 1.2,

	--------------------------------------------------------------------------
	-- Physical make-up
	--------------------------------------------------------------------------
	AirframeDensity = 0.7,
	ResetCooldown = 1,

	--------------------------------------------------------------------------
	-- Spawn
	--------------------------------------------------------------------------
	SpawnRadius = 260, -- how close to the runway counts as "at spawn" for the
	-- hangar. Big enough to include the whole apron, small enough that you
	-- cannot re-arm halfway round the course.
}
