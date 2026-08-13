--!strict

-- The shop. Toggled with B.
--
-- Prices and effects are read from UpgradeConfig, the same table the server
-- validates purchases against, so what is on the button is what gets charged.
-- Nothing here is trusted: the client sends an id and the server decides whether
-- the pilot can afford it and what it does.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UpgradeConfig"))

local player = Players.LocalPlayer
local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyUpgrade") :: RemoteEvent

local ACCENT = Color3.fromRGB(255, 132, 48)
local WHITE = Color3.fromRGB(235, 235, 240)
local DIM = Color3.fromRGB(150, 150, 162)
local GREEN = Color3.fromRGB(120, 230, 140)
local PANEL = Color3.fromRGB(18, 18, 22)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopUi"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shade.BackgroundTransparency = 0.45
shade.BorderSizePixel = 0
shade.Parent = screenGui

local window = Instance.new("Frame")
window.Size = UDim2.new(0, 620, 0, 470)
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.BackgroundColor3 = PANEL
window.BorderSizePixel = 0
window.Parent = screenGui

local windowCorner = Instance.new("UICorner")
windowCorner.CornerRadius = UDim.new(0, 10)
windowCorner.Parent = window

local windowPadding = Instance.new("UIPadding")
windowPadding.PaddingTop = UDim.new(0, 14)
windowPadding.PaddingLeft = UDim.new(0, 18)
windowPadding.PaddingRight = UDim.new(0, 18)
windowPadding.PaddingBottom = UDim.new(0, 14)
windowPadding.Parent = window

local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, 0, 0, 28)
header.BackgroundTransparency = 1
header.Font = Enum.Font.Code
header.TextSize = 22
header.TextColor3 = ACCENT
header.TextXAlignment = Enum.TextXAlignment.Left
header.Text = "HANGAR"
header.Parent = window

local pointsLabel = Instance.new("TextLabel")
pointsLabel.Size = UDim2.new(1, 0, 0, 22)
pointsLabel.Position = UDim2.new(0, 0, 0, 28)
pointsLabel.BackgroundTransparency = 1
pointsLabel.Font = Enum.Font.Code
pointsLabel.TextSize = 16
pointsLabel.TextColor3 = GREEN
pointsLabel.TextXAlignment = Enum.TextXAlignment.Left
pointsLabel.Text = ""
pointsLabel.Parent = window

local scroller = Instance.new("ScrollingFrame")
scroller.Size = UDim2.new(1, 0, 1, -84)
scroller.Position = UDim2.new(0, 0, 0, 56)
scroller.BackgroundTransparency = 1
scroller.BorderSizePixel = 0
scroller.ScrollBarThickness = 5
scroller.CanvasSize = UDim2.new()
scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroller.Parent = window

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroller

local footer = Instance.new("TextLabel")
footer.Size = UDim2.new(1, 0, 0, 20)
footer.Position = UDim2.new(0, 0, 1, -20)
footer.BackgroundTransparency = 1
footer.Font = Enum.Font.Code
footer.TextSize = 13
footer.TextColor3 = DIM
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.Text = "B to close  -  upgrades apply to your aircraft immediately"
footer.Parent = window

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function sectionLabel(order: number, text: string)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -10, 0, 26)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 15
	label.TextColor3 = ACCENT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.LayoutOrder = order
	label.Parent = scroller
	return label
end

type Row = {
	frame: Frame,
	title: TextLabel,
	blurb: TextLabel,
	button: TextButton,
}

local function makeRow(order: number): Row
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -10, 0, 62)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.Parent = scroller

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -150, 0, 24)
	title.Position = UDim2.new(0, 12, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Code
	title.TextSize = 16
	title.TextColor3 = WHITE
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local blurb = Instance.new("TextLabel")
	blurb.Size = UDim2.new(1, -150, 0, 20)
	blurb.Position = UDim2.new(0, 12, 0, 32)
	blurb.BackgroundTransparency = 1
	blurb.Font = Enum.Font.Code
	blurb.TextSize = 12
	blurb.TextColor3 = DIM
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.Parent = frame

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 124, 0, 38)
	button.Position = UDim2.new(1, -136, 0, 12)
	button.BackgroundColor3 = ACCENT
	button.BorderSizePixel = 0
	button.Font = Enum.Font.Code
	button.TextSize = 14
	button.TextColor3 = Color3.fromRGB(20, 20, 20)
	button.AutoButtonColor = true
	button.Parent = frame

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 5)
	buttonCorner.Parent = button

	return { frame = frame, title = title, blurb = blurb, button = button }
end

local planeRows: { [string]: Row } = {}
local upgradeRows: { [string]: Row } = {}

local order = 0
order += 1
sectionLabel(order, "AIRCRAFT")

for _, plane in UpgradeConfig.Planes do
	order += 1
	local row = makeRow(order)
	row.title.Text = plane.name
	row.blurb.Text = plane.blurb
	row.button.Activated:Connect(function()
		buyRemote:FireServer({ kind = "plane", id = plane.id })
	end)
	planeRows[plane.id] = row
end

order += 1
sectionLabel(order, "UPGRADES")

for _, upgrade in UpgradeConfig.Upgrades do
	order += 1
	local row = makeRow(order)
	row.blurb.Text = upgrade.blurb
	row.button.Activated:Connect(function()
		buyRemote:FireServer({ kind = "upgrade", id = upgrade.id })
	end)
	upgradeRows[upgrade.id] = row
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local function ownedPlanes(): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	local raw = player:GetAttribute("OwnedPlanes")
	for id in string.gmatch(if type(raw) == "string" then raw else "trainer", "[^,]+") do
		owned[id] = true
	end
	return owned
end

local function refresh()
	local points = player:GetAttribute("Points") or 0
	local current = player:GetAttribute("PlaneId")
	local owned = ownedPlanes()

	pointsLabel.Text = string.format("%d points to spend", points)

	for _, plane in UpgradeConfig.Planes do
		local row = planeRows[plane.id]
		local stats = string.format(
			"spd x%.2f  turn x%.2f  climb x%.2f",
			plane.speed,
			plane.handling,
			plane.climb
		)
		row.title.Text = `{plane.name}   {stats}`

		if plane.id == current then
			row.button.Text = "FLYING"
			row.button.BackgroundColor3 = Color3.fromRGB(70, 80, 95)
		elseif owned[plane.id] then
			row.button.Text = "SELECT"
			row.button.BackgroundColor3 = GREEN
		elseif points >= plane.cost then
			row.button.Text = string.format("BUY  %d", plane.cost)
			row.button.BackgroundColor3 = ACCENT
		else
			row.button.Text = string.format("%d", plane.cost)
			row.button.BackgroundColor3 = Color3.fromRGB(70, 60, 60)
		end
	end

	for _, upgrade in UpgradeConfig.Upgrades do
		local row = upgradeRows[upgrade.id]
		local level = player:GetAttribute("Level_" .. upgrade.id) or 0
		local cost = UpgradeConfig.upgradeCost(upgrade, level)

		row.title.Text = string.format(
			"%s   level %d / %d   (+%d%% each)",
			upgrade.name,
			level,
			upgrade.levels,
			math.floor(upgrade.perLevel * 100 + 0.5)
		)

		if not cost then
			row.button.Text = "MAXED"
			row.button.BackgroundColor3 = Color3.fromRGB(70, 80, 95)
		elseif points >= cost then
			row.button.Text = string.format("BUY  %d", cost)
			row.button.BackgroundColor3 = ACCENT
		else
			row.button.Text = string.format("%d", cost)
			row.button.BackgroundColor3 = Color3.fromRGB(70, 60, 60)
		end
	end
end

for _, name in { "Points", "PlaneId", "OwnedPlanes" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
for _, upgrade in UpgradeConfig.Upgrades do
	player:GetAttributeChangedSignal("Level_" .. upgrade.id):Connect(refresh)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.B then
		screenGui.Enabled = not screenGui.Enabled
		if screenGui.Enabled then
			refresh()
		end
	end
end)

refresh()
