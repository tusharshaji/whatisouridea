--!strict

-- Arcade flight controller for Workspace.Airplane.
--
-- This is deliberately not an aerodynamic simulation. The controller keeps four
-- numbers -- speed, heading, bank and climb rate -- eases each one toward what
-- the pilot is asking for, and then tells a LinearVelocity and an
-- AlignOrientation to make the aircraft match.
--
-- Commanding the result rather than nudging it with forces is what makes the
-- handling predictable. The plane has no momentum of its own to fight, so it
-- cannot spin, oscillate, sideslip, or drop out of a bank: the only motion it
-- has is the motion asked for here, and every limit is a clamp in PlaneConfig.
--
-- Turning and climbing are independent on purpose. Heading comes from bank
-- angle, height comes from the climb rate, and neither touches the other, so
-- banking never costs altitude.
--
-- The server owns all of it. Clients only ever send axis values, which are
-- validated on arrival and are the sole thing the pilot can influence.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.PlaneConfig)

local plane = Workspace:WaitForChild("Airplane") :: Model
local fuselage = plane:WaitForChild("Fuselage") :: BasePart
local hub = plane:WaitForChild("RotorHub") :: BasePart
local seat = plane:WaitForChild("PilotSeat") :: VehicleSeat
local state = plane:WaitForChild("State")

local rotorMotor = fuselage:WaitForChild("RotorMotor") :: HingeConstraint
local flight = fuselage:WaitForChild("Flight") :: LinearVelocity
local attitude = fuselage:WaitForChild("Attitude") :: AlignOrientation

local inputRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlaneInput") :: RemoteEvent

local ROTOR_PARTS: { [string]: boolean } = {
	RotorHub = true,
	RotorBladeA = true,
	RotorBladeB = true,
}

-- Moving control surfaces. Each is hinged at its leading edge and swung by one
-- of the control channels. A positive angle drops the trailing edge, so the
-- signs below are what make the pair of ailerons oppose each other and the
-- elevator rise when you pull back.
type SurfaceSpec = {
	name: string,
	channel: string,
	limit: number,
	sign: number,
	vertical: boolean, -- rudder swings about the vertical axis, the rest about the span
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

-- Rojo 7.7 has no Ref property support, so the constraints are declared in
-- default.project.json and linked to their attachments here.
rotorMotor.Attachment0 = fuselage:WaitForChild("RotorMount") :: Attachment
rotorMotor.Attachment1 = hub:WaitForChild("HubAxis") :: Attachment
flight.Attachment0 = fuselage:WaitForChild("ThrustPoint") :: Attachment
attitude.Attachment0 = fuselage:WaitForChild("AeroPoint") :: Attachment

-- Weld the airframe into one rigid body, and the blades into a second one the
-- hinge can spin. Rebuilding the welds from current positions each run means a
-- part dragged around in Studio still ends up attached where you left it.
local function weld(anchor: BasePart, part: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = anchor
	constraint.Part1 = part
	constraint.Parent = anchor
end

-- Uniform density, so Material is free to mean appearance only. Roblox derives
-- density from Material otherwise, and the spread is wide enough that recolouring
-- a part in Metal would quietly change how the aircraft balances.
local physics = PhysicalProperties.new(Config.AirframeDensity, 0.3, 0.2, 1, 1)

for _, part in plane:GetDescendants() do
	if part:IsA("BasePart") then
		part.Anchored = false
		part.CustomPhysicalProperties = physics

		if ROTOR_PARTS[part.Name] then
			if part ~= hub then
				weld(hub, part)
			end
		elseif not SURFACE_PARTS[part.Name] and part ~= fuselage then
			-- Control surfaces are left out: they get a Motor6D below so they
			-- can still swing while being carried rigidly by the airframe.
			weld(fuselage, part)
		end
	end
end

-- Hinge each control surface on its leading edge. Putting the joint on the edge
-- rather than the middle is what makes the surface pivot like a flap instead of
-- spinning about its own centre.
local surfaces: { { motor: Motor6D, base: CFrame, spec: SurfaceSpec } } = {}

for _, spec in SURFACE_SPECS do
	-- Wait rather than look once: on the first run after a sync the parts can
	-- still be arriving when this script starts.
	local part = plane:WaitForChild(spec.name, 5)

	if not part or not part:IsA("BasePart") then
		warn(
			`[Airplane] control surface "{spec.name}" was not found, so it will not move. `
				.. `If you just edited default.project.json, restart "rojo serve" and reconnect the Studio plugin.`
		)
		continue
	end

	local hinge = part.CFrame * CFrame.new(0, 0, -part.Size.Z / 2)

	local motor = Instance.new("Motor6D")
	motor.Name = spec.name .. "Hinge"
	motor.Part0 = fuselage
	motor.Part1 = part
	motor.C0 = fuselage.CFrame:ToObjectSpace(hinge)
	motor.C1 = part.CFrame:ToObjectSpace(hinge)
	motor.Parent = fuselage

	table.insert(surfaces, { motor = motor, base = motor.C0, spec = spec })
end

print(`[Airplane] hinged {#surfaces} of {#SURFACE_SPECS} control surfaces`)

plane.PrimaryPart = fuselage
local padCFrame = plane:GetPivot()
local _, padHeading = padCFrame:ToEulerAnglesYXZ()

-- Work out how high the fuselage rides above the lowest point of the aircraft,
-- then park it that far above the tarmac. Measuring the model instead of
-- hard-coding a height means the plane can be moved, raised or re-shod with
-- taller gear and it still sits on its wheels.
local boundingCFrame, boundingSize = plane:GetBoundingBox()
local groundClearance = fuselage.Position.Y - (boundingCFrame.Position.Y - boundingSize.Y / 2)
local groundAltitude = Config.RunwayHeight + groundClearance

-- Give the constraints enough authority to hold the aircraft exactly, scaled to
-- whatever the model actually weighs so resizing parts in Studio stays safe.
local mass = 0
for _, part in plane:GetDescendants() do
	if part:IsA("BasePart") then
		mass += part.Mass
	end
end

flight.MaxForce = mass * Config.ForceHeadroom
attitude.MaxTorque = mass * Config.ForceHeadroom
attitude.Responsiveness = Config.OrientationResponse
rotorMotor.MotorMaxTorque = mass * 20

local throttleValue = state:WaitForChild("Throttle") :: NumberValue
local airspeedValue = state:WaitForChild("Airspeed") :: NumberValue
local altitudeValue = state:WaitForChild("Altitude") :: NumberValue
local climbValue = state:WaitForChild("ClimbRate") :: NumberValue
local bankValue = state:WaitForChild("Bank") :: NumberValue
local headingValue = state:WaitForChild("Heading") :: NumberValue
local groundedValue = state:WaitForChild("Grounded") :: BoolValue

-- The entire flight state. Everything the plane does is one of these five.
local throttle = 0
local speed = 0
local heading = padHeading
local bank = 0
local pitch = 0
local climbRate = 0
local rotorSpeed = 0

local controls = { throttle = 0, pitch = 0, roll = 0, yaw = 0 }
local deflection: { [string]: number } = { roll = 0, pitch = 0, yaw = 0 }
local lastReset = 0

-- Step a value toward a target without ever overshooting it. Used for every
-- easing in the controller, which is why nothing here can oscillate.
local function approach(current: number, target: number, maxStep: number): number
	local delta = target - current
	if math.abs(delta) <= maxStep then
		return target
	end
	return current + (if delta > 0 then maxStep else -maxStep)
end

local function isPilot(player: Player): boolean
	local occupant = seat.Occupant
	return occupant ~= nil and occupant.Parent == player.Character
end

local function resetPlane()
	throttle, speed, bank, pitch, climbRate, rotorSpeed = 0, 0, 0, 0, 0, 0
	heading = padHeading
	controls.throttle, controls.pitch, controls.roll, controls.yaw = 0, 0, 0, 0
	deflection.roll, deflection.pitch, deflection.yaw = 0, 0, 0

	flight.VectorVelocity = Vector3.zero
	attitude.CFrame = CFrame.Angles(0, padHeading, 0)
	rotorMotor.AngularVelocity = 0

	plane:PivotTo(padCFrame)
	fuselage.AssemblyLinearVelocity = Vector3.zero
	fuselage.AssemblyAngularVelocity = Vector3.zero
	hub.AssemblyLinearVelocity = Vector3.zero
	hub.AssemblyAngularVelocity = Vector3.zero
end

-- Anything arriving from a client is untrusted: it must be a finite number, and
-- it is clamped to the range the controller expects before it is stored.
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
	if not isPilot(player) or type(payload) ~= "table" then
		return
	end

	if payload.reset == true then
		if os.clock() - lastReset >= Config.ResetCooldown then
			lastReset = os.clock()
			resetPlane()
		end
		return
	end

	controls.throttle = readAxis(payload.throttle)
	controls.pitch = readAxis(payload.pitch)
	controls.roll = readAxis(payload.roll)
	controls.yaw = readAxis(payload.yaw)
end)

-- Sitting in a VehicleSeat hands network ownership to the occupant. Claim it
-- back so the server both decides and simulates.
local function claimOwnership()
	if fuselage:IsDescendantOf(Workspace) then
		fuselage:SetNetworkOwner(nil)
		hub:SetNetworkOwner(nil)
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	task.defer(claimOwnership)
end)
claimOwnership()

Players.PlayerRemoving:Connect(function(player)
	if isPilot(player) then
		controls.throttle, controls.pitch, controls.roll, controls.yaw = 0, 0, 0, 0
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if seat.Occupant == nil then
		-- Unattended: close the throttle and stop steering.
		controls.throttle, controls.pitch, controls.roll, controls.yaw = -1, 0, 0, 0
	end

	local altitude = fuselage.Position.Y
	local airborne = altitude > groundAltitude + Config.GroundTolerance

	-- Fast enough for the nose to come up. Checked against speed rather than
	-- height so the plane can rotate off the runway in the first place.
	local hasFlyingSpeed = speed >= Config.TakeoffSpeed

	-- Throttle sets a target speed and the plane eases toward it. Once airborne
	-- the target is floored at MinFlightSpeed, so closing the throttle in flight
	-- slows the plane down but never leaves it hanging.
	throttle = math.clamp(throttle + controls.throttle * Config.ThrottleRate * dt, 0, 1)
	local targetSpeed = throttle * Config.MaxSpeed
	if airborne then
		targetSpeed = math.max(targetSpeed, Config.MinFlightSpeed)
	end
	local speedStep = (if targetSpeed > speed then Config.Acceleration else Config.Braking) * dt
	speed = approach(speed, targetSpeed, speedStep)

	-- Bank follows A/D, and returns to level on its own the moment they are
	-- released. Wings stay level on the ground so the plane cannot tip over.
	local targetBank = if airborne then controls.roll * Config.MaxBankAngle else 0
	local bankStep = (if controls.roll ~= 0 then Config.BankRate else Config.AutoLevelRate) * dt
	bank = approach(bank, targetBank, bankStep)

	-- Heading comes from bank in the air and from the rudder on the ground.
	-- Negative because a positive heading angle turns toward -X, and banking
	-- right should turn right.
	local turnRate = 0
	if airborne then
		turnRate = (bank / Config.MaxBankAngle) * Config.MaxTurnRate + controls.yaw * Config.RudderTurnRate
	elseif speed > 1 then
		turnRate = controls.yaw * Config.GroundSteerRate
	end
	heading -= turnRate * dt

	-- Climb rate is commanded directly, which is what keeps a turn level: bank
	-- has no say here at all.
	local targetClimb = 0
	if hasFlyingSpeed then
		local limit = if controls.pitch >= 0 then Config.MaxClimbRate else Config.MaxDescentRate
		targetClimb = controls.pitch * limit
	end
	climbRate = approach(climbRate, targetClimb, Config.ClimbAcceleration * dt)

	if altitude <= groundAltitude and climbRate < 0 then
		climbRate = 0
	elseif altitude >= Config.MaxAltitude and climbRate > 0 then
		climbRate = 0
	end

	-- The nose tracks the climb rate. This is appearance only; the plane moves
	-- where the velocity below says, not where it is pointing.
	local targetPitch = math.clamp(
		math.atan2(climbRate, math.max(speed, 1)),
		-Config.MaxPitchAngle,
		Config.MaxPitchAngle
	)
	pitch = approach(pitch, targetPitch, Config.PitchRate * dt)

	-- Hand the finished state to the constraints.
	local facing = CFrame.Angles(0, heading, 0)
	local forward = facing.LookVector
	flight.VectorVelocity = Vector3.new(forward.X * speed, climbRate, forward.Z * speed)
	attitude.CFrame = facing * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, -bank)

	-- Swing the control surfaces to match what is being asked for. The rudder
	-- picks up a share of the roll input too, so banking into a turn visibly
	-- swings it the way a coordinated turn would.
	local rudderTarget = math.clamp(controls.yaw + controls.roll * Config.RudderTurnMix, -1, 1)
	local surfaceStep = Config.SurfaceRate * dt
	deflection.roll = approach(deflection.roll, controls.roll, surfaceStep)
	deflection.pitch = approach(deflection.pitch, controls.pitch, surfaceStep)
	deflection.yaw = approach(deflection.yaw, rudderTarget, surfaceStep)

	for _, surface in surfaces do
		local spec = surface.spec
		local angle = deflection[spec.channel] * spec.limit * spec.sign
		local swing = if spec.vertical then CFrame.Angles(0, angle, 0) else CFrame.Angles(angle, 0, 0)
		surface.motor.C0 = surface.base * swing
	end

	local targetRotor = throttle * Config.MaxRotorSpeed
	rotorSpeed += (targetRotor - rotorSpeed) * (1 - math.exp(-dt / Config.RotorSpoolTime))
	rotorMotor.AngularVelocity = rotorSpeed

	throttleValue.Value = throttle
	airspeedValue.Value = speed
	altitudeValue.Value = altitude
	climbValue.Value = climbRate
	bankValue.Value = math.deg(bank)
	headingValue.Value = math.deg(-heading) % 360
	groundedValue.Value = not airborne

	if altitude < Config.ResetHeight then
		resetPlane()
	end
end)
