--!strict

-- Dev panel. F4 to toggle.
--
-- Only drawn if the server has marked this player as a developer, and that flag
-- decides nothing else: every button fires a remote the server re-authorises on
-- arrival. Drawing or not drawing buttons is presentation, not security.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")


local Shared = ReplicatedStorage:WaitForChild("Shared")
local DevConfig = require(Shared:WaitForChild("DevConfig"))
local UpgradeConfig = require(Shared:WaitForChild("UpgradeConfig"))

local player = Players.LocalPlayer
local devRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevAction") :: RemoteEvent

local PANEL = Color3.fromRGB(14, 16, 20)
local ACCENT = Color3.fromRGB(120, 230, 140)
local WHITE = Color3.fromRGB(235, 235, 240)
local DIM = Color3.fromRGB(140, 140, 152)
local DANGER = Color3.fromRGB(210, 80, 80)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DevPanel"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local window = Instance.new("Frame")
window.Size = UDim2.new(0, 250, 0, 430)
window.Position = UDim2.new(0, 24, 0, 90)
window.BackgroundColor3 = PANEL
window.BackgroundTransparency = 0.08
window.BorderSizePixel = 0
window.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = window

local stroke = Instance.new("UIStroke")
stroke.Color = ACCENT
stroke.Transparency = 0.5
stroke.Parent = window

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = window

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 5)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = window

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function heading(text: string)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.TextColor3 = ACCENT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.LayoutOrder = nextOrder()
	label.Parent = window
end

local function button(text: string, action: string, colour: Color3?, id: string?): TextButton
	local element = Instance.new("TextButton")
	element.Size = UDim2.new(1, 0, 0, 28)
	element.BackgroundColor3 = colour or Color3.fromRGB(38, 40, 48)
	element.BorderSizePixel = 0
	element.Font = Enum.Font.Code
	element.TextSize = 13
	element.TextColor3 = WHITE
	element.Text = text
	element.AutoButtonColor = true
	element.LayoutOrder = nextOrder()
	element.Parent = window

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 5)
	buttonCorner.Parent = element

	element.Activated:Connect(function()
		devRemote:FireServer({ action = action, id = id })
	end)

	return element
end

heading("DEV")

-- Read from the same table the server grants from, so the label cannot promise
-- one number and the server hand over another.
button(string.format("+%d points", DevConfig.PointsGrant), "points")
button("Unlock everything", "unlockAll", Color3.fromRGB(40, 70, 48))
button("Max upgrades only", "maxUpgrades")
button("Unlock aircraft only", "unlockPlanes")

heading("AIRCRAFT")
for _, plane in UpgradeConfig.Planes do
	button(`Fly the {plane.name}`, "setPlane", nil, plane.id)
end

heading("FLIGHT")
local invincibleButton = button("Invincible: off", "invincible")
button("Refuel", "refuel")
button("Skip to active gate", "skipGate")
button("New course", "newCourse")

heading("DANGER")
button("Wipe my progress", "wipe", DANGER)

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, 0, 0, 30)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Code
hint.TextSize = 11
hint.TextColor3 = DIM
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = "F4 closes. Studio only, plus the place owner."
hint.LayoutOrder = nextOrder()
hint.Parent = window

--------------------------------------------------------------------------------

local function refreshInvincible()
	local on = player:GetAttribute("Invincible") == true
	invincibleButton.Text = if on then "Invincible: ON" else "Invincible: off"
	invincibleButton.BackgroundColor3 = if on
		then Color3.fromRGB(40, 70, 48)
		else Color3.fromRGB(38, 40, 48)
end

player:GetAttributeChangedSignal("Invincible"):Connect(refreshInvincible)
refreshInvincible()

local function isDev(): boolean
	return player:GetAttribute("IsDev") == true
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.F4 then
		return
	end
	if not isDev() then
		return
	end
	screenGui.Enabled = not screenGui.Enabled
end)
