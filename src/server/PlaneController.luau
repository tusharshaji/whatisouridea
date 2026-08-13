--!strict

-- One aircraft, belonging to one pilot.
--
-- This was a single script driving the single plane in the world. It is now a
-- class because every player gets their own, which also means every value it
-- used to keep as a file-level local is now a field: there is no such thing as
-- "the" throttle any more.
--
-- The flight model itself is unchanged and still deliberately not aerodynamic.
-- The controller keeps five numbers -- throttle, speed, heading, bank and climb
-- rate -- eases each toward what its pilot is asking for, and commands the
-- result through a LinearVelocity and an AlignOrientation. Turning and climbing
-- stay independent, so banking never costs altitude.
--
-- Respawning works by throwing the aeroplane away and cloning a new one. The
-- previous version broke the welds, flung the parts and then tried to put the
-- same parts back afterwards, which lost pieces: debris that fell past
-- FallenPartsDestroyHeight, or through thin terrain, was gone by the time
-- reassembly ran, and reassembly had no way to recreate it. A fresh clone cannot
-- be missing anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.PlaneConfig)

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

export type Controller = typeof(setmetatable({} :: any, PlaneController))

-- Step a value toward a target without overshooting. Every easing goes through
-- this, which is why nothing in the model can oscillate.
local function approach(current: number, target: number, maxStep: number): number
	local delta = target - current
	if math.abs(delta) <= maxStep then
		return target
	end
	return current + (if delta > 0 then maxStep else -maxStep)
end

function PlaneController.new(
	player: Player,
	template: Model,
	container: Instance,
	pad: CFrame,
	probe: RaycastParams,
	collisionGroup: string
)
	local self = setmetatable({}, PlaneController)

	self.player = player
	self.template = template
	self.container = container
	self.pad = pad
	self.probe = probe
	self.collisionGroup = collisionGroup

	self.crashed = false
	self.crashClearsAt = 0
	self.crashImmuneUntil = 0
	self.onCrash = nil :: (() -> ())?
	self.onReset = nil :: (() -> ())?
	self.publishClock = 0

	self.controls = { throttle = 0, pitch = 0, roll = 0, yaw = 0 }
	self.stats = { speed = 1, handling = 1, climb = 1 }

	self:build()
	return self
end

-- Multipliers from the pilot's aircraft and upgrades. Stored as resolved values
-- so the flight loop never has to think about who owns what.
function PlaneController:applyStats(stats: { [string]: number })
	self.stats = stats

	local speed = stats.speed or 1
	local handling = stats.handling or 1
	local climb = stats.climb or 1

	self.maxSpeed = Config.MaxSpeed * speed
	self.minFlightSpeed = Config.MinFlightSpeed * speed
	self.maxTurnRate = Config.MaxTurnRate * handling
	self.bankRate = Config.BankRate * handling
	self.autoLevelRate = Config.AutoLevelRate * handling
	self.maxClimbRate = Config.MaxClimbRate * climb
	self.maxDescentRate = Config.MaxDescentRate * climb
end

function PlaneController:build()
	local model = self.template:Clone()
	model.Name = `Plane_{self.player.UserId}`
	model.Parent = self.container

	local fuselage = model:FindFirstChild("Fuselage") :: BasePart
	local hub = model:FindFirstChild("RotorHub") :: BasePart
	local seat = model:FindFirstChild("PilotSeat") :: VehicleSeat

	if not fuselage or not hub or not seat then
		warn(`[PlaneController] template is missing Fuselage, RotorHub or PilotSeat for {self.player.Name}`)
		model:Destroy()
		return
	end

	self.model = model
	self.fuselage = fuselage
	self.hub = hub
	self.seat = seat

	local rotorMotor = fuselage:FindFirstChild("RotorMotor") :: HingeConstraint
	local flight = fuselage:FindFirstChild("Flight") :: LinearVelocity
	local attitude = fuselage:FindFirstChild("Attitude") :: AlignOrientation

	self.rotorMotor = rotorMotor
	self.flight = flight
	self.attitude = attitude

	-- Rojo has no Ref property support, so constraints are declared in the
	-- project file and linked to their attachments here.
	rotorMotor.Attachment0 = fuselage:FindFirstChild("RotorMount") :: Attachment
	rotorMotor.Attachment1 = hub:FindFirstChild("HubAxis") :: Attachment
	flight.Attachment0 = fuselage:FindFirstChild("ThrustPoint") :: Attachment
	attitude.Attachment0 = fuselage:FindFirstChild("AeroPoint") :: Attachment

	local joints: { Instance } = {}
	local function weld(anchor: BasePart, part: BasePart)
		local constraint = Instance.new("WeldConstraint")
		constraint.Part0 = anchor
		constraint.Part1 = part
		constraint.Parent = anchor
		table.insert(joints, constraint)
	end

	-- Uniform density, so Material means appearance only.
	local physics = PhysicalProperties.new(Config.AirframeDensity, 0.3, 0.2, 1, 1)

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CustomPhysicalProperties = physics
			-- Every aircraft shares one collision group that does not collide
			-- with itself, so pilots fly through each other instead of swatting
			-- one another off the course.
			part.CollisionGroup = self.collisionGroup

			if ROTOR_PARTS[part.Name] then
				if part ~= hub then
					weld(hub, part)
				end
			elseif not SURFACE_PARTS[part.Name] and part ~= fuselage then
				weld(fuselage, part)
			end
		end
	end

	-- Hinge each control surface on its leading edge so it pivots like a flap
	-- rather than spinning about its own centre.
	local surfaces: { { motor: Motor6D, base: CFrame, spec: SurfaceSpec } } = {}

	for _, spec in SURFACE_SPECS do
		local part = model:FindFirstChild(spec.name)
		if part and part:IsA("BasePart") then
			local hinge = part.CFrame * CFrame.new(0, 0, -part.Size.Z / 2)

			local motor = Instance.new("Motor6D")
			motor.Name = spec.name .. "Hinge"
			motor.Part0 = fuselage
			motor.Part1 = part
			motor.C0 = fuselage.CFrame:ToObjectSpace(hinge)
			motor.C1 = part.CFrame:ToObjectSpace(hinge)
			motor.Parent = fuselage

			table.insert(surfaces, { motor = motor, base = motor.C0, spec = spec })
			table.insert(joints, motor)
		end
	end

	self.joints = joints
	self.surfaces = surfaces

	model.PrimaryPart = fuselage

	-- How high the fuselage rides above the lowest point of the aircraft.
	local boundingCFrame, boundingSize = model:GetBoundingBox()
	self.groundClearance = fuselage.Position.Y - (boundingCFrame.Position.Y - boundingSize.Y / 2)

	-- Park on whatever is under the pad, so terrain generated over the runway
	-- still leaves the wheels on the surface.
	local padGround = self:groundHeightAt(self.pad.Position)
	local resting = if padGround
		then padGround + self.groundClearance
		else self.pad.Position.Y

	local parked = CFrame.new(self.pad.Position.X, resting, self.pad.Position.Z)
		* (self.pad - self.pad.Position)
	model:PivotTo(parked)

	self.padFuselage = fuselage.CFrame
	self.padHeading = select(2, parked:ToEulerAnglesYXZ())

	local mass = 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			mass += part.Mass
		end
	end

	flight.MaxForce = mass * Config.ForceHeadroom
	attitude.MaxTorque = mass * Config.ForceHeadroom
	attitude.Responsiveness = Config.OrientationResponse
	rotorMotor.MotorMaxTorque = mass * 20

	-- Flight state, all of it.
	self.throttle = 0
	self.speed = 0
	self.heading = self.padHeading
	self.bank = 0
	self.pitch = 0
	self.climbRate = 0
	self.rotorSpeed = 0
	self.deflection = { roll = 0, pitch = 0, yaw = 0 }
	self.lastPosition = fuselage.Position

	self.crashed = false
	self.crashImmuneUntil = os.clock() + Config.CrashGracePeriod

	if not self.maxSpeed then
		self:applyStats(self.stats)
	end

	self:claimOwnership()
	self:seatPilot()
end

function PlaneController:claimOwnership()
	-- Sitting in a VehicleSeat hands network ownership to the occupant. Claim it
	-- back so the server both decides and simulates.
	if self.fuselage and self.fuselage:IsDescendantOf(Workspace) then
		self.fuselage:SetNetworkOwner(nil)
		self.hub:SetNetworkOwner(nil)
	end
end

function PlaneController:seatPilot()
	local character = self.player.Character
	if not character or not self.seat then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		self.seat:Sit(humanoid)
		task.defer(function()
			self:claimOwnership()
		end)
	end
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

-- Let the aeroplane come apart. Every joint off turns each part into its own
-- free body; a shove outward turns that into a burst rather than a collapse.
-- The wreck is thrown away wholesale on respawn, so nothing here has to be
-- recoverable.
function PlaneController:crash()
	if self.crashed or not self.model then
		return
	end

	self.crashed = true
	self.crashClearsAt = os.clock() + Config.CrashRespawnDelay

	self.flight.Enabled = false
	self.attitude.Enabled = false
	self.rotorMotor.AngularVelocity = 0
	self.throttle, self.speed, self.climbRate, self.rotorSpeed = 0, 0, 0, 0

	local scatter = Random.new()
	local origin = self.fuselage.Position

	for _, joint in self.joints do
		(joint :: any).Enabled = false
	end
	self.rotorMotor.Enabled = false

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

	self.player:SetAttribute("Crashed", true)
	if self.onCrash then
		self.onCrash()
	end
end

-- Back to the runway with a brand new aeroplane.
function PlaneController:reset()
	if self.model then
		self.model:Destroy()
	end

	self:build()

	self.player:SetAttribute("Crashed", false)
	if self.onReset then
		self.onReset()
	end
end

function PlaneController:destroy()
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
end

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
		-- Unattended: close the throttle and stop steering.
		controls.throttle, controls.pitch, controls.roll, controls.yaw = -1, 0, 0, 0
	end

	local altitude = position.Y

	-- Height is measured against the ground directly below, never against world
	-- Y. Over terrain those are not the same thing, and comparing to a constant
	-- makes the aircraft believe it is parked whenever it flies over low ground.
	local groundY = self:groundHeightAt(position)
	local restingAltitude = if groundY then groundY + self.groundClearance else -math.huge
	local airborne = altitude > restingAltitude + Config.GroundTolerance

	local hasFlyingSpeed = self.speed >= Config.TakeoffSpeed

	self.throttle = math.clamp(
		self.throttle + controls.throttle * Config.ThrottleRate * dt,
		0,
		1
	)
	local targetSpeed = self.throttle * self.maxSpeed
	if airborne then
		targetSpeed = math.max(targetSpeed, self.minFlightSpeed)
	end
	local speedStep = (if targetSpeed > self.speed then Config.Acceleration else Config.Braking) * dt
	self.speed = approach(self.speed, targetSpeed, speedStep)

	local targetBank = if airborne then controls.roll * Config.MaxBankAngle else 0
	local bankStep = (if controls.roll ~= 0 then self.bankRate else self.autoLevelRate) * dt
	self.bank = approach(self.bank, targetBank, bankStep)

	local turnRate = 0
	if airborne then
		turnRate = (self.bank / Config.MaxBankAngle) * self.maxTurnRate
			+ controls.yaw * Config.RudderTurnRate
	elseif self.speed > 1 then
		turnRate = controls.yaw * Config.GroundSteerRate
	end
	self.heading -= turnRate * dt

	local targetClimb = 0
	if hasFlyingSpeed then
		local limit = if controls.pitch >= 0 then self.maxClimbRate else self.maxDescentRate
		targetClimb = controls.pitch * limit
	end
	self.climbRate = approach(self.climbRate, targetClimb, Config.ClimbAcceleration * dt)

	if altitude <= restingAltitude and self.climbRate < 0 then
		self.climbRate = 0
	elseif altitude >= Config.MaxAltitude and self.climbRate > 0 then
		self.climbRate = 0
	end

	local targetPitch = math.clamp(
		math.atan2(self.climbRate, math.max(self.speed, 1)),
		-Config.MaxPitchAngle,
		Config.MaxPitchAngle
	)
	self.pitch = approach(self.pitch, targetPitch, Config.PitchRate * dt)

	local facing = CFrame.Angles(0, self.heading, 0)
	local forward = facing.LookVector
	self.flight.VectorVelocity = Vector3.new(
		forward.X * self.speed,
		self.climbRate,
		forward.Z * self.speed
	)
	self.attitude.CFrame = facing
		* CFrame.Angles(self.pitch, 0, 0)
		* CFrame.Angles(0, 0, -self.bank)

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

	local targetRotor = self.throttle * Config.MaxRotorSpeed
	self.rotorSpeed += (targetRotor - self.rotorSpeed) * (1 - math.exp(-dt / Config.RotorSpoolTime))
	self.rotorMotor.AngularVelocity = self.rotorSpeed

	-- Instruments. Published at a fixed rate rather than every frame: these are
	-- replicated properties and one aircraft per player makes that add up.
	self.publishClock += dt
	if self.publishClock >= 1 / 15 then
		self.publishClock = 0
		local player = self.player
		player:SetAttribute("Throttle", self.throttle)
		player:SetAttribute("Airspeed", self.speed)
		player:SetAttribute("Altitude", altitude)
		player:SetAttribute("HeightAboveGround", if groundY then altitude - groundY else 9999)
		player:SetAttribute("ClimbRate", self.climbRate)
		player:SetAttribute("Bank", math.deg(self.bank))
		player:SetAttribute("Heading", math.deg(-self.heading) % 360)
		player:SetAttribute("Grounded", not airborne)
	end

	-- Sweep from where the aircraft was to where it is now, plus a look-ahead.
	-- Sweeping cannot be tunnelled through a ridge at 220 studs/sec, and
	-- starting from last frame's position -- open air -- avoids the dead zone a
	-- ray gets when it begins inside solid geometry.
	if Config.CrashEnabled and airborne and os.clock() >= self.crashImmuneUntil then
		local travel = position - self.lastPosition

		if travel.Magnitude > 0.01 then
			local direction = travel.Unit
			local sweep = Workspace:Raycast(
				self.lastPosition,
				travel + direction * Config.CrashProbeDistance,
				self.probe
			)

			-- Only head-on impacts count, which is what tells a shallow
			-- touchdown apart from a dive into the same ground.
			if sweep and direction:Dot(sweep.Normal) <= Config.CrashImpactDot then
				self:crash()
				return
			end
		end
	end

	if altitude < Config.VoidHeight then
		self:reset()
		return
	end

	self.lastPosition = position
end

return PlaneController
