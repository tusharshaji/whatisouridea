--!strict

-- The server. One aircraft, one course and one scoreboard per pilot.
--
-- Aircraft are built from specs in PlaneModels rather than cloned from an
-- authored template, which is why there is no longer an Airplane model in the
-- project file: a jet has to actually be shaped like a jet, and that cannot come
-- from recolouring one shared airframe.
--
-- Gate detection is a plane crossing, not a Touched event. At several hundred
-- studs a second the aircraft moves a long way between frames and a gate is
-- three studs thick, so touching one is a coin flip. Testing which side of the
-- gate's plane it was on last frame and which side it is on now cannot be
-- tunnelled, and gives the accuracy figure for scoring in the same step.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DevConfig = require(ReplicatedStorage.Shared.DevConfig)
local PlaneConfig = require(ReplicatedStorage.Shared.PlaneConfig)
local RingConfig = require(ReplicatedStorage.Shared.RingConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)
local ensure = require(ReplicatedStorage.Shared.Ensure)

local CourseBuilder = require(script.Parent.CourseBuilder)
local PlaneController = require(script.Parent.PlaneController)
local Save = require(script.Parent.Save)
local TerrainSurvey = require(script.Parent.TerrainSurvey)

local COLLISION_GROUP = "Planes"

-- Several gates can fall inside a single frame at speed, so detection runs a
-- short loop rather than testing one gate and giving up.
local MAX_GATES_PER_FRAME = 4

-- How often the seating and airframe watchdog runs. Four times a second is
-- imperceptible to a player and nothing here is expensive.
local SUPERVISE_INTERVAL = 0.25

-- How often progress is written back, in seconds. Leaving and shutdown both
-- flush as well; this is only insurance against a crash taking the server with
-- it.
local AUTOSAVE_INTERVAL = 120

-- Bump this whenever you change a server file. "Is Studio actually running the
-- current code?" has been the real answer to enough bug reports here that it is
-- worth one line of Output to settle it at a glance instead of by symptom.
local BUILD = "2026-08-15e"

Players.RespawnTime = 3

print(`[Main] server build {BUILD}`)

--------------------------------------------------------------------------------
-- World setup
--------------------------------------------------------------------------------

local planesFolder = Instance.new("Folder")
planesFolder.Name = "Planes"
planesFolder.Parent = Workspace

-- The engine deletes any unanchored part below this line, and the default is
-- -500. This island's valleys bottom out around -851 with water at -644, so the
-- default quietly deleted whole aeroplanes mid-flight the moment somebody dived
-- into low ground -- no crash, no wreck, no respawn, just a pilot standing on
-- the runway wondering where their aircraft went. It has to sit below the point
-- at which the game itself calls you out of the world.
--
-- In a pcall because everything below this line -- planes, courses, scoring, the
-- dev panel -- lives in the same script, and a single throwing property write at
-- the top would take the entire game down with it.
local heightOk, heightErr = pcall(function()
	Workspace.FallenPartsDestroyHeight = PlaneConfig.VoidHeight - 500
end)
if not heightOk then
	warn(`[Main] could not set FallenPartsDestroyHeight: {heightErr}`)
end

pcall(function()
	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
end)
PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)

-- Start of the runway, pointing down it. Taken from the tarmac itself so moving
-- the runway moves the aircraft with it.
local function runwayPad(): CFrame
	local runway = Workspace:FindFirstChild("Runway")
	local tarmac = runway and runway:FindFirstChild("Tarmac") :: BasePart?

	if not tarmac then
		warn("[Main] no Runway.Tarmac found; spawning aircraft at the origin")
		return CFrame.new(0, 5, 0)
	end

	-- The tarmac is longer than it is wide, so its length runs along local Z.
	-- Park at the near end. No rotation: a CFrame's LookVector is its -Z, which
	-- already points down the strip from here. Turning it 180 degrees would
	-- line every aircraft up facing off the end of the runway.
	local halfLength = tarmac.Size.Z / 2
	return tarmac.CFrame * CFrame.new(0, tarmac.Size.Y / 2, halfLength - 30)
end

local basePad = runwayPad()

local remotes = ensure(ReplicatedStorage, "Remotes", "Folder")
local inputRemote = ensure(remotes, "PlaneInput", "RemoteEvent") :: RemoteEvent
local courseRemote = ensure(remotes, "CourseData", "RemoteEvent") :: RemoteEvent
local eventRemote = ensure(remotes, "GameEvent", "RemoteEvent") :: RemoteEvent
local buyRemote = ensure(remotes, "BuyUpgrade", "RemoteEvent") :: RemoteEvent
local devRemote = ensure(remotes, "DevAction", "RemoteEvent") :: RemoteEvent

-- One filter for every raycast: no aircraft and no character should ever read as
-- terrain. The pilot's own character is welded into the seat and sits directly
-- in the path of the crash sweep.
local probe = RaycastParams.new()
probe.FilterType = Enum.RaycastFilterType.Exclude
probe.IgnoreWater = false

local function refreshProbeFilter()
	local filter: { Instance } = { planesFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	probe.FilterDescendantsInstances = filter
end

refreshProbeFilter()

local function groundAt(x: number, z: number): number?
	local top = PlaneConfig.MaxAltitude + 500
	local hit = Workspace:Raycast(
		Vector3.new(x, top, z),
		Vector3.new(0, -(top - PlaneConfig.VoidHeight), 0),
		probe
	)
	return if hit then hit.Position.Y else nil
end

-- A measured override wins outright. Terrain.MaxExtents sounds like the right
-- source and is not: on a generated map it can report a region far larger than
-- anything built, so the survey spreads its samples across mostly nothing.
local function mapBounds(): (number, number, number, number)
	local override = RingConfig.MapOverride
	if override then
		return override.minX, override.maxX, override.minZ, override.maxZ
	end

	local extents = Workspace.Terrain.MaxExtents
	local minX, maxX = extents.Min.X * 4, extents.Max.X * 4
	local minZ, maxZ = extents.Min.Z * 4, extents.Max.Z * 4

	if (maxX - minX) < 512 or (maxX - minX) > 60000 then
		warn("[Main] Terrain.MaxExtents is unusable and no MapOverride is set. "
			.. "Measure the map with tools/MeasureMap.luau.")
		local half = RingConfig.FallbackExtent / 2
		return -half, half, -half, half
	end
	return minX, maxX, minZ, maxZ
end

--------------------------------------------------------------------------------
-- Terrain survey, once, in the background
--------------------------------------------------------------------------------

local survey: TerrainSurvey.Survey? = nil
local boundsMinX, boundsMaxX, boundsMinZ, boundsMaxZ = mapBounds()

task.spawn(function()
	print(string.format(
		"[Main] map bounds X %.0f..%.0f  Z %.0f..%.0f",
		boundsMinX, boundsMaxX, boundsMinZ, boundsMaxZ
	))

	survey = TerrainSurvey.build(
		boundsMinX,
		boundsMaxX,
		boundsMinZ,
		boundsMaxZ,
		RingConfig.SurveyCell,
		probe,
		PlaneConfig.MaxAltitude + 500,
		PlaneConfig.VoidHeight,
		RingConfig.WaterLevel
	)
end)

--------------------------------------------------------------------------------
-- Pilots
--------------------------------------------------------------------------------

type Pilot = {
	player: Player,
	controller: any,
	slot: number,
	gates: { CourseBuilder.Gate },
	activeIndex: number,
	combo: number,
	lastPosition: Vector3,
	lap: number,
	lastReset: number,
	planeId: string,
	levels: { [string]: number },
	-- False when this player's save could not be read. Their progress is then
	-- never written back, so a DataStore outage cannot overwrite good data with
	-- the defaults they are flying on.
	saveable: boolean,
	-- "course" or "casual". Casual has no gates, no crashing and no fuel: it is
	-- the mode for going and looking at the island.
	mode: string,
}

local pilots: { [Player]: Pilot } = {}
local usedSlots: { [number]: boolean } = {}

local function claimSlot(): number
	local slot = 0
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	return slot
end

-- Runway slots: three abreast, then further back down the tarmac.
local function padForSlot(slot: number): CFrame
	local across = (slot % 3 - 1) * 14
	local along = -math.floor(slot / 3) * 52
	return basePad * CFrame.new(across, 0, along)
end

local function publishAttributes(pilot: Pilot)
	local player = pilot.player
	player:SetAttribute("PlaneId", pilot.planeId)
	for _, upgrade in UpgradeConfig.Upgrades do
		player:SetAttribute("Level_" .. upgrade.id, pilot.levels[upgrade.id] or 0)
	end
end

-- Stat-only change: no new airframe, so the aircraft keeps flying.
local function refreshStats(pilot: Pilot)
	pilot.controller:applyStats(UpgradeConfig.statsFor(pilot.planeId, pilot.levels))
	publishAttributes(pilot)
end

-- Aircraft change: the model itself is different, so it has to be rebuilt.
local function equipPlane(pilot: Pilot, planeId: string)
	local def = UpgradeConfig.findPlane(planeId) or UpgradeConfig.Planes[1]
	pilot.planeId = def.id
	pilot.controller:setPlane(def.id, def.color)
	pilot.controller:applyStats(UpgradeConfig.statsFor(def.id, pilot.levels))
	pilot.controller:reset()
	publishAttributes(pilot)
end

local function sendCourse(pilot: Pilot)
	local payload = {}
	for _, gate in pilot.gates do
		table.insert(payload, { p = gate.center, n = gate.normal, r = gate.radius })
	end
	courseRemote:FireClient(pilot.player, payload)
	pilot.player:SetAttribute("TotalGates", #pilot.gates)
	pilot.player:SetAttribute("ActiveGate", pilot.activeIndex)
end

local function buildCourse(pilot: Pilot)
	-- Casual pilots get an empty course rather than a hidden one. The client draws
	-- what it is sent, so an empty payload is what makes the rings, the marker and
	-- the gate counter all go away at once.
	if pilot.mode == "casual" then
		pilot.gates = {}
		pilot.activeIndex = 1
		courseRemote:FireClient(pilot.player, {})
		pilot.player:SetAttribute("TotalGates", 0)
		pilot.player:SetAttribute("ActiveGate", 1)
		return
	end

	while not survey do
		task.wait(0.25)
	end

	local plane = pilot.controller.model
	if not plane then
		return
	end

	local pivot = plane:GetPivot()
	pilot.gates = CourseBuilder.build(
		survey :: TerrainSurvey.Survey,
		groundAt,
		pivot.Position,
		pivot.LookVector,
		RingConfig.Seed + pilot.player.UserId % 100000 + pilot.lap * 7919,
		boundsMinX,
		boundsMaxX,
		boundsMinZ,
		boundsMaxZ
	)

	pilot.activeIndex = 1
	if pilot.controller.fuselage then
		pilot.lastPosition = pilot.controller.fuselage.Position
	end
	sendCourse(pilot)

	print(`[Main] course for {pilot.player.Name}: {#pilot.gates} gates, lap {pilot.lap + 1}`)
end

local function restartRun(pilot: Pilot)
	pilot.combo = 0
	pilot.activeIndex = 1

	local player = pilot.player
	player:SetAttribute("Score", 0)
	player:SetAttribute("Combo", 0)
	player:SetAttribute("Multiplier", 1)
	player:SetAttribute("ActiveGate", 1)

	if pilot.controller.fuselage then
		pilot.lastPosition = pilot.controller.fuselage.Position
	end
end

local function ownedSet(player: Player): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	local raw = player:GetAttribute("OwnedPlanes")
	for id in string.gmatch(if type(raw) == "string" then raw else "trainer", "[^,]+") do
		owned[id] = true
	end
	return owned
end

local function writeOwned(player: Player, owned: { [string]: boolean })
	local list = {}
	for id in owned do
		table.insert(list, id)
	end
	table.sort(list)
	player:SetAttribute("OwnedPlanes", table.concat(list, ","))
end

-- The attributes are the live truth while the player is here; this turns them
-- back into something the store can hold. Keeping one source rather than two
-- means the saved profile cannot drift from what the pilot is actually flying.
local function profileFor(pilot: Pilot): Save.Profile
	local player = pilot.player
	return {
		points = player:GetAttribute("Points") or 0,
		best = player:GetAttribute("Best") or 0,
		planeId = pilot.planeId,
		owned = ownedSet(player),
		levels = pilot.levels,
		saveable = pilot.saveable,
	}
end

local function savePilot(pilot: Pilot)
	if not pilot.saveable then
		return
	end
	Save.store(pilot.player, profileFor(pilot))
end

-- Fold a loaded profile into a pilot who is already flying.
--
-- Everything about progress arrives this way rather than being waited for,
-- because the DataStore read is the one part of joining that can take seconds or
-- never finish, and nothing about getting into an aeroplane should depend on it.
-- Blocking on it here once meant that a Studio session without API access spent
-- twelve seconds with no aircraft, no attributes and no dev panel while the read
-- retried an error that was never going to clear.
local function applyProfile(pilot: Pilot, profile: Save.Profile)
	local player = pilot.player

	-- Anything earned in the seconds before the profile landed is kept, not
	-- overwritten. Small, but losing points to a race is the sort of thing that
	-- makes a save system feel untrustworthy.
	local earned = player:GetAttribute("Points") or 0
	player:SetAttribute("Points", profile.points + earned)
	player:SetAttribute("Best", math.max(profile.best, player:GetAttribute("Best") or 0))

	local owned = ownedSet(player)
	for id in profile.owned do
		owned[id] = true
	end
	writeOwned(player, owned)

	for id, level in profile.levels do
		pilot.levels[id] = math.max(pilot.levels[id] or 0, level)
	end

	-- Only from here on, so the autosave and the leave handler cannot write the
	-- defaults the pilot was flying on a moment ago over their real save.
	pilot.saveable = profile.saveable
	player:SetAttribute("ProgressSaving", profile.saveable)

	-- Rebuilding the airframe interrupts whatever they are doing, so it happens
	-- only when the saved aircraft is not the one already under them.
	if profile.planeId ~= pilot.planeId then
		equipPlane(pilot, profile.planeId)
	else
		refreshStats(pilot)
	end
end

-- Switch between flying the course and just flying.
--
-- Casual turns off the three things that make a run a run: gates to chase,
-- terrain that kills you, and a tank that empties. It is not a difficulty
-- setting -- nothing is scored in it at all -- so it needs no balancing against
-- course mode, and points earned before switching are simply kept.
local function setMode(pilot: Pilot, mode: string)
	if mode ~= "casual" and mode ~= "course" then
		return
	end
	if pilot.mode == mode then
		return
	end

	pilot.mode = mode
	local casual = mode == "casual"
	local controller = pilot.controller

	controller.invincible = casual
	controller.unlimitedFuel = casual
	controller:refuel()

	local player = pilot.player
	player:SetAttribute("Mode", mode)
	player:SetAttribute("Invincible", casual)

	-- The run does not carry across. Score is per-run and casual has no runs, so
	-- coming back to the course starts a clean one at gate one.
	pilot.combo = 0
	pilot.lap = 0
	player:SetAttribute("Score", 0)
	player:SetAttribute("Combo", 0)
	player:SetAttribute("Multiplier", 1)

	task.spawn(buildCourse, pilot)
end

local function addPilot(player: Player, profile: Save.Profile)
	local slot = claimSlot()
	local controller = PlaneController.new(
		player,
		planesFolder,
		padForSlot(slot),
		probe,
		COLLISION_GROUP
	)

	local pilot: Pilot = {
		player = player,
		controller = controller,
		slot = slot,
		gates = {},
		activeIndex = 1,
		combo = 0,
		lastPosition = controller.fuselage and controller.fuselage.Position or Vector3.zero,
		lap = 0,
		lastReset = 0,
		planeId = profile.planeId,
		levels = profile.levels,
		saveable = profile.saveable,
		mode = "course",
	}
	pilots[player] = pilot

	-- Score and combo are the run, and a run is never restored. Points, best and
	-- the hangar are the progress, and those come straight out of the save.
	player:SetAttribute("Score", 0)
	player:SetAttribute("Combo", 0)
	player:SetAttribute("Multiplier", 1)
	player:SetAttribute("Crashed", false)
	player:SetAttribute("Mode", "course")
	player:SetAttribute("Points", profile.points)
	player:SetAttribute("Best", profile.best)
	writeOwned(player, profile.owned)
	-- So the client can say so rather than letting someone bank an hour of
	-- points that were never going to be written down.
	player:SetAttribute("ProgressSaving", profile.saveable)
	-- Only decides whether the panel is drawn. Every action is re-checked on
	-- arrival, because an attribute is not a permission.
	player:SetAttribute("IsDev", DevConfig.isDeveloper(player))

	-- Equip rather than just apply stats: this is what gives the aircraft its
	-- colour and its actual shape, and the controller built a default one in
	-- its constructor before any of that was known.
	equipPlane(pilot, profile.planeId)

	controller.onCrash = function()
		eventRemote:FireClient(player, { kind = "crash" })
		pilot.combo = 0
		player:SetAttribute("Combo", 0)
		player:SetAttribute("Multiplier", 1)
	end

	controller.onReset = function()
		restartRun(pilot)
	end

	task.spawn(buildCourse, pilot)
end

local function removePilot(player: Player)
	local pilot = pilots[player]
	if not pilot then
		return
	end

	pilots[player] = nil
	usedSlots[pilot.slot] = nil
	pilot.controller:destroy()

	-- After the table entry is gone, so a slow write cannot be raced by the same
	-- player rejoining this server.
	savePilot(pilot)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		refreshProbeFilter()
		local pilot = pilots[player]
		if pilot then
			task.defer(function()
				pilot.controller:seatPilot()
			end)
		end
	end)

	refreshProbeFilter()

	-- In the air first, progress second. The aeroplane, the course and every
	-- attribute exist before the DataStore is asked anything, so a store that is
	-- slow, throttled or switched off costs the player nothing but a few seconds
	-- of showing zero points.
	--
	-- Defaults are deliberately marked unsaveable until the real profile lands,
	-- so an autosave or a quick disconnect in that window cannot write an empty
	-- bank over a full one.
	local starting = Save.blank()
	starting.saveable = false
	addPilot(player, starting)

	task.spawn(function()
		local profile = Save.load(player)

		-- They can leave during a load, especially a retrying one.
		local pilot = pilots[player]
		if not pilot or player.Parent == nil then
			return
		end

		applyProfile(pilot, profile)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	removePilot(player)
	task.defer(refreshProbeFilter)
end)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

--------------------------------------------------------------------------------
-- Writing progress back
--------------------------------------------------------------------------------

-- A snapshot, because every save yields on the DataStore and a player can leave
-- while one is in flight. Walking `pilots` itself across a yield is iteration
-- over a table that is being mutated underneath you, which in Lua is not a bug
-- that shows up reliably -- it is a bug that shows up once, in production, with
-- somebody's progress attached.
local function currentPilots(): { Pilot }
	local list: { Pilot } = {}
	for _, pilot in pilots do
		table.insert(list, pilot)
	end
	return list
end

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, pilot in currentPilots() do
			-- They may have left since the snapshot was taken; PlayerRemoving has
			-- already saved them in that case.
			if pilots[pilot.player] then
				savePilot(pilot)
				-- Spread the writes out rather than firing one per player in a
				-- single frame, which is the quickest way to hit the budget.
				task.wait(1)
			end
		end
	end
end)

-- Roblox gives a closing server a short grace period to finish its writes, and
-- only if something is actually blocking here.
game:BindToClose(function()
	local pending = 0

	for _, pilot in currentPilots() do
		if pilot.saveable then
			pending += 1
			task.spawn(function()
				savePilot(pilot)
				pending -= 1
			end)
		end
	end

	-- Nothing to wait for when no one had a saveable session, which is the usual
	-- case in Studio and keeps stopping a playtest instant.
	local deadline = os.clock() + 20
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local function readAxis(value: any): number
	if type(value) ~= "number" then
		return 0
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.clamp(value, -1, 1)
end

inputRemote.OnServerEvent:Connect(function(player, payload)
	local pilot = pilots[player]
	if not pilot or type(payload) ~= "table" then
		return
	end

	-- Carried on the input remote rather than one of its own, because a new
	-- RemoteEvent means a new instance in default.project.json, and that reaches
	-- Studio only when rojo serve is restarted. This needs no restart at all.
	if type(payload.mode) == "string" then
		setMode(pilot, payload.mode)
		return
	end

	if payload.reset == true then
		local now = os.clock()
		if pilot.controller.crashed or now - pilot.lastReset < PlaneConfig.ResetCooldown then
			return
		end
		pilot.lastReset = now
		pilot.controller:reset()

		-- Nothing else to do. Rebuilding parks a new aeroplane on the runway and
		-- seats the pilot in it, and Seat:Sit teleports the character into the
		-- seat, so being put back at the runway falls out of being re-seated.
		--
		-- There used to be a follow-up that wrote to HumanoidRootPart if the
		-- seating looked like it had not taken. It regularly ran while the pilot
		-- was already seated and dragged them straight back out again, which is
		-- what made R look like it did nothing. supervise() now covers the case
		-- it was there for, from outside the seat rather than against it.
		return
	end

	pilot.controller:setInput(
		readAxis(payload.throttle),
		readAxis(payload.pitch),
		readAxis(payload.roll),
		readAxis(payload.yaw)
	)
end)

--------------------------------------------------------------------------------
-- Purchases
--------------------------------------------------------------------------------

buyRemote.OnServerEvent:Connect(function(player, payload)
	local pilot = pilots[player]
	if not pilot or type(payload) ~= "table" or type(payload.id) ~= "string" then
		return
	end

	-- The hangar is a place, not a menu. Checked here and not only in the UI,
	-- because the UI is the client's and the client is not to be trusted.
	if not pilot.controller:isNearSpawn() then
		eventRemote:FireClient(player, { kind = "denied", reason = "Return to the runway first" })
		return
	end

	local points = player:GetAttribute("Points") or 0

	if payload.kind == "plane" then
		local plane = UpgradeConfig.findPlane(payload.id)
		if not plane then
			return
		end

		local owned = ownedSet(player)
		if not owned[plane.id] then
			if points < plane.cost then
				eventRemote:FireClient(player, { kind = "denied", reason = "Not enough points" })
				return
			end
			player:SetAttribute("Points", points - plane.cost)
			owned[plane.id] = true
			writeOwned(player, owned)
		end

		equipPlane(pilot, plane.id)
		-- Spending is the one thing worth writing down straight away: it is the
		-- change a player would be angriest to lose, and it is rare enough that
		-- saving on every one costs nothing.
		task.spawn(savePilot, pilot)
		eventRemote:FireClient(player, { kind = "bought", name = plane.name })
		return
	end

	if payload.kind == "upgrade" then
		local upgrade = UpgradeConfig.findUpgrade(payload.id)
		if not upgrade then
			return
		end

		local level = pilot.levels[upgrade.id] or 0
		local cost = UpgradeConfig.upgradeCost(upgrade, level)
		if not cost then
			return
		end

		if points < cost then
			eventRemote:FireClient(player, { kind = "denied", reason = "Not enough points" })
			return
		end

		player:SetAttribute("Points", points - cost)
		pilot.levels[upgrade.id] = level + 1
		refreshStats(pilot)

		-- A bigger tank is no use if it arrives empty and you are already at
		-- the runway, so buying at the pad tops you up.
		pilot.controller:refuel()
		task.spawn(savePilot, pilot)

		eventRemote:FireClient(player, {
			kind = "bought",
			name = `{upgrade.name} {level + 1}`,
		})
	end
end)

--------------------------------------------------------------------------------
-- Dev panel
--
-- Re-authorised on every action. The client is told whether it is a developer
-- so it knows whether to draw the panel, and that answer is worth nothing here:
-- a client can fire this remote whatever it was told.
--------------------------------------------------------------------------------

local function grantAllPlanes(player: Player)
	local owned: { [string]: boolean } = {}
	for _, plane in UpgradeConfig.Planes do
		owned[plane.id] = true
	end
	writeOwned(player, owned)
end

devRemote.OnServerEvent:Connect(function(player, payload)
	if not DevConfig.isDeveloper(player) then
		warn(`[Main] refused a dev action from {player.Name}`)
		return
	end

	local pilot = pilots[player]
	if not pilot or type(payload) ~= "table" then
		return
	end

	local action = payload.action

	if action == "points" then
		player:SetAttribute("Points", (player:GetAttribute("Points") or 0) + DevConfig.PointsGrant)
	elseif action == "unlockAll" then
		grantAllPlanes(player)
		for _, upgrade in UpgradeConfig.Upgrades do
			pilot.levels[upgrade.id] = upgrade.levels
		end
		refreshStats(pilot)
		pilot.controller:refuel()
	elseif action == "maxUpgrades" then
		for _, upgrade in UpgradeConfig.Upgrades do
			pilot.levels[upgrade.id] = upgrade.levels
		end
		refreshStats(pilot)
		pilot.controller:refuel()
	elseif action == "unlockPlanes" then
		grantAllPlanes(player)
	elseif action == "setPlane" and type(payload.id) == "string" then
		-- No purchase and no runway check: the point of the panel is to skip
		-- exactly those.
		grantAllPlanes(player)
		equipPlane(pilot, payload.id)
	elseif action == "refuel" then
		pilot.controller:refuel()
	elseif action == "invincible" then
		pilot.controller.invincible = not pilot.controller.invincible
		player:SetAttribute("Invincible", pilot.controller.invincible)
	elseif action == "skipGate" then
		-- Drop in on the approach to the active gate, lined up and at speed.
		local gate = pilot.gates[pilot.activeIndex]
		if gate then
			local approach = gate.center - gate.normal * 420
			pilot.controller:placeAt(
				CFrame.lookAt(approach, gate.center),
				pilot.controller.maxSpeed * 0.7
			)
			pilot.lastPosition = pilot.controller.fuselage.Position
		end
	elseif action == "newCourse" then
		pilot.lap += 1
		task.spawn(buildCourse, pilot)
	elseif action == "wipe" then
		player:SetAttribute("Points", 0)
		player:SetAttribute("Best", 0)
		player:SetAttribute("OwnedPlanes", "trainer")
		pilot.levels = {}
		equipPlane(pilot, "trainer")
	else
		return
	end

	-- Dev actions are saved like any other change, so testing the ramp from zero
	-- is not undone by a rejoin.
	task.spawn(savePilot, pilot)
	eventRemote:FireClient(player, { kind = "dev", action = tostring(action) })
end)

--------------------------------------------------------------------------------
-- Gate detection and scoring
--------------------------------------------------------------------------------

local function completeLap(pilot: Pilot)
	local player = pilot.player
	local bonus = RingConfig.LapBonus

	player:SetAttribute("Score", (player:GetAttribute("Score") or 0) + bonus)
	player:SetAttribute("Points", (player:GetAttribute("Points") or 0) + bonus)

	local score = player:GetAttribute("Score") or 0
	if score > (player:GetAttribute("Best") or 0) then
		player:SetAttribute("Best", score)
	end

	pilot.lap += 1
	eventRemote:FireClient(player, { kind = "complete", lap = pilot.lap, bonus = bonus })

	task.spawn(buildCourse, pilot)
end

local function passGate(pilot: Pilot, gate: CourseBuilder.Gate, radial: number)
	local player = pilot.player
	local accuracy = 1 - math.clamp(radial / gate.radius, 0, 1)

	pilot.combo += 1
	local multiplier = math.min(
		1 + (pilot.combo - 1) * RingConfig.ComboStep,
		RingConfig.MaxComboMultiplier
	)

	local difficulty = RingConfig.StartRadius / gate.radius
	local points = math.floor(
		(RingConfig.BasePoints * difficulty + RingConfig.CenterBonus * accuracy * accuracy) * multiplier
	)

	local score = (player:GetAttribute("Score") or 0) + points
	player:SetAttribute("Score", score)
	-- Banked separately, and deliberately not wiped by a crash.
	player:SetAttribute("Points", (player:GetAttribute("Points") or 0) + points)
	if score > (player:GetAttribute("Best") or 0) then
		player:SetAttribute("Best", score)
	end
	player:SetAttribute("Combo", pilot.combo)
	player:SetAttribute("Multiplier", multiplier)

	pilot.activeIndex += 1
	player:SetAttribute("ActiveGate", pilot.activeIndex)

	eventRemote:FireClient(player, {
		kind = "pass",
		index = gate.index,
		points = points,
		accuracy = accuracy,
		combo = pilot.combo,
	})

	if pilot.activeIndex > #pilot.gates then
		completeLap(pilot)
	end
end

local function missGate(pilot: Pilot, gate: CourseBuilder.Gate)
	local player = pilot.player
	pilot.combo = 0
	player:SetAttribute("Combo", 0)
	player:SetAttribute("Multiplier", 1)

	pilot.activeIndex += 1
	player:SetAttribute("ActiveGate", pilot.activeIndex)
	eventRemote:FireClient(player, { kind = "miss", index = gate.index })

	if pilot.activeIndex > #pilot.gates then
		completeLap(pilot)
	end
end

local function checkGate(pilot: Pilot)
	local controller = pilot.controller
	local fuselage = controller.fuselage

	if not fuselage or controller.crashed then
		if fuselage then
			pilot.lastPosition = fuselage.Position
		end
		return
	end

	-- A rebuilt aeroplane appears somewhere else entirely. The controller flags
	-- it exactly rather than leaving detection to guess from a distance
	-- threshold, which a fast aircraft could exceed legitimately.
	if controller.teleported then
		controller.teleported = false
		pilot.lastPosition = fuselage.Position
		return
	end

	local current = fuselage.Position

	for _ = 1, MAX_GATES_PER_FRAME do
		local gate = pilot.gates[pilot.activeIndex]
		if not gate then
			break
		end

		local before = (pilot.lastPosition - gate.center):Dot(gate.normal)
		local after = (current - gate.center):Dot(gate.normal)

		if before >= 0 then
			-- Already past this gate's plane the moment it became active, which
			-- happens when the previous gate is passed while the next one is
			-- alongside or behind. It can never be crossed forwards again, so
			-- without this the course sticks on it and no further gate scores.
			-- This is the "rings stop working" bug, and faster aircraft hit it
			-- far more often because they cover more ground between gates.
			missGate(pilot, gate)
		elseif after >= 0 then
			local span = before - after
			local t = if math.abs(span) > 1e-6 then before / span else 0
			local crossing = pilot.lastPosition:Lerp(current, t)

			local offset = crossing - gate.center
			local radial = (offset - gate.normal * offset:Dot(gate.normal)).Magnitude

			if radial <= gate.radius then
				passGate(pilot, gate, radial)
			elseif radial <= gate.radius * RingConfig.MissRadiusFactor then
				missGate(pilot, gate)
			else
				break
			end
		else
			-- Not there yet.
			break
		end
	end

	pilot.lastPosition = current
end

local sinceSupervise = 0

RunService.Heartbeat:Connect(function(dt)
	for _, pilot in pilots do
		pilot.controller:step(dt)
		checkGate(pilot)
	end

	-- The watchdog. Every way a pilot could previously end up permanently on
	-- foot -- somebody else in their seat, a respawn that outlasted the seating
	-- retries, an airframe deleted by the engine -- is a state this notices and
	-- undoes, rather than something the code has to have predicted.
	sinceSupervise += dt
	if sinceSupervise >= SUPERVISE_INTERVAL then
		sinceSupervise = 0
		for _, pilot in pilots do
			pilot.controller:supervise()
		end
	end
end)
