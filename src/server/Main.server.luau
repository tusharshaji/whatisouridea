--!strict

-- The server. One aircraft, one course and one scoreboard per pilot.
--
-- Everything used to be global: one plane in the world, one set of rings, one
-- score. That made a second player a spectator who happened to also collect
-- everybody else's gates. Every piece of state here now hangs off a pilot record
-- instead, and the rings are not even instances -- each client draws its own
-- course from data sent only to it, so nobody can see or score anyone else's.
--
-- Gate detection is a plane crossing rather than a Touched event. At 220
-- studs/sec the aircraft moves nearly four studs between frames and a gate is
-- three thick, so touching one is a coin flip. Testing which side of the gate's
-- plane it was on last frame and which side it is on now cannot be tunnelled,
-- and gives the accuracy figure for scoring in the same step.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PlaneConfig = require(ReplicatedStorage.Shared.PlaneConfig)
local RingConfig = require(ReplicatedStorage.Shared.RingConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)
local ensure = require(ReplicatedStorage.Shared.Ensure)

local CourseBuilder = require(script.Parent.CourseBuilder)
local PlaneController = require(script.Parent.PlaneController)
local TerrainSurvey = require(script.Parent.TerrainSurvey)

local COLLISION_GROUP = "Planes"
local TELEPORT_JUMP = 150

--------------------------------------------------------------------------------
-- World setup
--------------------------------------------------------------------------------

-- The aeroplane is authored in Workspace so it can be seen and edited in Studio,
-- and becomes a template the moment the game runs. Every pilot flies a clone.
local template = Workspace:WaitForChild("Airplane") :: Model
local basePad = template:GetPivot()
template.Parent = ServerStorage

local planesFolder = Instance.new("Folder")
planesFolder.Name = "Planes"
planesFolder.Parent = Workspace

-- Aircraft do not collide with each other. Without this one pilot can swat
-- another off the course, and two planes sharing a runway slot explode.
pcall(function()
	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
end)
PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)

local remotes = ensure(ReplicatedStorage, "Remotes", "Folder")
local inputRemote = ensure(remotes, "PlaneInput", "RemoteEvent") :: RemoteEvent
local courseRemote = ensure(remotes, "CourseData", "RemoteEvent") :: RemoteEvent
local eventRemote = ensure(remotes, "GameEvent", "RemoteEvent") :: RemoteEvent
local buyRemote = ensure(remotes, "BuyUpgrade", "RemoteEvent") :: RemoteEvent

-- One filter for every raycast the game makes: no aircraft and no character
-- should ever read as terrain. The pilot's own character is welded into the seat
-- and sits directly in the path of the crash sweep, so without this an aeroplane
-- crashes into its own pilot the instant it leaves the ground.
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

-- Where to lay courses.
--
-- A measured override wins outright. Terrain.MaxExtents sounds like the right
-- source and is not: on a generated map it can report a region far larger than
-- anything built, so the survey spreads its samples across mostly nothing and
-- the course gets planned on a box that is not even centred on the island.
local function mapBounds(): (number, number, number, number)
	local override = RingConfig.MapOverride
	if override then
		return override.minX, override.maxX, override.minZ, override.maxZ
	end

	local extents = Workspace.Terrain.MaxExtents
	local minX, maxX = extents.Min.X * 4, extents.Max.X * 4
	local minZ, maxZ = extents.Min.Z * 4, extents.Max.Z * 4
	local width = maxX - minX

	if width < 512 or width > 60000 then
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

-- Runway slots: three abreast, then further back down the tarmac. The runway is
-- 44 wide and 290 long, so this keeps a good few pilots on the concrete.
local function padForSlot(slot: number): CFrame
	local across = (slot % 3 - 1) * 14
	local along = -math.floor(slot / 3) * 52
	return basePad * CFrame.new(across, 0, along)
end

local function publishStats(pilot: Pilot)
	local stats = UpgradeConfig.statsFor(pilot.planeId, pilot.levels)
	pilot.controller:applyStats(stats)

	local player = pilot.player
	player:SetAttribute("PlaneId", pilot.planeId)
	for _, upgrade in UpgradeConfig.Upgrades do
		player:SetAttribute("Level_" .. upgrade.id, pilot.levels[upgrade.id] or 0)
	end
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
	-- Courses are laid from the terrain survey, so a pilot who joins before it
	-- has finished simply waits for it rather than getting a flat one.
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
	pilot.lastPosition = pilot.controller.fuselage.Position
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

local function addPilot(player: Player)
	local slot = claimSlot()
	local controller = PlaneController.new(
		player,
		template,
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
		planeId = "trainer",
		levels = {},
	}
	pilots[player] = pilot

	player:SetAttribute("Score", 0)
	player:SetAttribute("Best", 0)
	player:SetAttribute("Points", 0)
	player:SetAttribute("Combo", 0)
	player:SetAttribute("Multiplier", 1)
	player:SetAttribute("Crashed", false)
	player:SetAttribute("OwnedPlanes", "trainer")

	publishStats(pilot)

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

	pilot.controller:destroy()
	usedSlots[pilot.slot] = nil
	pilots[player] = nil
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		refreshProbeFilter()
		local pilot = pilots[player]
		if pilot then
			-- Put them back in the cockpit after a respawn on foot.
			task.defer(function()
				pilot.controller:seatPilot()
			end)
		end
	end)

	addPilot(player)
	refreshProbeFilter()
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	removePilot(player)
	task.defer(refreshProbeFilter)
end)

-- Anyone already here when the script starts, which in a Studio playtest is the
-- local player. They need the same CharacterAdded hook as a late joiner.
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

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

	if payload.reset == true then
		-- Rate limited, and refused mid-crash: without both, holding the key
		-- rebuilds the aeroplane every frame.
		local now = os.clock()
		if not pilot.controller.crashed and now - pilot.lastReset >= PlaneConfig.ResetCooldown then
			pilot.lastReset = now
			pilot.controller:reset()
		end
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

local function ownedPlanes(player: Player): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	for id in string.gmatch(player:GetAttribute("OwnedPlanes") or "trainer", "[^,]+") do
		owned[id] = true
	end
	return owned
end

buyRemote.OnServerEvent:Connect(function(player, payload)
	local pilot = pilots[player]
	if not pilot or type(payload) ~= "table" or type(payload.id) ~= "string" then
		return
	end

	local points = player:GetAttribute("Points") or 0

	if payload.kind == "plane" then
		local plane = UpgradeConfig.findPlane(payload.id)
		if not plane then
			return
		end

		local owned = ownedPlanes(player)
		if not owned[plane.id] then
			if points < plane.cost then
				eventRemote:FireClient(player, { kind = "denied", reason = "Not enough points" })
				return
			end
			player:SetAttribute("Points", points - plane.cost)
			owned[plane.id] = true

			local list = {}
			for id in owned do
				table.insert(list, id)
			end
			player:SetAttribute("OwnedPlanes", table.concat(list, ","))
		end

		pilot.planeId = plane.id
		publishStats(pilot)
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
		publishStats(pilot)
		eventRemote:FireClient(player, {
			kind = "bought",
			name = `{upgrade.name} {level + 1}`,
		})
	end
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
	-- Banked separately, and deliberately not wiped by a crash: an hour of
	-- flying should leave something behind even if the last run ended in a cliff.
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
	local gate = pilot.gates[pilot.activeIndex]
	local fuselage = pilot.controller.fuselage

	if not gate or not fuselage or pilot.controller.crashed then
		if fuselage then
			pilot.lastPosition = fuselage.Position
		end
		return
	end

	local current = fuselage.Position

	-- A respawn moves the aircraft further in one frame than flight ever could.
	if (current - pilot.lastPosition).Magnitude > TELEPORT_JUMP then
		pilot.lastPosition = current
		return
	end

	local before = (pilot.lastPosition - gate.center):Dot(gate.normal)
	local after = (current - gate.center):Dot(gate.normal)

	if before < 0 and after >= 0 then
		local span = before - after
		local t = if math.abs(span) > 1e-6 then before / span else 0
		local crossing = pilot.lastPosition:Lerp(current, t)

		local offset = crossing - gate.center
		local radial = (offset - gate.normal * offset:Dot(gate.normal)).Magnitude

		if radial <= gate.radius then
			passGate(pilot, gate, radial)
		elseif radial <= gate.radius * RingConfig.MissRadiusFactor then
			missGate(pilot, gate)
		end
	end

	pilot.lastPosition = current
end

RunService.Heartbeat:Connect(function(dt)
	for _, pilot in pilots do
		pilot.controller:step(dt)
		checkGate(pilot)
	end
end)
