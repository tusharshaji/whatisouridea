--!strict

-- Ring course tuning.
--
-- A course is a walk across the map that drops a gate every few hundred studs.
-- Where that walk goes is decided from a height grid sampled once at startup
-- (see TerrainSurvey), not from raycasts around whatever position it happens to
-- be standing on -- which is why an earlier version simply circled the flat
-- ground near the runway. It could not see the mountains, so it never went to
-- them.
--
-- The tightest corner the course may ask for comes out of the aircraft rather
-- than out of taste: turning is rolling and pulling, so the smallest circle is
-- MaxSpeed / PitchRate, about 148 studs. Two gates can never demand a change of
-- direction sharper than that in the distance between them, and retuning the
-- aeroplane retunes the course with it.
--
-- Climb is not a limit any more -- the aircraft can point straight up -- so how
-- steep a leg to allow is a design decision. See PlanningClimbSlope.

return {
	--------------------------------------------------------------------------
	-- Course shape
	--------------------------------------------------------------------------
	Seed = 20260813, -- base seed. Each player's course is this plus their own
	-- offset, so two pilots on one server fly different lines.
	RingCount = 30,
	FirstGateDistance = 800, -- runway to gate one, long enough to get airborne

	-- Where the land actually is.
	--
	-- Terrain.MaxExtents is not trustworthy: on a generated map it can report a
	-- region wildly larger than anything that was built, and the course then
	-- plans across a box that is mostly empty and not even centred on the
	-- island. Measure the map with tools/MeasureMap.luau and put the real
	-- numbers here. Set MapOverride to nil to go back to reading MaxExtents.
	MapOverride = {
		minX = -6000,
		maxX = 600,
		minZ = -6000,
		maxZ = 500,
	},
	FallbackExtent = 4096, -- only if there is no override and no usable terrain
	EdgeMargin = 400,

	--------------------------------------------------------------------------
	-- The survey grid
	--------------------------------------------------------------------------
	SurveyCell = 96, -- studs per sample. Smaller sees narrower passes and costs
	-- more rays: a 4096 map is about 1,800 samples at 96.
	RuggedRadius = 260, -- neighbourhood used when judging how broken up ground is
	WallRadius = 300, -- neighbourhood used when judging what stands above a gate

	--------------------------------------------------------------------------
	-- Steering. The walk aims at a rugged patch of map and re-aims when it
	-- arrives, which is what keeps it out among the terrain.
	--------------------------------------------------------------------------
	TargetMinDistance = 1400,
	TargetMaxDistance = 4200,
	RetargetWithin = 900, -- pick a new target once this close to the old one
	TargetPull = 0.55, -- how strongly a candidate is judged on heading toward
	-- the target versus on the terrain immediately around it

	--------------------------------------------------------------------------
	-- Spacing and turning. Both tighten as the course goes on.
	--------------------------------------------------------------------------
	StartSpacing = 900,
	EndSpacing = 500,
	StartTurn = math.rad(35),
	EndTurn = math.rad(75),
	TurnSafety = 0.8, -- fraction of the geometrically possible turn to use

	Candidates = 20, -- bearings tried per gate. These are grid lookups now
	-- rather than raycasts, so this can be generous.

	--------------------------------------------------------------------------
	-- Height. Measured from the ring's lowest point to the ground under it, so
	-- a gate is never generated buried in a hillside whatever its radius. Kept
	-- low deliberately: the aircraft is meant to be down among the rock.
	--------------------------------------------------------------------------
	StartMinClearance = 45,
	StartMaxClearance = 130,
	EndMinClearance = 15,
	EndMaxClearance = 65,
	ClimbSafety = 0.7,

	-- How steep a leg the course is willing to ask for, as rise over run. The
	-- aircraft can point straight up, so this is taste rather than a limit:
	-- 0.75 is about 37 degrees, steep enough to be interesting and shallow
	-- enough that arriving at the gate with any speed left is possible.
	PlanningClimbSlope = 0.75,

	-- The height of the sea, and nowhere near a safe default. A generated map
	-- puts sea level wherever the generator felt like, and this one sits at
	-- -644. Leaving it at 0 forced every gate to at least (0 + radius + margin),
	-- which on a map whose highest peak is Y=34 clamped the entire course above
	-- the island: rings hanging in clear sky with nothing to hit. Measure it.
	WaterLevel = -644,
	CeilingMargin = 150,

	-- A gate is only worth having if terrain stands above it. This is the
	-- fraction of the surrounding neighbourhood that has to be higher than the
	-- gate before it counts as threading the landscape rather than floating over
	-- it. Candidates are ranked on raw wall score, and any that clear this bar
	-- get a large bonus on top, so a genuinely enclosed line always beats a
	-- marginally better-aimed one out in the open.
	WallTarget = 0.35,
	WallBonus = 0.5,

	-- How far ahead and behind a gate has to be clear for the aircraft to get
	-- through it. Without this the search happily buries a gate in the most
	-- enclosed thing on the map, which is the inside of a mountain.
	CorridorReach = 220,

	--------------------------------------------------------------------------
	-- Gate size. Wingspan is 30 studs, so EndRadius leaves a little under a
	-- wingspan of room on each side.
	--------------------------------------------------------------------------
	StartRadius = 100,
	EndRadius = 38,

	--------------------------------------------------------------------------
	-- Appearance. Gates are built by each client for its own course only, so
	-- these are read on the client.
	--------------------------------------------------------------------------
	Segments = 18,
	Thickness = 3.4,
	ActiveColor = Color3.fromRGB(255, 132, 48),
	UpcomingColor = Color3.fromRGB(70, 110, 180),
	PassedColor = Color3.fromRGB(110, 225, 130),
	UpcomingTransparency = 0.5,
	PassedTransparency = 0.8,
	VisibleAhead = 3,
	FadeTime = 0.7, -- how long a gate takes to vanish once flown through

	--------------------------------------------------------------------------
	-- Scoring
	--------------------------------------------------------------------------
	BasePoints = 100,
	CenterBonus = 150,
	ComboStep = 0.25,
	MaxComboMultiplier = 5,
	MissRadiusFactor = 3.5,
	LapBonus = 1500, -- for finishing a whole course
}
