--!strict

-- Pilot input and instruments.
--
-- Input is sampled every frame and sent at a fixed rate; the server owns the
-- flight model and only ever receives axis values. Readouts come back as
-- attributes on the local player, which is how each pilot sees their own
-- aircraft rather than whichever one happened to be in the world first.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlaneConfig"))

local SEND_RATE = 1 / 20

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inputRemote = remotes:WaitForChild("PlaneInput") :: RemoteEvent

local ACCENT = Color3.fromRGB(255, 132, 48)
local WHITE = Color3.fromRGB(235, 235, 240)
local GREEN = Color3.fromRGB(120, 230, 140)
local RED = Color3.fromRGB(240, 96, 96)
local WARN = Color3.fromRGB(255, 200, 90)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlaneHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 240, 0, 231)
panel.Position = UDim2.new(0, 20, 1, -251)
panel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
panel.BackgroundTransparency = 0.35
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 2)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = panel

local function addRow(order: number, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.Code
	label.TextSize = size
	label.Text = ""
	label.LayoutOrder = order
	label.Parent = panel
	return label
end

local title = addRow(1, 16, ACCENT)
title.Text = "FLIGHT"

local throttleRow = addRow(2, 15, WHITE)
local speedRow = addRow(3, 15, WHITE)
local altitudeRow = addRow(4, 15, WHITE)
local aglRow = addRow(5, 15, WHITE)
local climbRow = addRow(6, 15, WHITE)
local bankRow = addRow(7, 15, WHITE)
local headingRow = addRow(8, 15, WHITE)
local statusRow = addRow(9, 15, GREEN)

local hint = addRow(10, 12, Color3.fromRGB(160, 160, 170))
hint.Size = UDim2.new(1, 0, 0, 42)
hint.TextWrapped = true
hint.Text = "W/S throttle  -  arrows climb/dive\nA/D turn  -  Q/E rudder  -  R restart  -  B shop"

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

-- This pilot's own aircraft, which the server names after their user id.
local function ownPlane(): Model?
	local folder = Workspace:FindFirstChild("Planes")
	if not folder then
		return nil
	end
	return folder:FindFirstChild(`Plane_{player.UserId}`) :: Model?
end

local function bar(fraction: number): string
	local filled = math.floor(math.clamp(fraction, 0, 1) * 10 + 0.5)
	return string.rep("#", filled) .. string.rep(".", 10 - filled)
end

local function number(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		inputRemote:FireServer({ reset = true })
	end
end)

local sinceSend = 0

RunService.Heartbeat:Connect(function(dt)
	local plane = ownPlane()
	panel.Visible = plane ~= nil
	if not plane then
		return
	end

	local agl = number("HeightAboveGround")

	throttleRow.Text = string.format("THR  %s %3d%%", bar(number("Throttle")), number("Throttle") * 100)
	speedRow.Text = string.format("SPD  %6.0f studs/s", number("Airspeed"))
	altitudeRow.Text = string.format("ALT  %6.0f studs", number("Altitude"))
	-- Over terrain this is the number that keeps you alive; ALT alone says
	-- nothing about the mountain immediately below.
	aglRow.Text = string.format("AGL  %6.0f studs", agl)
	climbRow.Text = string.format("VS   %+6.0f studs/s", number("ClimbRate"))
	bankRow.Text = string.format("BNK  %+6.0f deg", number("Bank"))
	headingRow.Text = string.format("HDG  %6.0f deg", number("Heading"))

	if player:GetAttribute("Crashed") then
		statusRow.TextColor3 = RED
		statusRow.Text = "CRASHED - RUN LOST"
	elseif not player:GetAttribute("Grounded") then
		if agl < 60 then
			statusRow.TextColor3 = WARN
			statusRow.Text = "LOW - PULL UP"
		else
			statusRow.Text = ""
		end
	elseif number("Airspeed") >= Config.TakeoffSpeed then
		statusRow.TextColor3 = GREEN
		statusRow.Text = "READY - PULL UP"
	else
		statusRow.TextColor3 = GREEN
		statusRow.Text = "ON RUNWAY - HOLD W"
	end

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
