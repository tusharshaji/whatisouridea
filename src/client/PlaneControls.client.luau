--!strict

-- Pilot input and instruments. Input is sampled every frame and sent at a fixed
-- rate; the server owns the flight model and only ever receives axis values.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlaneConfig"))

local SEND_RATE = 1 / 20

local player = Players.LocalPlayer
local inputRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlaneInput") :: RemoteEvent

local plane = Workspace:WaitForChild("Airplane")
local seat = plane:WaitForChild("PilotSeat") :: VehicleSeat
local state = plane:WaitForChild("State")

local throttleValue = state:WaitForChild("Throttle") :: NumberValue
local airspeedValue = state:WaitForChild("Airspeed") :: NumberValue
local altitudeValue = state:WaitForChild("Altitude") :: NumberValue
local climbValue = state:WaitForChild("ClimbRate") :: NumberValue
local bankValue = state:WaitForChild("Bank") :: NumberValue
local headingValue = state:WaitForChild("Heading") :: NumberValue
local groundedValue = state:WaitForChild("Grounded") :: BoolValue

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlaneHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 240, 0, 210)
panel.Position = UDim2.new(0, 20, 1, -230)
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

local ACCENT = Color3.fromRGB(255, 132, 48)
local WHITE = Color3.fromRGB(235, 235, 240)
local GREEN = Color3.fromRGB(120, 230, 140)

local title = addRow(1, 16, ACCENT)
title.Text = "FLIGHT"

local throttleRow = addRow(2, 15, WHITE)
local speedRow = addRow(3, 15, WHITE)
local altitudeRow = addRow(4, 15, WHITE)
local climbRow = addRow(5, 15, WHITE)
local bankRow = addRow(6, 15, WHITE)
local headingRow = addRow(7, 15, WHITE)
local statusRow = addRow(8, 15, GREEN)

local hint = addRow(9, 12, Color3.fromRGB(160, 160, 170))
hint.Size = UDim2.new(1, 0, 0, 42)
hint.TextWrapped = true
hint.Text = "W/S throttle  -  arrows climb/dive\nA/D turn  -  Q/E rudder  -  R reset"

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

local function isFlying(): boolean
	local occupant = seat.Occupant
	return occupant ~= nil and occupant.Parent == player.Character
end

local function bar(fraction: number): string
	local filled = math.floor(math.clamp(fraction, 0, 1) * 10 + 0.5)
	return string.rep("#", filled) .. string.rep(".", 10 - filled)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.R and isFlying() then
		inputRemote:FireServer({ reset = true })
	end
end)

local sinceSend = 0

RunService.Heartbeat:Connect(function(dt)
	local flying = isFlying()
	panel.Visible = flying
	if not flying then
		return
	end

	throttleRow.Text = string.format("THR  %s %3d%%", bar(throttleValue.Value), throttleValue.Value * 100)
	speedRow.Text = string.format("SPD  %6.0f studs/s", airspeedValue.Value)
	altitudeRow.Text = string.format("ALT  %6.0f studs", altitudeValue.Value)
	climbRow.Text = string.format("VS   %+6.0f studs/s", climbValue.Value)
	bankRow.Text = string.format("BNK  %+6.0f deg", bankValue.Value)
	headingRow.Text = string.format("HDG  %6.0f deg", headingValue.Value)

	if not groundedValue.Value then
		statusRow.Text = ""
	elseif airspeedValue.Value >= Config.TakeoffSpeed then
		statusRow.Text = "READY - PULL UP"
	else
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
