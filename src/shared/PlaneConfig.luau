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
	--------------------------------------------------------------------------
	RunwayHeight = 0.1, -- Y of the tarmac surface
	-- The height the plane parks at is measured from the model's own extents at
	-- startup rather than written down here, so moving the aircraft, raising it,
	-- or changing the landing gear all keep the wheels on the ground by itself.
	GroundTolerance = 1.5, -- how far above resting height still counts as landed
	MaxAltitude = 2500, -- ceiling, to keep the plane in view of the world
	ResetHeight = -40, -- fall below this and the plane returns to the runway

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
