--!strict

-- One aircraft, belonging to one pilot.
--
-- THE FLIGHT MODEL
--
-- The aircraft carries a full orientation CFrame. Controls rotate it about its
-- own axes -- pitch about its right, roll about its nose, yaw about its up --
-- and velocity then runs along wherever the nose ends up pointing.
--
-- This replaces a model that kept heading, bank and climb rate as three separate
-- scalars. That one was beautifully stable and fundamentally incapable of being
-- upside down: with "bank" as a number clamped to 45 degrees and height as a
-- climb rate rather than a direction, there was nowhere for a loop to live.
-- Pitch had to be clamped to a shallow cone because exceeding it had no meaning.
--
-- What the change costs is the old guarantee that a turn never lost altitude,
-- and the guarantee that the aircraft could not be pointed at the ground. Both
-- were load-bearing for "forgiving" and both had to go for aerobatics. What
-- keeps it flyable instead is a weak auto-level that gives up past 100 degrees
-- of bank, so it settles you when you are nearly upright and never fights you
-- when you are deliberately inverted.
--
-- Respawning throws the aeroplane away and builds a new one, which is why the
-- wreck can be scattered freely: nothing here has to be recoverable.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.PlaneConfig)
local PlaneModels = require(ReplicatedStorage.Shared.PlaneModels)

local ROTOR_PARTS: { [string]: boolean } = {
	RotorHub = true,
	RotorBladeA = true,
	RotorBladeB = true,
}

type SurfaceSpec = {
	name: string,
	channel: string,
	limit: number,
	sign: number,
	vertical: boolean,
}

local SURFACE_SPECS: { SurfaceSpec } = {
	{ name = "AileronL", channel = "roll", limit = Config.MaxAileronAngle, sign = 1, vertical = false },
	{ name = "AileronR", channel = "roll", limit = Config.MaxAileronAngle, sign = -1, vertical = false },
	{ name = "Elevator", channel = "pitch", limit = Config.MaxElevatorAngle, sign = -1, vertical = false },
	{ name = "Rudder", channel = "yaw", limit = Config.MaxRudderAngle, sign = 1, vertical = true },
}

local SURFACE_PARTS: { [string]: boolean } = {}
for _, spec in SURFACE_SPECS do
	SURFACE_PARTS[spec.name] = true
end

local PlaneController = {}
PlaneController.__index = PlaneController

-- Who is sitting in a seat, or nil. A Humanoid's Parent is only typed as an
-- Instance, so the cast is here once rather than at all three call sites.
local function playerOf(humanoid: Humanoid?): Player?
	local character = humanoid and humanoid.Parent
	if not character then
		return nil
	end
	return Players:GetPlayerFromCharacter(character :: Model)
end

local function approach(current: number, target: number, maxStep: number): number
	local delta = target - current
	if math.abs(delta) <= maxStep then
		return target
	end
	return current + (if delta > 0 then maxStep else -maxStep)
end

function PlaneController.new(
	player: Player,
	container: Instance,
	pad: CFrame,
	probe: RaycastParams,
	collisionGroup: string
)
	local self = setmetatable({}, PlaneController)

	self.player = player
	self.container = container
	self.pad = pad
	self.probe = probe
	self.collisionGroup = collisionGroup

	self.planeId = "trainer"
	self.stats = { speed = 1, handling = 1, climb = 1, fuel = 1, stability = 1 }
	self.crashed = false
	self.crashClearsAt = 0
	self.crashImmuneUntil = 0
	self.teleported = true
	self.publishClock = 0
	self.retired = false -- set when the pilot leaves, so the watchdog stops
	self.passenger = nil :: Player? -- whoever is riding in the back
	self.onCrash = nil :: (() -> ())?
	self.onReset = nil :: (() -> ())?

	self.controls = { throttle = 0, pitch = 0, roll = 0, yaw = 0 }

	self:applyStats(self.stats)
	self:build()
	return self
end

function PlaneController:applyStats(stats: { [string]: number })
	self.stats = stats

	local speed = stats.speed or 1
	local handling = stats.handling or 1
	local climb = stats.climb or 1

	self.maxSpeed = Config.MaxSpeed * speed
	self.minFlightSpeed = Config.MinFlightSpeed * speed
	self.pitchRate = Config.PitchRate * climb
	self.rollRate = Config.RollRate * handling
	self.yawRate = Config.YawRate * handling
	self.autoLevelRate = Config.AutoLevelRate * (stats.stability or 1)
	self.pitchSettleRate = Config.PitchSettleRate * (stats.stability or 1)
	self.fuelCapacity = Config.FuelCapacity * (stats.fuel or 1)

	-- Topping up rather than refilling: buying a bigger tank mid-flight should
	-- not be a free refuel, but it should not throw away what is in there.
	self.fuel = math.min(self.fuel or self.fuelCapacity, self.fuelCapacity)
end

function PlaneController:setPlane(planeId: string, color: Color3)
	self.planeId = planeId
	self.planeColor = color
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function PlaneController:build()
	local spec = PlaneModels.get(self.planeId, self.planeColor or Color3.fromRGB(225, 225, 235))

	local model = Instance.new("Model")
	model.Name = `Plane_{self.player.UserId}`

	local physics = PhysicalProperties.new(Config.AirframeDensity, 0.3, 0.2, 1, 1)
	local built: { [string]: BasePart } = {}
	local ordered: { BasePart } = {}

	for index, partSpec in spec.parts do
		local part = Instance.new("Part")
		part.Name = partSpec.name or `Part{index}`
		part.Size = partSpec.size
		part.Color = partSpec.color or Color3.fromRGB(220, 220, 225)
		part.Material = partSpec.material or Enum.Material.SmoothPlastic
		part.Transparency = partSpec.transparency or 0
		part.Anchored = true -- unanchored once everything is positioned
		part.CanCollide = true
		part.CustomPhysicalProperties = physics
		part.CollisionGroup = self.collisionGroup
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth

		if partSpec.shape then
			part.Shape = partSpec.shape
		end

		part.Parent = model
		built[part.Name] = part
		ordered[index] = part
	end

	local fuselage = built.Fuselage
	if not fuselage then
		warn(`[PlaneController] spec for "{self.planeId}" has no Fuselage`)
		model:Destroy()
		return
	end

	-- The seats. Built rather than specified, because every aircraft needs the
	-- same two and they always go in the same place relative to the canopy.
	local seat = Instance.new("VehicleSeat")
	seat.Name = "PilotSeat"
	seat.Size = Vector3.new(2.4, 0.6, 2.4)
	seat.Transparency = 1
	seat.Anchored = true
	seat.CanCollide = false
	seat.CollisionGroup = self.collisionGroup
	seat.Disabled = false
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = model
	built.PilotSeat = seat

	-- The back seat. A plain Seat, not a VehicleSeat: a second VehicleSeat would
	-- publish its own steering inputs and there is only one aeroplane to steer.
	local rear = Instance.new("Seat")
	rear.Name = "PassengerSeat"
	rear.Size = Vector3.new(2.4, 0.6, 2.4)
	rear.Transparency = 1
	rear.Anchored = true
	rear.CanCollide = false
	rear.CollisionGroup = self.collisionGroup
	rear.Parent = model
	built.PassengerSeat = rear

	local canopy = built.Canopy
	local seatOffset = if canopy then CFrame.new(0, -0.4, 0) else CFrame.new(0, 1.2, 0)

	-- Place everything relative to the pad, then release it.
	local root = self.pad
	for index, partSpec in spec.parts do
		ordered[index].CFrame = root * partSpec.offset
	end
	seat.CFrame = (canopy and canopy.CFrame or fuselage.CFrame) * seatOffset
	-- Behind the pilot. +Z is aft, since the nose points down -Z.
	rear.CFrame = seat.CFrame * CFrame.new(0, 0, 3)

	self.model = model
	self.fuselage = fuselage
	self.seat = seat
	self.rearSeat = rear
	self.hub = built.RotorHub

	--------------------------------------------------------------------------
	-- Attachments and constraints
	--------------------------------------------------------------------------
	local thrustPoint = Instance.new("Attachment")
	thrustPoint.Name = "ThrustPoint"
	thrustPoint.Parent = fuselage

	local aeroPoint = Instance.new("Attachment")
	aeroPoint.Name = "AeroPoint"
	aeroPoint.Parent = fuselage

	local flight = Instance.new("LinearVelocity")
	flight.Name = "Flight"
	flight.Attachment0 = thrustPoint
	flight.RelativeTo = Enum.ActuatorRelativeTo.World
	flight.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	flight.VectorVelocity = Vector3.zero
	flight.Parent = fuselage

	local attitude = Instance.new("AlignOrientation")
	attitude.Name = "Attitude"
	attitude.Attachment0 = aeroPoint
	attitude.Mode = Enum.OrientationAlignmentMode.OneAttachment
	attitude.Responsiveness = Config.OrientationResponse
	attitude.Parent = fuselage

	self.flight = flight
	self.attitude = attitude

	--------------------------------------------------------------------------
	-- Joints
	--------------------------------------------------------------------------
	local joints: { Instance } = {}
	local function weld(anchor: BasePart, part: BasePart)
		local constraint = Instance.new("WeldConstraint")
		constraint.Part0 = anchor
		constraint.Part1 = part
		constraint.Parent = anchor
		table.insert(joints, constraint)
	end

	local hub = self.hub
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if hub and ROTOR_PARTS[part.Name] then
				if part ~= hub then
					weld(hub, part)
				end
			elseif not SURFACE_PARTS[part.Name] and part ~= fuselage then
				weld(fuselage, part)
			end
		end
	end

	if hub then
		local mount = Instance.new("Attachment")
		mount.Name = "RotorMount"
		mount.CFrame = fuselage.CFrame:ToObjectSpace(hub.CFrame)
		mount.Parent = fuselage

		local axis = Instance.new("Attachment")
		axis.Name = "HubAxis"
		axis.Parent = hub

		local rotorMotor = Instance.new("HingeConstraint")
		rotorMotor.Name = "RotorMotor"
		rotorMotor.ActuatorType = Enum.ActuatorType.Motor
		rotorMotor.AngularSpeed = 0
		rotorMotor.Attachment0 = mount
		rotorMotor.Attachment1 = axis
		rotorMotor.Parent = fuselage
		self.rotorMotor = rotorMotor
	else
		self.rotorMotor = nil
	end

	-- Hinge each control surface on its leading edge so it pivots like a flap.
	local surfaces: { { motor: Motor6D, base: CFrame, spec: SurfaceSpec } } = {}
	for _, surfaceSpec in SURFACE_SPECS do
		local part = built[surfaceSpec.name]
		if part then
			local hinge = part.CFrame * CFrame.new(0, 0, -part.Size.Z / 2)

			local motor = Instance.new("Motor6D")
			motor.Name = surfaceSpec.name .. "Hinge"
			motor.Part0 = fuselage
			motor.Part1 = part
			motor.C0 = fuselage.CFrame:ToObjectSpace(hinge)
			motor.C1 = part.CFrame:ToObjectSpace(hinge)
			motor.Parent = fuselage

			table.insert(surfaces, { motor = motor, base = motor.C0, spec = surfaceSpec })
			table.insert(joints, motor)
		end
	end

	self.joints = joints
	self.surfaces = surfaces

	--------------------------------------------------------------------------
	-- Exhausts
	--------------------------------------------------------------------------
	self.thrusters = {}
	for index, offset in spec.thrusters do
		local nozzle = Instance.new("Part")
		nozzle.Name = `Thruster{index}`
		nozzle.Shape = Enum.PartType.Cylinder
		nozzle.Size = Vector3.new(spec.thrusterSize, spec.thrusterSize, spec.thrusterSize * 1.4)
		-- A cylinder's length runs along X, so it has to be turned to point aft.
		nozzle.CFrame = root * offset * CFrame.Angles(0, math.rad(90), 0)
		nozzle.Color = Color3.fromRGB(35, 35, 40)
		nozzle.Material = Enum.Material.Metal
		nozzle.Anchored = true
		nozzle.CanCollide = false
		nozzle.CollisionGroup = self.collisionGroup
		nozzle.CustomPhysicalProperties = physics
		nozzle.Parent = model

		local flame = Instance.new("Fire")
		flame.Heat = Config.ThrusterHeat
		flame.Size = Config.ThrusterFlameIdle
		flame.Color = spec.trailColor
		flame.SecondaryColor = Color3.fromRGB(255, 190, 90)
		flame.Enabled = false
		flame.Parent = nozzle

		local glow = Instance.new("PointLight")
		glow.Color = spec.trailColor
		glow.Range = 10
		glow.Brightness = 0
		glow.Parent = nozzle

		weld(fuselage, nozzle)
		table.insert(self.thrusters, { part = nozzle, fire = flame, light = glow })
	end

	--------------------------------------------------------------------------
	-- Sit it on the ground and let go
	--------------------------------------------------------------------------
	model.PrimaryPart = fuselage
	model.Parent = self.container

	local boundingCFrame, boundingSize = model:GetBoundingBox()
	self.groundClearance = fuselage.Position.Y - (boundingCFrame.Position.Y - boundingSize.Y / 2)

	local padGround = self:groundHeightAt(self.pad.Position)
	local resting = if padGround then padGround + self.groundClearance else self.pad.Position.Y
	local parked = CFrame.new(self.pad.Position.X, resting, self.pad.Position.Z)
		* (self.pad - self.pad.Position)
	model:PivotTo(parked)

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	self.padFuselage = fuselage.CFrame
	self.spawnCFrame = parked

	local mass = 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			mass += part.Mass
		end
	end

	flight.MaxForce = mass * Config.ForceHeadroom
	attitude.MaxTorque = mass * Config.ForceHeadroom
	if self.rotorMotor then
		self.rotorMotor.MotorMaxTorque = mass * 20
	end

	-- Flight state.
	self.orientation = CFrame.Angles(0, select(2, parked:ToEulerAnglesYXZ()), 0)
	self.throttle = 0
	self.speed = 0
	self.rotorSpeed = 0
	self.deflection = { roll = 0, pitch = 0, yaw = 0 }
	self.lastPosition = fuselage.Position
	self.fuel = self.fuelCapacity
	self.engineOut = false

	self.crashed = false
	self.crashImmuneUntil = os.clock() + Config.CrashGracePeriod
	self.teleported = true

	-- Whoever is in the front seat, and whether the pilot has chosen to be out of
	-- it. A new airframe starts with nobody in it and no such decision made.
	self.seated = nil :: Player?
	self.dismounted = false

	self:wireSeats()
	self:claimOwnership()
	self:seatPilot()
end

--------------------------------------------------------------------------------
-- Seats
--
-- Two of them, and neither can be left to look after itself. A Seat takes
-- whoever touches it, which on a shared runway means somebody else's character
-- wandering into your cockpit and taking the controls out of your hands -- your
-- aeroplane then flies on your inputs with a stranger in it, and your own
-- attempt to get back in is refused because the seat is full. That is the
-- multiplayer half of "R does nothing".
--------------------------------------------------------------------------------

function PlaneController:wireSeats()
	local seat = self.seat
	local rear = self.rearSeat
	if not seat or not rear then
		return
	end

	-- Boarding is a prompt, not a walk-in. Both seats sit inside the airframe,
	-- and the fuselage is solid, so there is no way to touch one on foot.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RidePrompt"
	prompt.ActionText = "Ride along"
	prompt.ObjectText = `{self.player.DisplayName}'s aircraft`
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	-- Not the default E: that is the rudder, so a pilot with an empty back seat
	-- would have a prompt on screen for their own aeroplane and set it off every
	-- time they yawed right.
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Parent = rear
	self.ridePrompt = prompt

	prompt.Triggered:Connect(function(who: Player)
		local character = who.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or self.crashed then
			return
		end

		-- Boarding your own aeroplane means flying it, whichever seat you asked
		-- for. Sitting behind yourself would just park it.
		if who == self.player then
			if seat.Occupant == nil then
				self.dismounted = false
				seat:Sit(humanoid)
			end
			return
		end

		if rear.Occupant == nil then
			rear:Sit(humanoid)
		end
	end)

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		-- Seats from a previous airframe still fire this as they are destroyed,
		-- and acting on one would mean a rebuild reading as somebody getting out.
		if self.seat ~= seat then
			return
		end

		local occupant = seat.Occupant
		local who = playerOf(occupant)
		local left = self.seated
		self.seated = who

		-- Anyone who is not the owner is put back out of the pilot's seat.
		if occupant then
			if who ~= self.player then
				occupant.Sit = false
			end
			return
		end

		-- Empty now. Only the owner standing up under their own power counts as
		-- getting out: being ejected is somebody else leaving, and dying is
		-- answered by the respawn putting them back.
		if left ~= self.player then
			return
		end

		local character = self.player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			self.dismounted = true
		end
	end)

	rear:GetPropertyChangedSignal("Occupant"):Connect(function()
		if self.rearSeat ~= rear then
			return
		end

		local occupant = rear.Occupant
		if not occupant then
			self.passenger = nil
			return
		end

		local sitting = playerOf(occupant)
		if sitting == self.player then
			-- The owner ended up in the back. Move them forward.
			occupant.Sit = false
			return
		end

		self.passenger = sitting
	end)
end

-- Keep whoever was riding along across a rebuild. Bounded, because after a crash
-- they are dead too and have to respawn before there is anything to seat.
function PlaneController:restorePassenger(who: Player)
	task.spawn(function()
		for _ = 1, 30 do
			local rear = self.rearSeat
			if self.retired or not rear or not rear.Parent then
				return
			end
			if who.Parent == nil then
				return -- they left
			end
			if rear.Occupant ~= nil then
				return -- someone got there first
			end

			local character = who.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and character.PrimaryPart and humanoid.SeatPart == nil then
				rear:Sit(humanoid)
				return
			end

			task.wait(0.25)
		end
	end)
end

-- Called a few times a second by the server loop. Idempotent, and the reason a
-- pilot can no longer end up permanently on foot: whatever went wrong -- a seat
-- taken by somebody else, a respawn that outlasted the retry window, an airframe
-- deleted out from under the controller -- the next tick notices and fixes it.
function PlaneController:supervise()
	if self.retired then
		return
	end

	-- The airframe can vanish without anything here asking it to: parts below
	-- Workspace.FallenPartsDestroyHeight are deleted by the engine, and a plane
	-- flown into a deep valley qualifies. Rebuild rather than sitting dead.
	local model = self.model
	local fuselage = self.fuselage
	if not model or not model.Parent or not fuselage or not fuselage.Parent then
		-- Rate-limited, so a build that cannot succeed complains once every couple
		-- of seconds instead of thrashing the server at the watchdog's tick rate.
		local now = os.clock()
		if now - (self.lastRebuild or 0) < 2 then
			return
		end
		self.lastRebuild = now

		warn(`[PlaneController] {self.player.Name}'s airframe went missing; rebuilding`)
		self:reset()
		return
	end

	if self.crashed then
		return
	end

	-- You can board an aeroplane that is parked, and not one that is taxiing or
	-- flying. This also keeps the prompt off the pilot's own screen for all but
	-- the moment they are sat still on the runway.
	local rear = self.rearSeat
	if self.ridePrompt and rear then
		self.ridePrompt.Enabled = rear.Occupant == nil and (self.speed or 0) < 2
	end

	local seat = self.seat
	if not seat then
		return
	end

	local occupant = seat.Occupant
	if occupant then
		-- The Occupant listener normally catches this the instant it happens;
		-- this is the belt to its braces.
		if playerOf(occupant) ~= self.player then
			occupant.Sit = false
		end
		return
	end

	local character = self.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not character.PrimaryPart then
		return
	end

	-- Riding in somebody else's aeroplane is a choice, not a fault. Only an
	-- unseated pilot gets put back in their own.
	if humanoid.SeatPart ~= nil then
		return
	end

	-- So is getting out and standing on the runway. The watchdog is here to undo
	-- accidents, not decisions, and without this it put the pilot straight back
	-- in the cockpit every time they jumped out. F or R gets them back in.
	if self.dismounted then
		return
	end

	seat:Sit(humanoid)
end

function PlaneController:claimOwnership()
	if self.fuselage and self.fuselage:IsDescendantOf(Workspace) then
		self.fuselage:SetNetworkOwner(nil)
		if self.hub then
			self.hub:SetNetworkOwner(nil)
		end
	end
end

-- Put the pilot in the cockpit, promptly.
--
-- This is the fast path only. It retries for a few seconds because after a crash
-- the pilot is dead and the aeroplane is rebuilt before the character has
-- finished respawning, so a single Sit call lands on a corpse. If even that
-- window is missed -- a slow respawn, a seat briefly held by somebody else --
-- supervise() picks it up on its next tick, so nothing here has to be exhaustive.
function PlaneController:seatPilot()
	-- An explicit request to be in the cockpit, so it clears any earlier decision
	-- to be out of it. The two callers are a fresh airframe and a respawned
	-- character, and both should end with the pilot flying.
	self.dismounted = false

	self.seatToken = (self.seatToken or 0) + 1
	local token = self.seatToken

	task.spawn(function()
		for _ = 1, 25 do
			-- A newer attempt, or a newer aeroplane, cancels this one.
			if self.seatToken ~= token or not self.model or not self.model.Parent then
				return
			end

			local seat = self.seat
			local character = self.player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")

			if seat and humanoid and humanoid.Health > 0 and character.PrimaryPart then
				if seat.Occupant == humanoid then
					self:claimOwnership()
					return
				end
				if seat.Occupant == nil then
					seat:Sit(humanoid)
				end
			end

			task.wait(0.2)
		end
	end)
end

function PlaneController:groundHeightAt(position: Vector3): number?
	local hit = Workspace:Raycast(
		position + Vector3.new(0, 5, 0),
		Vector3.new(0, -Config.GroundProbeDepth, 0),
		self.probe
	)
	return if hit then hit.Position.Y else nil
end

function PlaneController:setInput(throttle: number, pitch: number, roll: number, yaw: number)
	self.controls.throttle = throttle
	self.controls.pitch = pitch
	self.controls.roll = roll
	self.controls.yaw = yaw
end

function PlaneController:isNearSpawn(): boolean
	if not self.fuselage then
		return false
	end
	local here = self.fuselage.Position
	local pad = self.spawnCFrame.Position
	return (Vector3.new(here.X, 0, here.Z) - Vector3.new(pad.X, 0, pad.Z)).Magnitude
		<= Config.SpawnRadius
end

function PlaneController:refuel()
	self.fuel = self.fuelCapacity
	self.engineOut = false
end

-- Drop the aircraft somewhere else, already flying. Used by the dev panel to
-- skip to a gate without flying the whole course to reach it.
--
-- `teleported` matters: gate detection works by comparing where the aircraft
-- was against where it is, and a jump of a few thousand studs would read as
-- having crossed everything in between.
function PlaneController:placeAt(target: CFrame, speed: number)
	if not self.model or not self.fuselage then
		return
	end

	self.orientation = target - target.Position
	self.speed = speed
	self.throttle = math.clamp(speed / math.max(self.maxSpeed, 1), 0, 1)

	self.model:PivotTo(target * self.fuselage.CFrame:ToObjectSpace(self.model:GetPivot()))
	self.fuselage.AssemblyLinearVelocity = self.orientation.LookVector * speed
	self.fuselage.AssemblyAngularVelocity = Vector3.zero

	self.lastPosition = self.fuselage.Position
	self.teleported = true
	self.crashImmuneUntil = os.clock() + Config.CrashGracePeriod
end

--------------------------------------------------------------------------------
-- Crashing
--------------------------------------------------------------------------------

function PlaneController:crash()
	if self.crashed or not self.model then
		return
	end

	self.crashed = true
	self.crashClearsAt = os.clock() + Config.CrashRespawnDelay

	self.flight.Enabled = false
	self.attitude.Enabled = false
	self.throttle, self.speed, self.rotorSpeed = 0, 0, 0

	for _, thruster in self.thrusters do
		thruster.fire.Enabled = false
		thruster.light.Brightness = 0
	end

	local scatter = Random.new()
	local origin = self.fuselage.Position

	for _, joint in self.joints do
		(joint :: any).Enabled = false
	end
	if self.rotorMotor then
		self.rotorMotor.Enabled = false
		self.rotorMotor.AngularVelocity = 0
	end

	for _, part in self.model:GetDescendants() do
		if part:IsA("BasePart") then
			local away = part.Position - origin
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 1, 0)

			part.AssemblyLinearVelocity = away * Config.CrashScatterSpeed
				+ Vector3.new(0, Config.CrashScatterLift, 0)
			part.AssemblyAngularVelocity = Vector3.new(
				scatter:NextNumber(-1, 1),
				scatter:NextNumber(-1, 1),
				scatter:NextNumber(-1, 1)
			) * Config.CrashScatterSpin
		end
	end

	-- A fireball where the aeroplane was.
	local blast = Instance.new("Part")
	blast.Anchored = true
	blast.CanCollide = false
	blast.CanQuery = false
	blast.Transparency = 1
	blast.Size = Vector3.one
	blast.CFrame = CFrame.new(origin)
	blast.Parent = self.model.Parent

	local fireball = Instance.new("Fire")
	fireball.Heat = 25
	fireball.Size = 26
	fireball.Parent = blast
	Debris:AddItem(blast, 3)

	-- Everybody aboard dies with the aeroplane. Riding the wreck down unhurt made
	-- a crash feel like a pause rather than a mistake, and a passenger who walks
	-- away from a fireball undercuts the same thing.
	local function killAboard(who: Player?)
		local character = who and who.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end

	killAboard(self.player)
	killAboard(self.passenger)

	self.player:SetAttribute("Crashed", true)
	if self.onCrash then
		self.onCrash()
	end
end

function PlaneController:reset()
	-- Whoever was riding along should still be riding along afterwards. Captured
	-- before the old aeroplane goes, because destroying it empties the seat and
	-- clears the field.
	local riding = self.passenger

	if self.model then
		self.model:Destroy()
	end
	self.passenger = nil
	self.fuel = nil -- a new aeroplane is a full one
	self:build()

	if riding then
		self:restorePassenger(riding)
	end

	self.player:SetAttribute("Crashed", false)
	if self.onReset then
		self.onReset()
	end
end

function PlaneController:destroy()
	-- Before the model goes, so supervise() cannot decide the missing airframe
	-- means it should build another one for a pilot who has left.
	self.retired = true
	self.passenger = nil

	if self.model then
		self.model:Destroy()
		self.model = nil
	end
end

--------------------------------------------------------------------------------
-- Flight
--------------------------------------------------------------------------------

function PlaneController:step(dt: number)
	if not self.model or not self.model.Parent or not self.fuselage then
		return
	end

	local position = self.fuselage.Position

	if self.crashed then
		if os.clock() >= self.crashClearsAt then
			self:reset()
		end
		return
	end

	local controls = self.controls
	if self.seat.Occupant == nil then
		controls.throttle, controls.pitch, controls.roll, controls.yaw = -1, 0, 0, 0
	end

	local groundY = self:groundHeightAt(position)
	local altitude = position.Y
	local restingAltitude = if groundY then groundY + self.groundClearance else -math.huge
	local airborne = altitude > restingAltitude + Config.GroundTolerance

	--------------------------------------------------------------------------
	-- Fuel
	--------------------------------------------------------------------------
	self.throttle = math.clamp(
		self.throttle + controls.throttle * Config.ThrottleRate * dt,
		0,
		1
	)

	if self.fuel > 0 then
		local burn = Config.FuelIdleBurn + Config.FuelBurnRate * self.throttle
		self.fuel = math.max(0, self.fuel - burn * dt)
		self.engineOut = self.fuel <= 0
	else
		self.engineOut = true
	end

	if self.engineOut then
		self.throttle = 0
	end

	--------------------------------------------------------------------------
	-- Attitude. Rotations are applied in the aircraft's own frame, which is
	-- what allows a loop to carry through inverted instead of hitting a limit.
	--------------------------------------------------------------------------
	local orientation = self.orientation

	if airborne then
		-- Signs, worked out rather than guessed. These are rotations about the
		-- aircraft's own axes, applied as orientation * CFrame.Angles(x, y, z).
		--
		--   +X  raises the nose      (LookVector goes to (0, sin, -cos))
		--   +Z  raises the RIGHT wing, so rolling right needs a negative angle
		--   +Y  yaws LEFT,           so yawing right needs a negative angle
		--
		-- Pitch used to carry the same minus as the other two, which quietly
		-- made a positive pitch input push the nose down.
		local pitch = controls.pitch * self.pitchRate * dt
		local roll = -controls.roll * self.rollRate * dt
		local yaw = -controls.yaw * self.yawRate * dt

		orientation = orientation * CFrame.Angles(pitch, yaw, roll)

		-- Weak self-levelling, and only while roughly upright. Measured from
		-- how far the aircraft's own up-vector has fallen from world up, so it
		-- rolls the shortest way back and gives up entirely once inverted.
		if controls.roll == 0 then
			local up = orientation.UpVector
			local tilt = math.acos(math.clamp(up.Y, -1, 1))

			if tilt > 0.02 and tilt < Config.AutoLevelLimit then
				local right = orientation.RightVector
				-- Positive when the right wing is low, so correcting means
				-- rolling back the other way.
				local lean = right.Y
				local correction = math.clamp(
					lean * self.autoLevelRate * dt,
					-self.autoLevelRate * dt,
					self.autoLevelRate * dt
				)
				orientation = orientation * CFrame.Angles(0, 0, -correction)
			end
		end

		-- With no pitch input the nose drifts back toward the horizon, so
		-- letting go settles rather than holding a climb for ever.
		if controls.pitch == 0 then
			local look = orientation.LookVector
			local settle = math.clamp(
				look.Y * self.pitchSettleRate * dt,
				-self.pitchSettleRate * dt,
				self.pitchSettleRate * dt
			)
			orientation = orientation * CFrame.Angles(settle, 0, 0)
		end
	else
		-- On the ground: hold the wings level and steer with the rudder, so the
		-- aircraft cannot tip over while taxiing.
		local _, heading = orientation:ToEulerAnglesYXZ()
		if self.speed > 1 then
			heading -= controls.yaw * Config.GroundSteerRate * dt
		end
		orientation = CFrame.Angles(0, heading, 0)
	end

	self.orientation = orientation

	--------------------------------------------------------------------------
	-- Speed
	--------------------------------------------------------------------------
	local targetSpeed = self.throttle * self.maxSpeed
	if airborne then
		-- An empty tank keeps a floor too, just a lower one. Without thrust the
		-- aircraft glides exactly as it does with the throttle shut rather than
		-- dropping: you keep every control, and losing height is a problem you
		-- solve by pointing the nose somewhere sensible.
		local floor = if self.engineOut
			then self.minFlightSpeed * Config.GlideSpeedFactor
			else self.minFlightSpeed
		targetSpeed = math.max(targetSpeed, floor)
	end

	local speedStep = (if targetSpeed > self.speed then Config.Acceleration else Config.Braking) * dt
	self.speed = approach(self.speed, targetSpeed, speedStep)

	if airborne then
		-- Uphill costs speed, downhill gains it. The only nod to real flight in
		-- the model, and it is what gives a loop a cost and a dive a payoff.
		local climbing = orientation.LookVector.Y
		self.speed -= climbing * Config.GravityDrag * dt
		self.speed = math.clamp(self.speed, 0, self.maxSpeed * 1.4)
	end

	--------------------------------------------------------------------------
	-- Velocity
	--------------------------------------------------------------------------
	local velocity = orientation.LookVector * self.speed

	-- Never drive down through the surface while rolling along it.
	if not airborne and velocity.Y < 0 then
		velocity = Vector3.new(velocity.X, 0, velocity.Z)
	end
	if altitude >= Config.MaxAltitude and velocity.Y > 0 then
		velocity = Vector3.new(velocity.X, 0, velocity.Z)
	end

	self.flight.VectorVelocity = velocity
	self.attitude.CFrame = orientation

	--------------------------------------------------------------------------
	-- Cosmetics
	--------------------------------------------------------------------------
	local rudderTarget = math.clamp(controls.yaw + controls.roll * Config.RudderTurnMix, -1, 1)
	local surfaceStep = Config.SurfaceRate * dt
	local deflection = self.deflection
	deflection.roll = approach(deflection.roll, controls.roll, surfaceStep)
	deflection.pitch = approach(deflection.pitch, controls.pitch, surfaceStep)
	deflection.yaw = approach(deflection.yaw, rudderTarget, surfaceStep)

	for _, surface in self.surfaces do
		local spec = surface.spec
		local angle = deflection[spec.channel] * spec.limit * spec.sign
		local swing = if spec.vertical then CFrame.Angles(0, angle, 0) else CFrame.Angles(angle, 0, 0)
		surface.motor.C0 = surface.base * swing
	end

	if self.rotorMotor then
		local targetRotor = self.throttle * Config.MaxRotorSpeed
		self.rotorSpeed += (targetRotor - self.rotorSpeed) * (1 - math.exp(-dt / Config.RotorSpoolTime))
		self.rotorMotor.AngularVelocity = self.rotorSpeed
	end

	for _, thruster in self.thrusters do
		thruster.fire.Enabled = self.throttle > 0.05
		thruster.fire.Size = Config.ThrusterFlameIdle
			+ (Config.ThrusterFlameFull - Config.ThrusterFlameIdle) * self.throttle
		thruster.light.Brightness = self.throttle * Config.ThrusterLight
	end

	--------------------------------------------------------------------------
	-- Instruments, at a fixed rate rather than every frame
	--------------------------------------------------------------------------
	self.publishClock += dt
	if self.publishClock >= 1 / 15 then
		self.publishClock = 0

		local look = orientation.LookVector
		local up = orientation.UpVector
		local player = self.player

		player:SetAttribute("Throttle", self.throttle)
		player:SetAttribute("Airspeed", self.speed)
		player:SetAttribute("Altitude", altitude)
		player:SetAttribute("HeightAboveGround", if groundY then altitude - groundY else 9999)
		player:SetAttribute("ClimbRate", velocity.Y)
		player:SetAttribute("Pitch", math.deg(math.asin(math.clamp(look.Y, -1, 1))))
		player:SetAttribute("Bank", math.deg(math.atan2(orientation.RightVector.Y, up.Y)))
		player:SetAttribute("Inverted", up.Y < 0)
		player:SetAttribute("Heading", math.deg(math.atan2(-look.X, -look.Z)) % 360)
		player:SetAttribute("Grounded", not airborne)
		player:SetAttribute("Fuel", self.fuel)
		player:SetAttribute("FuelCapacity", self.fuelCapacity)
		player:SetAttribute("EngineOut", self.engineOut)
		player:SetAttribute("AtSpawn", self:isNearSpawn())
	end

	--------------------------------------------------------------------------
	-- Impact
	--------------------------------------------------------------------------
	if
		Config.CrashEnabled
		and not self.invincible
		and airborne
		and os.clock() >= self.crashImmuneUntil
	then
		local travel = position - self.lastPosition

		if travel.Magnitude > 0.01 then
			local direction = travel.Unit
			local sweep = Workspace:Raycast(
				self.lastPosition,
				travel + direction * Config.CrashProbeDistance,
				self.probe
			)

			if sweep and direction:Dot(sweep.Normal) <= Config.CrashImpactDot then
				self:crash()
				return
			end
		end
	end

	if altitude < Config.VoidHeight then
		-- Falling out of the world is not a crash worth watching when the point
		-- is to be untouchable, so invincibility just puts it back.
		if self.invincible then
			self:reset()
		else
			self:crash()
		end
		return
	end

	self.lastPosition = position
end

return PlaneController
