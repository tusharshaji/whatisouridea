--!strict

-- The hangar. Toggled with B, and only usable at the runway.
--
-- Prices and effects are read from UpgradeConfig, the same table the server
-- validates purchases against, so what is on the button is what gets charged.
-- Nothing here is trusted: the client sends an id and the server decides whether
-- the pilot can afford it and what it does.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UiTheme"))
local UpgradeConfig = require(Shared:WaitForChild("UpgradeConfig"))

local C = Theme.Colour

local player = Players.LocalPlayer
local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyUpgrade") :: RemoteEvent

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopUi"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shade.BackgroundTransparency = 0.4
shade.BorderSizePixel = 0
shade.Parent = screenGui

local window = Theme.panel(
	screenGui,
	UDim2.new(0, 660, 0, 500),
	UDim2.new(0.5, -330, 0.5, -250)
)
Theme.padding(window, 20, 22, 18, 22)

local title = Theme.text(window, Theme.Font.Display, 26, C.Text)
title.Size = UDim2.new(1, 0, 0, 30)
title.Text = "HANGAR"

local pointsChip, pointsLabel = Theme.pill(
	window,
	UDim2.new(0, 150, 0, 28),
	UDim2.new(1, -150, 0, 2),
	C.Good
)
pointsChip.ZIndex = 2

local subtitle = Theme.text(window, Theme.Font.Body, 13, C.Muted)
subtitle.Size = UDim2.new(1, 0, 0, 18)
subtitle.Position = UDim2.new(0, 0, 0, 32)
subtitle.Text = "Buying an aircraft rebuilds it and restarts your run."

local scroller = Instance.new("ScrollingFrame")
scroller.Size = UDim2.new(1, 0, 1, -84)
scroller.Position = UDim2.new(0, 0, 0, 58)
scroller.BackgroundTransparency = 1
scroller.BorderSizePixel = 0
scroller.ScrollBarThickness = 4
scroller.ScrollBarImageColor3 = C.Line
scroller.CanvasSize = UDim2.new()
scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroller.Parent = window

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroller

local footer = Theme.text(window, Theme.Font.Body, 12, C.Muted)
footer.Size = UDim2.new(1, 0, 0, 18)
footer.Position = UDim2.new(0, 0, 1, -18)
footer.Text = "B to close"

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function heading(text: string)
	local label = Theme.text(scroller, Theme.Font.Display, 14, C.Accent)
	label.Size = UDim2.new(1, -12, 0, 26)
	label.Text = text
	label.LayoutOrder = nextOrder()
end

type Row = { title: TextLabel, blurb: TextLabel, stats: TextLabel, button: TextButton }

local function makeRow(): Row
	local card = Theme.card(scroller, 74)
	card.Size = UDim2.new(1, -12, 0, 74)
	card.LayoutOrder = nextOrder()

	local titleLabel = Theme.text(card, Theme.Font.Display, 16, C.Text)
	titleLabel.Size = UDim2.new(1, -190, 0, 20)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local blurb = Theme.text(card, Theme.Font.Body, 12, C.Muted)
	blurb.Size = UDim2.new(1, -190, 0, 16)
	blurb.Position = UDim2.new(0, 16, 0, 32)

	local stats = Theme.text(card, Theme.Font.Strong, 11, C.Line)
	stats.Size = UDim2.new(1, -190, 0, 14)
	stats.Position = UDim2.new(0, 16, 0, 50)
	stats.TextColor3 = Color3.fromRGB(120, 130, 148)

	local button = Theme.button(card, 44, "", C.Accent, C.AccentDeep)
	button.Size = UDim2.new(0, 150, 0, 44)
	button.Position = UDim2.new(1, -166, 0, 15)

	return { title = titleLabel, blurb = blurb, stats = stats, button = button }
end

local planeRows: { [string]: Row } = {}
local upgradeRows: { [string]: Row } = {}

heading("AIRCRAFT")
for _, plane in UpgradeConfig.Planes do
	local row = makeRow()
	row.title.Text = plane.name
	row.blurb.Text = plane.blurb
	row.button.Activated:Connect(function()
		buyRemote:FireServer({ kind = "plane", id = plane.id })
	end)
	planeRows[plane.id] = row
end

heading("UPGRADES")
for _, upgrade in UpgradeConfig.Upgrades do
	local row = makeRow()
	row.blurb.Text = upgrade.blurb
	row.button.Activated:Connect(function()
		buyRemote:FireServer({ kind = "upgrade", id = upgrade.id })
	end)
	upgradeRows[upgrade.id] = row
end

--------------------------------------------------------------------------------
-- Away from the runway
--------------------------------------------------------------------------------

local awayNotice = Theme.panel(
	screenGui,
	UDim2.new(0, 480, 0, 130),
	UDim2.new(0.5, -240, 0.5, -65)
)
awayNotice.Visible = false

local awayTitle = Theme.text(awayNotice, Theme.Font.Display, 20, C.Warn, Enum.TextXAlignment.Center)
awayTitle.Size = UDim2.new(1, 0, 0, 26)
awayTitle.Position = UDim2.new(0, 0, 0, 30)
awayTitle.Text = "THE HANGAR IS AT THE RUNWAY"

local awayBody = Theme.text(awayNotice, Theme.Font.Body, 14, C.Muted, Enum.TextXAlignment.Center)
awayBody.Size = UDim2.new(1, -40, 0, 40)
awayBody.Position = UDim2.new(0, 20, 0, 62)
awayBody.TextWrapped = true
awayBody.Text = "Land back at the strip to buy anything."

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

	pointsLabel.Text = string.format("%d POINTS", points)

	-- Said here rather than anywhere else, because the hangar is the one screen
	-- where somebody is about to spend an evening's earnings and deserves to
	-- know the server could not read their save and will not be writing one.
	if player:GetAttribute("ProgressSaving") == false then
		footer.Text = "B to close     ⚠ SAVING IS OFF — nothing bought here will be kept"
		footer.TextColor3 = C.Warn
	else
		footer.Text = "B to close"
		footer.TextColor3 = C.Muted
	end

	for _, plane in UpgradeConfig.Planes do
		local row = planeRows[plane.id]
		row.stats.Text = string.format(
			"SPEED ×%.2f     TURN ×%.2f     PITCH ×%.2f     FUEL ×%.2f",
			plane.speed,
			plane.handling,
			plane.climb,
			plane.fuel
		)

		if plane.id == current then
			Theme.setButton(row.button, "FLYING", C.Neutral, C.NeutralDeep, true)
		elseif owned[plane.id] then
			Theme.setButton(row.button, "SELECT", C.Good, C.GoodDeep)
		elseif points >= plane.cost then
			Theme.setButton(row.button, string.format("BUY   %d", plane.cost), C.Accent, C.AccentDeep)
		else
			Theme.setButton(row.button, string.format("%d", plane.cost), C.Trough, C.NeutralDeep, true)
		end
	end

	for _, upgrade in UpgradeConfig.Upgrades do
		local row = upgradeRows[upgrade.id]
		local level = player:GetAttribute("Level_" .. upgrade.id) or 0
		local cost = UpgradeConfig.upgradeCost(upgrade, level)

		row.title.Text = upgrade.name
		row.stats.Text = string.format(
			"LEVEL %d / %d     +%d%% EACH",
			level,
			upgrade.levels,
			math.floor(upgrade.perLevel * 100 + 0.5)
		)

		if not cost then
			Theme.setButton(row.button, "MAXED", C.Neutral, C.NeutralDeep, true)
		elseif points >= cost then
			Theme.setButton(row.button, string.format("BUY   %d", cost), C.Accent, C.AccentDeep)
		else
			Theme.setButton(row.button, string.format("%d", cost), C.Trough, C.NeutralDeep, true)
		end
	end
end

for _, name in { "Points", "PlaneId", "OwnedPlanes" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
for _, upgrade in UpgradeConfig.Upgrades do
	player:GetAttributeChangedSignal("Level_" .. upgrade.id):Connect(refresh)
end

local function atSpawn(): boolean
	return player:GetAttribute("AtSpawn") == true
end

local function setOpen(open: boolean)
	screenGui.Enabled = open
	if not open then
		return
	end

	local here = atSpawn()
	window.Visible = here
	awayNotice.Visible = not here

	if here then
		refresh()
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.B then
		setOpen(not screenGui.Enabled)
	end
end)

-- Fly away with the hangar open and it changes to the notice, rather than
-- leaving a window full of buttons the server is going to refuse.
player:GetAttributeChangedSignal("AtSpawn"):Connect(function()
	if screenGui.Enabled then
		setOpen(true)
	end
end)

refresh()
