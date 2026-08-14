--!strict

-- Input, and the cockpit.
--
-- Readouts are attributes on the local player, so each pilot sees their own
-- aircraft. Input is sampled every frame and sent at a fixed rate; the server
-- owns the flight model and only ever receives axis values.
--
-- The panel is laid out like an instrument cluster rather than a list of
-- numbers: throttle and fuel are bars because a bar can be read at a glance
-- while you are busy flying, and an artificial horizon is there because with
-- full aerobatics you can genuinely lose track of which way up you are.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlaneConfig"))

local SEND_RATE = 1 / 20

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inputRemote = remotes:WaitForChild("PlaneInput") :: RemoteEvent

local ACCENT = Color3.fromRGB(255, 132, 48)
local WHITE = Color3.fromRGB(235, 235, 240)
local DIM = Color3.fromRGB(140, 140, 152)
local GREEN = Color3.fromRGB(120, 230, 140)
local RED = Color3.fromRGB(240, 96, 96)
local WARN = Color3.fromRGB(255, 200, 90)
local GLASS = Color3.fromRGB(10, 12, 16)

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
-- Instrument cluster, bottom left
--------------------------------------------------------------------------------

local panel = Instance.new("Frame")
panel.Name = "Cluster"
panel.Size = UDim2.new(0, 292, 0, 196)
panel.Position = UDim2.new(0, 24, 1, -220)
panel.BackgroundColor3 = GLASS
panel.BackgroundTransparency = 0.2
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(60, 66, 78)
panelStroke.Thickness = 1
panelStroke.Parent = panel

-- A labelled horizontal bar: the readable version of a row of hashes.
local function makeGauge(
	label: string,
	position: UDim2,
	width: number,
	fill: Color3
): (TextLabel, Frame, TextLabel)
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, width, 0, 34)
	holder.Position = position
	holder.BackgroundTransparency = 1
	holder.Parent = panel

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 13)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.Code
	caption.TextSize = 11
	caption.TextColor3 = DIM
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Text = label
	caption.Parent = holder

	local value = Instance.new("TextLabel")
	value.Size = UDim2.new(1, 0, 0, 13)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.Code
	value.TextSize = 11
	value.TextColor3 = WHITE
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Text = ""
	value.Parent = holder

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 12)
	track.Position = UDim2.new(0, 0, 0, 17)
	track.BackgroundColor3 = Color3.fromRGB(38, 40, 48)
	track.BorderSizePixel = 0
	track.Parent = holder

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 3)
	trackCorner.Parent = track

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 0, 1, 0)
	bar.BackgroundColor3 = fill
	bar.BorderSizePixel = 0
	bar.Parent = track

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 3)
	barCorner.Parent = bar

	return caption, bar, value
end

local _, throttleBar, throttleValue = makeGauge("THROTTLE", UDim2.new(0, 16, 0, 14), 168, ACCENT)
local fuelCaption, fuelBar, fuelValue = makeGauge("FUEL", UDim2.new(0, 16, 0, 56), 168, GREEN)

-- Artificial horizon.
--
-- Built as a ViewportFrame looking at a real ground plane, rather than as two
-- coloured Frames that get rotated. Rotating flat UI does not work here: a
-- rotated GuiObject is not clipped by its parent -- not by ClipsDescendants and
-- not by a CanvasGroup either -- so the oversized sky panel stayed neatly inside
-- its circle while level and painted itself across the screen the instant the
-- aircraft banked.
--
-- A ViewportFrame renders a 3D scene and is always clipped to its own
-- rectangle, so there is nothing to escape. It is also simply a better horizon:
-- rolling and pitching a camera is what an attitude indicator actually is, and
-- it stays correct past vertical and upside down for free.
local horizonHolder = Instance.new("ViewportFrame")
horizonHolder.Size = UDim2.new(0, 80, 0, 80)
horizonHolder.Position = UDim2.new(0, 196, 0, 14)
horizonHolder.BackgroundColor3 = Color3.fromRGB(64, 118, 176) -- the sky itself
horizonHolder.BackgroundTransparency = 0
horizonHolder.BorderSizePixel = 0
horizonHolder.Ambient = Color3.fromRGB(255, 255, 255)
horizonHolder.LightColor = Color3.fromRGB(255, 255, 255)
horizonHolder.Parent = panel

local horizonCorner = Instance.new("UICorner")
horizonCorner.CornerRadius = UDim.new(1, 0)
horizonCorner.Parent = horizonHolder

-- Ground: a very large slab with its top face exactly at y = 0. The camera sits
-- at y = 0 too, so with the aircraft level the horizon lands dead centre.
local groundSlab = Instance.new("Part")
groundSlab.Size = Vector3.new(4000, 2, 4000)
groundSlab.CFrame = CFrame.new(0, -1, 0)
groundSlab.Color = Color3.fromRGB(112, 82, 52)
groundSlab.Material = Enum.Material.SmoothPlastic
groundSlab.Anchored = true
groundSlab.Parent = horizonHolder

local horizonCamera = Instance.new("Camera")
horizonCamera.FieldOfView = 80
horizonCamera.Parent = horizonHolder
horizonHolder.CurrentCamera = horizonCamera

-- Fixed aircraft reference, drawn over the viewport. Unrotated, so it is safe
-- as flat UI.
local reticle = Instance.new("Frame")
reticle.Size = UDim2.new(0, 34, 0, 2)
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.new(0, 236, 0, 54)
reticle.BackgroundColor3 = ACCENT
reticle.BorderSizePixel = 0
reticle.ZIndex = 3
reticle.Parent = panel

local function makeReadout(order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 128, 0, 16)
	label.Position = UDim2.new(0, 16, 0, 100 + order * 17)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextColor3 = WHITE
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = panel
	return label
end

local speedRow = makeReadout(0)
local altitudeRow = makeReadout(1)
local aglRow = makeReadout(2)

local attitudeRow = Instance.new("TextLabel")
attitudeRow.Size = UDim2.new(0, 130, 0, 50)
attitudeRow.Position = UDim2.new(0, 152, 0, 102)
attitudeRow.BackgroundTransparency = 1
attitudeRow.Font = Enum.Font.Code
attitudeRow.TextSize = 13
attitudeRow.TextColor3 = DIM
attitudeRow.TextXAlignment = Enum.TextXAlignment.Left
attitudeRow.TextYAlignment = Enum.TextYAlignment.Top
attitudeRow.Text = ""
attitudeRow.Parent = panel

--------------------------------------------------------------------------------
-- Centre warning bar. Deliberately in the way.
--------------------------------------------------------------------------------

local alertBar = Instance.new("Frame")
alertBar.Name = "Alert"
alertBar.Size = UDim2.new(0, 460, 0, 46)
alertBar.AnchorPoint = Vector2.new(0.5, 0.5)
alertBar.Position = UDim2.fromScale(0.5, 0.2)
alertBar.BackgroundColor3 = RED
alertBar.BackgroundTransparency = 0.15
alertBar.BorderSizePixel = 0
alertBar.Visible = false
alertBar.Parent = screenGui

local alertCorner = Instance.new("UICorner")
alertCorner.CornerRadius = UDim.new(0, 6)
alertCorner.Parent = alertBar

local alertText = Instance.new("TextLabel")
alertText.Size = UDim2.fromScale(1, 1)
alertText.BackgroundTransparency = 1
alertText.Font = Enum.Font.GothamBold
alertText.TextSize = 22
alertText.TextColor3 = Color3.fromRGB(20, 18, 18)
alertText.Text = ""
alertText.Parent = alertBar

--------------------------------------------------------------------------------
-- Settings, right edge
--------------------------------------------------------------------------------

local settingsButton = Instance.new("TextButton")
settingsButton.Size = UDim2.new(0, 44, 0, 44)
settingsButton.Position = UDim2.new(1, -68, 0, 150)
settingsButton.BackgroundColor3 = GLASS
settingsButton.BackgroundTransparency = 0.2
settingsButton.BorderSizePixel = 0
settingsButton.Font = Enum.Font.GothamBold
settingsButton.TextSize = 20
settingsButton.TextColor3 = WHITE
settingsButton.Text = "?"
settingsButton.AutoButtonColor = true
settingsButton.Parent = screenGui

local settingsCorner = Instance.new("UICorner")
settingsCorner.CornerRadius = UDim.new(0, 8)
settingsCorner.Parent = settingsButton

local settingsStroke = Instance.new("UIStroke")
settingsStroke.Color = Color3.fromRGB(60, 66, 78)
settingsStroke.Parent = settingsButton

-- Height comes from the content, not from a number typed here. A fixed height
-- was smaller than the rows inside it, so the last few lines rendered outside
-- the panel background with nothing behind them.
local settingsPanel = Instance.new("Frame")
settingsPanel.Size = UDim2.new(0, 290, 0, 0)
settingsPanel.AutomaticSize = Enum.AutomaticSize.Y
settingsPanel.Position = UDim2.new(1, -324, 0, 150)
settingsPanel.BackgroundColor3 = GLASS
settingsPanel.BackgroundTransparency = 0.08
settingsPanel.BorderSizePixel = 0
settingsPanel.Visible = false
settingsPanel.Parent = screenGui

local settingsPanelCorner = Instance.new("UICorner")
settingsPanelCorner.CornerRadius = UDim.new(0, 10)
settingsPanelCorner.Parent = settingsPanel

local settingsPanelStroke = Instance.new("UIStroke")
settingsPanelStroke.Color = Color3.fromRGB(60, 66, 78)
settingsPanelStroke.Parent = settingsPanel

local settingsPadding = Instance.new("UIPadding")
settingsPadding.PaddingTop = UDim.new(0, 14)
settingsPadding.PaddingLeft = UDim.new(0, 16)
settingsPadding.PaddingRight = UDim.new(0, 16)
settingsPadding.PaddingBottom = UDim.new(0, 14)
settingsPadding.Parent = settingsPanel

local settingsList = Instance.new("UIListLayout")
settingsList.Padding = UDim.new(0, 4)
settingsList.SortOrder = Enum.SortOrder.LayoutOrder
settingsList.Parent = settingsPanel

local function settingsRow(order: number, text: string, color: Color3, size: number)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.LayoutOrder = order
	label.Parent = settingsPanel
end

settingsRow(1, "CONTROLS", ACCENT, 16)
settingsRow(2, "W / S        throttle", WHITE, 14)
settingsRow(3, "UP / DOWN    pitch, no limit", WHITE, 14)
settingsRow(4, "A / D        roll, no limit", WHITE, 14)
settingsRow(5, "Q / E        rudder", WHITE, 14)
settingsRow(6, "R            restart run", WHITE, 14)
settingsRow(7, "B            hangar (at runway)", WHITE, 14)
settingsRow(8, "", DIM, 6)
settingsRow(9, "CAMERA", ACCENT, 16)
settingsRow(10, "RIGHT DRAG   look around", WHITE, 14)
settingsRow(11, "SCROLL       zoom in / out", WHITE, 14)
settingsRow(12, "             recentres on its own", DIM, 12)
settingsRow(13, "", DIM, 6)
settingsRow(14, "Hold UP through the vertical and", DIM, 12)
settingsRow(15, "the aircraft will loop. Wings level", DIM, 12)
settingsRow(16, "themselves only while upright, so", DIM, 12)
settingsRow(17, "inverted flight holds.", DIM, 12)
settingsRow(18, "", DIM, 6)
settingsRow(19, "Watch AGL, not ALT. Fuel burns", DIM, 12)
settingsRow(20, "with throttle; empty means glide.", DIM, 12)

settingsButton.Activated:Connect(function()
	local opening = not settingsPanel.Visible
	settingsPanel.Visible = opening

	if opening then
		settingsPanel.Position = UDim2.new(1, -300, 0, 150)
		TweenService:Create(
			settingsPanel,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(1, -324, 0, 150) }
		):Play()
	end
end)

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local KEY_THROTTLE_UP = Enum.KeyCode.W
local KEY_THROTTLE_DOWN = Enum.KeyCode.S
local KEY_PITCH_UP = Enum.KeyCode.Up
local KEY_PITCH_DOWN = Enum.KeyCode.Down
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

local function ownPlane(): Model?
	local folder = Workspace:FindFirstChild("Planes")
	if not folder then
		return nil
	end
	return folder:FindFirstChild(`Plane_{player.UserId}`) :: Model?
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
	local plane = ownPlane()
	panel.Visible = plane ~= nil
	settingsButton.Visible = plane ~= nil
	if not plane then
		alertBar.Visible = false
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

	throttleBar.Size = UDim2.new(math.clamp(throttle, 0, 1), 0, 1, 0)
	throttleValue.Text = string.format("%d%%", throttle * 100)

	fuelBar.Size = UDim2.new(fuelFraction, 0, 1, 0)
	fuelValue.Text = string.format("%d%%", fuelFraction * 100)
	fuelBar.BackgroundColor3 = if fuelFraction <= 0.001
		then RED
		elseif fuelFraction < Config.FuelWarnFraction then WARN
		else GREEN
	fuelCaption.TextColor3 = if fuelFraction < Config.FuelWarnFraction then WARN else DIM

	speedRow.Text = string.format("SPD %5.0f", speed)
	altitudeRow.Text = string.format("ALT %5.0f", number("Altitude"))
	aglRow.Text = string.format("AGL %5.0f", agl)
	aglRow.TextColor3 = if agl < 60 and not grounded then WARN else WHITE

	local bank = number("Bank")
	local pitch = number("Pitch")
	attitudeRow.Text = string.format(
		"PITCH %+4.0f\nBANK  %+4.0f\nHDG    %3.0f",
		pitch,
		bank,
		number("Heading")
	)

	-- Horizon: point the little camera the way the aeroplane is pointing, minus
	-- the heading. Rx(pitch) * Rz(bank) is the attitude with yaw dropped, which
	-- is exactly what an attitude indicator shows.
	horizonCamera.CFrame = CFrame.Angles(math.rad(pitch), 0, math.rad(bank))

	----------------------------------------------------------------------------
	-- Warnings, in priority order, flashing so they cannot be tuned out
	----------------------------------------------------------------------------
	flashClock += dt
	local flash = math.sin(flashClock * 9) > -0.2

	local message, colour = nil :: string?, RED

	if crashed then
		message, colour = "CRASHED", RED
	elseif engineOut then
		message, colour = "ENGINE OUT  -  NO FUEL", RED
	elseif fuelFraction < Config.FuelWarnFraction and not grounded then
		message, colour = string.format("LOW FUEL  %d%%", fuelFraction * 100), WARN
	elseif not grounded and agl < 60 then
		message, colour = "TERRAIN  -  PULL UP", RED
	elseif grounded and speed >= Config.TakeoffSpeed then
		message, colour = "ROTATE", GREEN
	elseif grounded and speed < Config.TakeoffSpeed then
		message, colour = "HOLD W TO TAKE OFF", GREEN
	end

	if message then
		alertBar.Visible = true
		alertText.Text = message
		alertBar.BackgroundColor3 = colour
		-- Steady for the friendly ones, flashing for the ones that matter.
		local urgent = colour ~= GREEN
		alertBar.BackgroundTransparency = if urgent and not flash then 0.7 else 0.15
	else
		alertBar.Visible = false
	end

	----------------------------------------------------------------------------
	sinceSend += dt
	if sinceSend < SEND_RATE then
		return
	end
	sinceSend = 0

	inputRemote:FireServer({
		throttle = axis(KEY_THROTTLE_DOWN, KEY_THROTTLE_UP),
		pitch = axis(KEY_PITCH_DOWN, KEY_PITCH_UP),
		roll = axis(KEY_TURN_LEFT, KEY_TURN_RIGHT),
		yaw = axis(KEY_YAW_LEFT, KEY_YAW_RIGHT),
	})
end)
