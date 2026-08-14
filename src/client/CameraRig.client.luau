--!strict

-- Chase camera.
--
-- Sits behind and above your own aircraft and aims ahead of the nose rather
-- than at the aeroplane, so the gate you are flying at is in the middle of the
-- screen instead of your own tail.
--
-- Right-drag looks around. It recentres itself after a moment, deliberately: a
-- view the pilot has to remember to put back is a view they eventually fly into
-- a mountain with. Scroll changes the distance.
--
-- Roll is followed only partly. Copying it fully barrel-rolls the whole screen,
-- which is unreadable and makes people ill; ignoring it entirely leaves you with
-- no sense of being inverted at all, which matters now that inverted is
-- something you can be.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlaneConfig"))

local player = Players.LocalPlayer

local yawOffset = 0
local pitchOffset = 0
local distance = Config.CameraDistance
local lastLookAt = 0
local looking = false
local rig: CFrame? = nil

local probe = RaycastParams.new()
probe.FilterType = Enum.RaycastFilterType.Exclude
probe.IgnoreWater = true

local function ownPlane(): Model?
	local folder = Workspace:FindFirstChild("Planes")
	if not folder then
		return nil
	end
	return folder:FindFirstChild(`Plane_{player.UserId}`) :: Model?
end

-- Everything the camera must not collide with or see through: every aircraft,
-- every character, and this client's own ring course.
local function refreshFilter()
	local filter: { Instance } = {}

	local planes = Workspace:FindFirstChild("Planes")
	if planes then
		table.insert(filter, planes)
	end

	local course = Workspace:FindFirstChild("MyCourse")
	if course then
		table.insert(filter, course)
	end

	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(filter, other.Character)
		end
	end

	probe.FilterDescendantsInstances = filter
end

refreshFilter()
Workspace.ChildAdded:Connect(refreshFilter)
Workspace.ChildRemoved:Connect(refreshFilter)
Players.PlayerAdded:Connect(refreshFilter)
Players.PlayerRemoving:Connect(refreshFilter)
player.CharacterAdded:Connect(refreshFilter)

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		looking = true
		-- Pin the pointer while dragging, or it slides off the window and the
		-- drag stops halfway through a turn.
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		looking = false
		lastLookAt = os.clock()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseMovement and looking then
		yawOffset -= input.Delta.X * Config.CameraSensitivity
		pitchOffset = math.clamp(
			pitchOffset - input.Delta.Y * Config.CameraSensitivity,
			-Config.CameraPitchLimit,
			Config.CameraPitchLimit
		)
		lastLookAt = os.clock()
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		distance = math.clamp(
			distance - input.Position.Z * Config.CameraZoomStep,
			Config.CameraMinDistance,
			Config.CameraMaxDistance
		)
	end
end)

--------------------------------------------------------------------------------

local function decay(value: number, rate: number, dt: number): number
	local step = math.abs(value) * (1 - math.exp(-rate * dt)) + 0.0005
	if math.abs(value) <= step then
		return 0
	end
	return value - (if value > 0 then step else -step)
end

RunService:BindToRenderStep("PlaneCamera", Enum.RenderPriority.Camera.Value, function(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local plane = ownPlane()
	local root = plane and (plane.PrimaryPart or plane:FindFirstChild("Fuselage")) :: BasePart?

	if not root then
		-- No aeroplane: hand the camera back to Roblox so walking around works.
		if camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
		end
		rig = nil
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable

	-- Drift the look offsets back to centre once the mouse has been still.
	if not looking and os.clock() - lastLookAt > Config.CameraRecenterDelay then
		yawOffset = decay(yawOffset, Config.CameraRecenterRate, dt)
		pitchOffset = decay(pitchOffset, Config.CameraRecenterRate, dt)
	end

	local planeCFrame = root.CFrame
	local origin = planeCFrame.Position
	local look = planeCFrame.LookVector

	-- Partial roll: blend the aircraft's own up-vector toward world up.
	local up = Vector3.yAxis:Lerp(planeCFrame.UpVector, Config.CameraRollFollow)
	if up.Magnitude < 0.05 or math.abs(up.Unit:Dot(look)) > 0.99 then
		-- Straight up or straight down, where "which way is up" has no answer.
		-- Fall back to the aircraft's own frame, which always has one.
		up = planeCFrame.UpVector
	end

	local base = CFrame.lookAt(origin, origin + look, up.Unit)
	local orbit = base * CFrame.Angles(0, yawOffset, 0) * CFrame.Angles(pitchOffset, 0, 0)
	local wanted = orbit * CFrame.new(0, Config.CameraHeight, distance)

	-- Ease toward the wanted pose rather than snapping, framerate-independently.
	local blend = 1 - math.exp(-Config.CameraStiffness * dt)
	rig = if rig then (rig :: CFrame):Lerp(wanted, blend) else wanted

	local position = (rig :: CFrame).Position

	-- Do not let terrain get between the camera and the aeroplane.
	local toCamera = position - origin
	if toCamera.Magnitude > 0.01 then
		local hit = Workspace:Raycast(origin, toCamera, probe)
		if hit then
			position = hit.Position + hit.Normal * Config.CameraCollisionPadding
		end
	end

	camera.CFrame = CFrame.lookAt(position, origin + look * Config.CameraLookAhead, up.Unit)
	camera.Focus = CFrame.new(origin)
end)
