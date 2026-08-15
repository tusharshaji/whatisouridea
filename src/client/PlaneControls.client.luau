--!strict

-- Input, and the cockpit.
--
-- Readouts are attributes on the local player, so each pilot sees their own
-- aircraft. Input is sampled every frame and sent at a fixed rate; the server
-- owns the flight model and only ever receives axis values.
--
-- Layout follows UiTheme: big numerals with small quiet captions, meters instead
-- of number rows, and an attitude indicator, because with full aerobatics you
-- can genuinely lose track of which way up you are.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("PlaneConfig"))
local Theme = require(Shared:WaitForChild("UiTheme"))

local C = Theme.Colour
local SEND_RATE = 1 / 20

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inputRemote = remotes:WaitForChild("PlaneInput") :: RemoteEvent

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlaneHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local function number(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

--------------------------------------------------------------------------------
-- Instrument cluster
--------------------------------------------------------------------------------

local panel = Theme.panel(
	screenGui,
	UDim2.new(0, 330, 0, 186),
	UDim2.new(0, 26, 1, -212)
)
panel.Visible = false

local throttleBar = Theme.bar(panel, UDim2.new(0, 20, 0, 16), 190, "THROTTLE", C.Accent, C.AccentDeep)
local fuelBar = Theme.bar(panel, UDim2.new(0, 20, 0, 52), 190, "FUEL", C.Good, C.GoodDeep)

local speedValue = Theme.readout(panel, UDim2.new(0, 20, 0, 94), 116, 34, "SPEED")
local altitudeValue = Theme.readout(panel, UDim2.new(0, 20, 0, 146), 92, 17, "ALTITUDE")
local aglValue = Theme.readout(panel, UDim2.new(0, 118, 0, 146), 92, 17, "GROUND")

--------------------------------------------------------------------------------
-- Attitude indicator
--
-- A ViewportFrame looking at a real ground plane, not two rotated Frames. A
-- rotated GuiObject is not clipped by its parent -- not by ClipsDescendants and
-- not by a CanvasGroup -- so a flat version escapes its circle the moment the
-- aircraft banks. The camera must also sit ABOVE the slab: level with it, the
-- top face is edge-on and projects to nothing at all.
--------------------------------------------------------------------------------

local HORIZON_EYE = 30

local horizon = Instance.new("ViewportFrame")
horizon.Size = UDim2.new(0, 88, 0, 88)
horizon.Position = UDim2.new(0, 224, 0, 16)
horizon.BackgroundColor3 = C.Sky
horizon.BorderSizePixel = 0
horizon.Ambient = Color3.fromRGB(255, 255, 255)
horizon.LightColor = Color3.fromRGB(255, 255, 255)
horizon.Parent = panel
Theme.corner(horizon, 999)
Theme.stroke(horizon, C.Line, 0.2)

local groundSlab = Instance.new("Part")
groundSlab.Size = Vector3.new(40000, 20, 40000)
groundSlab.CFrame = CFrame.new(0, -10, 0)
groundSlab.Color = C.Ground
groundSlab.Material = Enum.Material.SmoothPlastic
groundSlab.Anchored = true
groundSlab.Parent = horizon

local horizonCamera = Instance.new("Camera")
horizonCamera.FieldOfView = 80
horizonCamera.Parent = horizon
horizon.CurrentCamera = horizonCamera

-- Fixed aircraft reference over the viewport. Unrotated, so it is safe as UI.
local reticle = Instance.new("Frame")
reticle.Size = UDim2.new(0, 34, 0, 3)
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.new(0, 268, 0, 60)
reticle.BackgroundColor3 = C.Accent
reticle.BorderSizePixel = 0
reticle.ZIndex = 3
reticle.Parent = panel
Theme.corner(reticle, 2)

local attitudeText = Theme.text(panel, Theme.Font.Strong, 12, C.Muted, Enum.TextXAlignment.Center)
attitudeText.Size = UDim2.new(0, 88, 0, 34)
attitudeText.Position = UDim2.new(0, 224, 0, 112)
attitudeText.TextYAlignment = Enum.TextYAlignment.Top

--------------------------------------------------------------------------------
-- Centre warning banner
--------------------------------------------------------------------------------

local alert = Instance.new("Frame")
alert.Size = UDim2.new(0, 420, 0, 52)
alert.AnchorPoint = Vector2.new(0.5, 0.5)
alert.Position = UDim2.fromScale(0.5, 0.19)
alert.BackgroundColor3 = C.Bad
alert.BorderSizePixel = 0
alert.Visible = false
alert.Parent = screenGui
Theme.corner(alert, 10)
local alertGradient = Theme.gradient(alert, C.Bad, C.BadDeep)
local alertStroke = Theme.stroke(alert, C.Bad, 0.4)

local alertText = Theme.text(alert, Theme.Font.Display, 22, Color3.fromRGB(26, 20, 18), Enum.TextXAlignment.Center)
alertText.Size = UDim2.fromScale(1, 1)

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local helpButton = Instance.new("TextButton")
helpButton.Size = UDim2.new(0, 46, 0, 46)
helpButton.Position = UDim2.new(1, -74, 0, 150)
helpButton.BackgroundColor3 = C.InkRaised
helpButton.BorderSizePixel = 0
helpButton.Font = Theme.Font.Display
helpButton.TextSize = 20
helpButton.TextColor3 = C.Text
helpButton.Text = "?"
helpButton.AutoButtonColor = true
helpButton.Parent = screenGui
Theme.corner(helpButton, 12)
Theme.stroke(helpButton, C.Line, 0.3)

--------------------------------------------------------------------------------
-- Mode, under the help button
--
-- On the side of the screen rather than in the hangar, because switching is
-- something you do when you have had enough of dying, and that is rarely the
-- moment you are parked at the runway with the shop open.
--------------------------------------------------------------------------------

local modeButton = Instance.new("TextButton")
modeButton.Size = UDim2.new(0, 46, 0, 46)
modeButton.Position = UDim2.new(1, -74, 0, 204)
modeButton.BackgroundColor3 = C.InkRaised
modeButton.BorderSizePixel = 0
modeButton.Font = Theme.Font.Display
modeButton.TextSize = 22
modeButton.TextColor3 = C.Text
modeButton.Text = "\u{2708}"
modeButton.AutoButtonColor = true
modeButton.Parent = screenGui
Theme.corner(modeButton, 12)
local modeStroke = Theme.stroke(modeButton, C.Line, 0.3)

local modeCaption = Theme.text(screenGui, Theme.Font.Strong, 10, C.Muted, Enum.TextXAlignment.Center)
modeCaption.Size = UDim2.new(0, 90, 0, 14)
modeCaption.Position = UDim2.new(1, -96, 0, 252)

-- Lit only in casual, so the default state is as quiet as the help button next
-- to it and being in the odd mode is the thing that stands out.
local function refreshMode()
	if player:GetAttribute("Mode") == "casual" then
		modeButton.BackgroundColor3 = C.Sky
		modeButton.TextColor3 = C.OnAccent
		modeStroke.Color = C.Sky
		modeCaption.Text = "CASUAL"
		modeCaption.TextColor3 = C.Sky
	else
		modeButton.BackgroundColor3 = C.InkRaised
		modeButton.TextColor3 = C.Text
		modeStroke.Color = C.Line
		modeCaption.Text = "COURSE"
		modeCaption.TextColor3 = C.Muted
	end
end

modeButton.Activated:Connect(function()
	local casual = player:GetAttribute("Mode") == "casual"
	inputRemote:FireServer({ mode = if casual then "course" else "casual" })
end)

player:GetAttributeChangedSignal("Mode"):Connect(refreshMode)
refreshMode()

local helpPanel = Theme.panel(
	screenGui,
	UDim2.new(0, 306, 0, 0),
	UDim2.new(1, -344, 0, 150)
)
helpPanel.AutomaticSize = Enum.AutomaticSize.Y
helpPanel.Visible = false
Theme.padding(helpPanel, 16, 18, 18, 18)

local helpList = Instance.new("UIListLayout")
helpList.Padding = UDim.new(0, 3)
helpList.SortOrder = Enum.SortOrder.LayoutOrder
helpList.Parent = helpPanel

local helpOrder = 0
local function helpRow(text: string, font: Enum.Font, size: number, colour: Color3)
	helpOrder += 1
	local label = Theme.text(helpPanel, font, size, colour)
	label.Size = UDim2.new(1, 0, 0, size + 7)
	label.Text = text
	label.LayoutOrder = helpOrder
end

local function helpGap()
	helpOrder += 1
	local spacer = Instance.new("Frame")
	spacer.Size = UDim2.new(1, 0, 0, 8)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = helpOrder
	spacer.Parent = helpPanel
end

-- Derived from the config, so the panel can never disagree with the bindings.
local NOSE_UP_KEY = if Config.InvertPitch then "S" else "W"
local NOSE_DOWN_KEY = if Config.InvertPitch then "W" else "S"

helpRow("FLYING", Theme.Font.Display, 15, C.Accent)
helpRow("Up / Down     Throttle", Theme.Font.Body, 13, C.Text)
helpRow(`{NOSE_UP_KEY}             Nose up`, Theme.Font.Body, 13, C.Text)
helpRow(`{NOSE_DOWN_KEY}             Nose down`, Theme.Font.Body, 13, C.Text)
helpRow("A / D         Roll", Theme.Font.Body, 13, C.Text)
helpRow("Q / E         Rudder", Theme.Font.Body, 13, C.Text)
helpRow("R             Restart run", Theme.Font.Body, 13, C.Text)
helpRow("B             Hangar, at the runway", Theme.Font.Body, 13, C.Text)
helpRow("Space         Get out", Theme.Font.Body, 13, C.Text)
helpRow("F             Get back in", Theme.Font.Body, 13, C.Text)
helpGap()
helpRow("RIDING ALONG", Theme.Font.Display, 15, C.Accent)
helpRow("Every aircraft has a back seat. Walk up", Theme.Font.Body, 12, C.Muted)
helpRow("to a parked one and hold F to get in.", Theme.Font.Body, 12, C.Muted)
helpRow("Jump to get out. If they crash, so do", Theme.Font.Body, 12, C.Muted)
helpRow("you. F on your own aircraft puts you", Theme.Font.Body, 12, C.Muted)
helpRow("back in the cockpit.", Theme.Font.Body, 12, C.Muted)
helpGap()
helpRow("MODE", Theme.Font.Display, 15, C.Accent)
helpRow("The plane button on the right switches", Theme.Font.Body, 12, C.Muted)
helpRow("between Course and Casual. Casual has", Theme.Font.Body, 12, C.Muted)
helpRow("no gates, no crashing and endless fuel,", Theme.Font.Body, 12, C.Muted)
helpRow("and scores nothing. Switching either", Theme.Font.Body, 12, C.Muted)
helpRow("way starts a fresh run.", Theme.Font.Body, 12, C.Muted)
helpGap()
helpRow("CAMERA", Theme.Font.Display, 15, C.Accent)
helpRow("Right drag    Look around", Theme.Font.Body, 13, C.Text)
helpRow("Scroll        Zoom", Theme.Font.Body, 13, C.Text)
helpGap()
helpRow(`Hold {NOSE_UP_KEY} through the vertical and the`, Theme.Font.Body, 12, C.Muted)
helpRow("aircraft loops. The wings only level", Theme.Font.Body, 12, C.Muted)
helpRow("themselves while upright, so inverted", Theme.Font.Body, 12, C.Muted)
helpRow("flight holds.", Theme.Font.Body, 12, C.Muted)
helpGap()
helpRow("Watch GROUND, not ALTITUDE. Fuel", Theme.Font.Body, 12, C.Muted)
helpRow("burns with throttle; empty means you", Theme.Font.Body, 12, C.Muted)
helpRow("glide.", Theme.Font.Body, 12, C.Muted)

helpButton.Activated:Connect(function()
	local opening = not helpPanel.Visible
	helpPanel.Visible = opening

	if opening then
		helpPanel.Position = UDim2.new(1, -320, 0, 150)
		TweenService:Create(
			helpPanel,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(1, -344, 0, 150) }
		):Play()
	end
end)

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

-- Arrows are the throttle. W and S are pitch: W noses up, S noses down.
-- Set PlaneConfig.InvertPitch to swap those two if you want a real stick.
local KEY_THROTTLE_UP = Enum.KeyCode.Up
local KEY_THROTTLE_DOWN = Enum.KeyCode.Down
local KEY_PITCH_UP = Enum.KeyCode.W
local KEY_PITCH_DOWN = Enum.KeyCode.S
local KEY_TURN_LEFT = Enum.KeyCode.A
local KEY_TURN_RIGHT = Enum.KeyCode.D
local KEY_YAW_LEFT = Enum.KeyCode.Q
local KEY_YAW_RIGHT = Enum.KeyCode.E

local function axis(negative: Enum.KeyCode, positive: Enum.KeyCode): number
	local value = 0
	if UserInputService:IsKeyDown(positive) then
		value += 1
	end
	if UserInputService:IsKeyDown(negative) then
		value -= 1
	end
	return value
end

-- Your aircraft, and only while you are sitting in the front of it. A passenger
-- in somebody else's back seat gets the chase camera and nothing else: the
-- instruments are all attributes on the local player, so showing them to a
-- passenger would show them their own parked aeroplane's readings.
local function flownPlane(): Model?
	local folder = Workspace:FindFirstChild("Planes")
	if not folder then
		return nil
	end

	local plane = folder:FindFirstChild(`Plane_{player.UserId}`)
	if not plane then
		return nil
	end

	local seat = plane:FindFirstChild("PilotSeat")
	if not seat or not seat:IsA("VehicleSeat") then
		return nil
	end

	local occupant = seat.Occupant
	if not occupant or occupant.Parent ~= player.Character then
		return nil
	end

	return plane :: Model
end

-- True when you are riding in the back of anybody's aircraft.
local function ridingAlong(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return seat ~= nil and seat.Name == "PassengerSeat"
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		inputRemote:FireServer({ reset = true })
	end
end)

--------------------------------------------------------------------------------
-- Per frame
--------------------------------------------------------------------------------

local flashClock = 0
local sinceSend = 0

RunService.Heartbeat:Connect(function(dt)
	local plane = flownPlane()
	panel.Visible = plane ~= nil
	if not plane then
		-- The help button stays, so the controls can be read on foot.
		if ridingAlong() then
			alert.Visible = true
			alertText.Text = "RIDING ALONG — JUMP TO GET OUT"
			alertText.TextColor3 = Color3.fromRGB(26, 20, 18)
			alert.BackgroundColor3 = C.Accent
			alertGradient.Color = ColorSequence.new(C.Accent, C.AccentDeep)
			alertStroke.Color = C.Accent
			alert.BackgroundTransparency = 0.02
		else
			alert.Visible = false
		end
		return
	end

	local throttle = number("Throttle")
	local fuel = number("Fuel")
	local capacity = math.max(number("FuelCapacity"), 1)
	local fuelFraction = math.clamp(fuel / capacity, 0, 1)
	local agl = number("HeightAboveGround")
	local speed = number("Airspeed")
	local grounded = player:GetAttribute("Grounded") == true
	local engineOut = player:GetAttribute("EngineOut") == true
	local crashed = player:GetAttribute("Crashed") == true
	local casual = player:GetAttribute("Mode") == "casual"

	Theme.setBar(throttleBar, throttle, C.Accent, C.AccentDeep)
	throttleBar.value.Text = string.format("%d%%", throttle * 100)

	if casual then
		-- Full and blue, and reading as a symbol rather than a number, so it is
		-- obvious at a glance that the gauge is not being flown to.
		Theme.setBar(fuelBar, 1, C.Sky, C.Accent)
		fuelBar.value.Text = "∞"
		fuelBar.caption.TextColor3 = C.Muted
	else
		local fuelColour, fuelDeep
		if fuelFraction <= 0.001 then
			fuelColour, fuelDeep = C.Bad, C.BadDeep
		elseif fuelFraction < Config.FuelWarnFraction then
			fuelColour, fuelDeep = C.Warn, C.WarnDeep
		else
			fuelColour, fuelDeep = C.Good, C.GoodDeep
		end
		Theme.setBar(fuelBar, fuelFraction, fuelColour, fuelDeep)
		fuelBar.value.Text = string.format("%d%%", fuelFraction * 100)
		fuelBar.caption.TextColor3 = if fuelFraction < Config.FuelWarnFraction then fuelColour else C.Muted
	end

	speedValue.Text = string.format("%d", speed)
	altitudeValue.Text = string.format("%d", number("Altitude"))
	aglValue.Text = string.format("%d", agl)
	aglValue.TextColor3 = if agl < 60 and not grounded then C.Warn else C.Text

	local bank = number("Bank")
	local pitch = number("Pitch")
	attitudeText.Text = string.format("%+d°  PITCH\n%+d°  BANK", math.floor(pitch + 0.5), math.floor(bank + 0.5))

	-- Point the little camera the way the aeroplane is pointing, minus the
	-- heading. Rx(pitch) * Rz(bank) is the attitude with yaw dropped, which is
	-- exactly what an attitude indicator shows. Rotation is about the eye point,
	-- so the translation comes first.
	horizonCamera.CFrame = CFrame.new(0, HORIZON_EYE, 0)
		* CFrame.Angles(math.rad(pitch), 0, math.rad(bank))

	----------------------------------------------------------------------------
	-- Warnings, in priority order, flashing so they cannot be tuned out
	----------------------------------------------------------------------------
	flashClock += dt
	local flash = math.sin(flashClock * 9) > -0.2

	local message: string? = nil
	local colour, deep = C.Bad, C.BadDeep

	if crashed then
		message = "CRASHED"
	elseif engineOut and not casual then
		message = "ENGINE OUT — NO FUEL"
	elseif fuelFraction < Config.FuelWarnFraction and not grounded and not casual then
		message, colour, deep = string.format("LOW FUEL — %d%%", fuelFraction * 100), C.Warn, C.WarnDeep
	elseif not grounded and agl < 60 and not casual then
		-- Nothing to pull up from in casual, and a red bar flashing at a pilot
		-- deliberately flying low through a valley is just noise.
		message = "TERRAIN — PULL UP"
	elseif grounded and speed >= Config.TakeoffSpeed then
		message, colour, deep = `ROTATE — HOLD {NOSE_UP_KEY}`, C.Good, C.GoodDeep
	elseif grounded and speed < Config.TakeoffSpeed then
		message, colour, deep = "HOLD UP ARROW FOR THROTTLE", C.Good, C.GoodDeep
	end

	if message then
		alert.Visible = true
		alertText.Text = message
		alert.BackgroundColor3 = colour
		alertGradient.Color = ColorSequence.new(colour, deep)
		alertStroke.Color = colour
		-- Steady for the friendly ones, flashing for the ones that matter.
		local urgent = colour ~= C.Good
		alert.BackgroundTransparency = if urgent and not flash then 0.65 else 0.02
	else
		alert.Visible = false
	end

	----------------------------------------------------------------------------
	sinceSend += dt
	if sinceSend < SEND_RATE then
		return
	end
	sinceSend = 0

	local pitchInput = axis(KEY_PITCH_DOWN, KEY_PITCH_UP)
	if Config.InvertPitch then
		pitchInput = -pitchInput
	end

	inputRemote:FireServer({
		throttle = axis(KEY_THROTTLE_DOWN, KEY_THROTTLE_UP),
		pitch = pitchInput,
		roll = axis(KEY_TURN_LEFT, KEY_TURN_RIGHT),
		yaw = axis(KEY_YAW_LEFT, KEY_YAW_RIGHT),
	})
end)
