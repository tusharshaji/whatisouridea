--!strict

-- Arcade flight tuning.
--
-- Every value here is a plain quantity you can reason about on its own: studs
-- per second, degrees, or seconds. There are no lift coefficients, angles of
-- attack or air-density curves. The controller decides what speed, heading,
-- bank and climb rate it wants and commands them directly, so changing a number
-- here changes exactly the one thing its name describes.
--
-- Angles are written with math.rad() so you can edit them in degrees.

return {
	--------------------------------------------------------------------------
	-- Speed
	--------------------------------------------------------------------------
	MaxSpeed = 220, -- studs/sec at full throttle
	MinFlightSpeed = 60, -- airborne floor; the plane never slows past this, so
	-- it cannot stall or drop out of the sky at low throttle
	TakeoffSpeed = 50, -- ground speed before the nose will come up
	Acceleration = 80, -- studs/sec^2 while speeding up
	Braking = 60, -- studs/sec^2 while slowing down
	ThrottleRate = 0.6, -- throttle travel per second while W or S is held

	--------------------------------------------------------------------------
	-- Turning
	--
	-- Bank angle is what steers: A/D roll the aircraft and the heading follows
	-- in proportion, which is what makes the turn look and feel coordinated.
	-- Altitude is handled separately by the climb section below, so a turn on
	-- its own never costs height.
	--------------------------------------------------------------------------
	MaxBankAngle = math.rad(45), -- how far the wings will ever tilt
	BankRate = math.rad(110), -- how fast bank follows the A/D keys
	AutoLevelRate = math.rad(80), -- how fast the wings level once you let go
	MaxTurnRate = math.rad(55), -- heading change per second at full bank
	RudderTurnRate = math.rad(20), -- extra yaw from Q/E in the air
	GroundSteerRate = math.rad(45), -- Q/E steering while taxiing

	--------------------------------------------------------------------------
	-- Climb and descent
	--------------------------------------------------------------------------
	MaxClimbRate = 70, -- studs/sec with the Up arrow held
	MaxDescentRate = 70, -- studs/sec with the Down arrow held
	ClimbAcceleration = 90, -- studs/sec^2 easing toward the target climb rate
	MaxPitchAngle = math.rad(28), -- how far the nose may visibly tilt
	PitchRate = math.rad(80), -- how fast the nose follows the climb rate

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
	-- The height the plane parks at is measured from the model's own extents at
	-- startup rather than written down here, so moving the aircraft, raising it,
	-- or changing the landing gear all keep the wheels on the ground by itself.
	GroundTolerance = 1.5, -- how far above resting height still counts as landed
	GroundProbeDepth = 4000, -- how far down to look for ground; must exceed the
	-- deepest point of the map, or the plane will think it is over the void
	MaxAltitude = 2500, -- ceiling, measured in absolute world Y
	VoidHeight = -1000, -- genuinely fallen out of the world; well below the floor
	-- of a generated map, so valleys and sea bed never trigger it

	--------------------------------------------------------------------------
	-- Crashing
	--
	-- The controller commands velocity directly, so without this the aircraft
	-- would simply grind into a mountain and keep pushing. A short probe along
	-- the flight path turns that into a crash instead.
	--------------------------------------------------------------------------
	CrashEnabled = true, -- set false to fly through terrain while building courses
	CrashProbeDistance = 16, -- studs ahead of the nose to watch for terrain
	CrashRespawnDelay = 2.6, -- seconds of wreckage before the runway is restored
	CrashGracePeriod = 2, -- seconds after a respawn during which impacts are
	-- ignored. Without it, terrain close to the end of the runway puts the
	-- aircraft into a crash loop it can never take off out of.
	CrashImpactDot = -0.35, -- how head-on an impact must be to count as a crash.
	-- Compared against travel direction dotted with the surface normal, so a
	-- shallow touchdown on flat ground is a landing and a dive into the same
	-- ground, or level flight into a cliff face, is a crash.

	-- An impact unwelds the airframe and throws the pieces outward from the
	-- middle of the wreck. The seat keeps its weld so the pilot rides the main
	-- section down instead of being flung off on their own.
	CrashScatterSpeed = 42, -- outward studs/sec given to each loose part
	CrashScatterLift = 26, -- upward studs/sec on top of that, so it bursts
	CrashScatterSpin = 9, -- rad/sec of random tumble per part

	--------------------------------------------------------------------------
	-- Response
	--
	-- The plane is held by a LinearVelocity and an AlignOrientation rather than
	-- pushed with forces, so it cannot oscillate or drift. These control how
	-- firmly those two are allowed to act.
	--------------------------------------------------------------------------
	OrientationResponse = 40, -- AlignOrientation responsiveness; higher is snappier
	ForceHeadroom = 5000, -- constraint strength as a multiple of the plane's mass

	--------------------------------------------------------------------------
	-- Control surfaces. Cosmetic: the ailerons, elevator and rudder swing so
	-- you can see what the aircraft is being asked to do, but none of them
	-- produce any of the motion.
	--------------------------------------------------------------------------
	MaxAileronAngle = math.rad(28), -- aileron travel at full A/D
	MaxElevatorAngle = math.rad(25), -- elevator travel at full up/down arrow
	MaxRudderAngle = math.rad(32), -- rudder travel at full Q/E
	SurfaceRate = 6, -- how fast a surface reaches its angle; 1.0 is full travel
	RudderTurnMix = 0.8, -- how far A/D also swings the rudder into the turn

	--------------------------------------------------------------------------
	-- Rotor. Cosmetic only -- the propeller does not produce the thrust.
	--------------------------------------------------------------------------
	MaxRotorSpeed = 90, -- rad/sec at full throttle
	RotorSpoolTime = 1.2, -- seconds to reach ~63% of a new rotor speed

	--------------------------------------------------------------------------
	-- Physical make-up
	--------------------------------------------------------------------------
	AirframeDensity = 0.7, -- uniform density, so Material only affects looks
	ResetCooldown = 1, -- seconds between accepted reset requests
}
