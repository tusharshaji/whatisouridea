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
local Theme = require(Shared:WaitForChild("UiTheme"))
local UpgradeConfig = require(Shared:WaitForChild("UpgradeConfig"))

local C = Theme.Colour

local player = Players.LocalPlayer
local devRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevAction") :: RemoteEvent

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DevPanel"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local window = Theme.panel(screenGui, UDim2.new(0, 262, 0, 0), UDim2.new(0, 26, 0, 96))
window.AutomaticSize = Enum.AutomaticSize.Y
Theme.padding(window, 16, 14, 16, 14)

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = window

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function heading(text: string)
	local label = Theme.text(window, Theme.Font.Display, 13, C.Good)
	label.Size = UDim2.new(1, 0, 0, 20)
	label.Text = text
	label.LayoutOrder = nextOrder()
end

local function button(text: string, action: string, colour: Color3?, deep: Color3?, id: string?): TextButton
	local element = Theme.button(window, 32, text, colour or C.Neutral, deep or C.NeutralDeep)
	element.LayoutOrder = nextOrder()

	local label = Theme.buttonLabel(element)
	if label then
		label.TextSize = 13
		label.TextColor3 = if colour then C.OnAccent else C.Text
	end

	element.Activated:Connect(function()
		devRemote:FireServer({ action = action, id = id })
	end)

	return element
end

heading("DEVELOPER")
button(string.format("+%d points", DevConfig.PointsGrant), "points")
button("Unlock everything", "unlockAll", C.Good, C.GoodDeep)
button("Max upgrades only", "maxUpgrades")
button("Unlock aircraft only", "unlockPlanes")

heading("AIRCRAFT")
for _, plane in UpgradeConfig.Planes do
	button(`Fly the {plane.name}`, "setPlane", nil, nil, plane.id)
end

heading("FLIGHT")
local invincibleButton = button("Invincible — off", "invincible")
button("Refuel", "refuel")
button("Skip to active gate", "skipGate")
button("New course", "newCourse")

heading("DANGER")
button("Wipe my progress", "wipe", C.Bad, C.BadDeep)

local hint = Theme.text(window, Theme.Font.Body, 11, C.Muted)
hint.Size = UDim2.new(1, 0, 0, 30)
hint.TextWrapped = true
hint.Text = "F4 closes. Studio only, plus the place owner."
hint.LayoutOrder = nextOrder()

--------------------------------------------------------------------------------

local function refreshInvincible()
	local on = player:GetAttribute("Invincible") == true
	if on then
		Theme.setButton(invincibleButton, "Invincible — ON", C.Good, C.GoodDeep)
	else
		Theme.setButton(invincibleButton, "Invincible — off", C.InkRaised, C.Ink, true)
	end
	invincibleButton.TextSize = 13
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
