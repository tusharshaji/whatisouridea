--!strict

-- Score, combo, and this pilot's own gates.
--
-- The rings are built here rather than on the server, and that is the whole
-- point: a client only ever receives its own course, so it only ever sees and
-- flies its own rings. When gates were real server instances every pilot could
-- see everybody's, and one person flying through one scored it for the room.
-- Building them locally also spares the network thirty rings times eighteen
-- parts times every player on the server.
--
-- Detection still happens on the server from the same gate data. Nothing here is
-- authoritative; it only draws.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RingConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RingConfig"))
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UpgradeConfig"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local courseRemote = remotes:WaitForChild("CourseData") :: RemoteEvent
local eventRemote = remotes:WaitForChild("GameEvent") :: RemoteEvent

local ACCENT = Color3.fromRGB(255, 132, 48)
local WHITE = Color3.fromRGB(235, 235, 240)
local DIM = Color3.fromRGB(150, 150, 162)
local GREEN = Color3.fromRGB(120, 230, 140)
local RED = Color3.fromRGB(240, 96, 96)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RingHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- Scoreboard
--------------------------------------------------------------------------------

-- Parked off the top of the screen. It drops into view on takeoff, so the
-- runway is uncluttered and the scoreboard arriving is itself the cue that the
-- run has started.
local BOARD_HIDDEN = UDim2.new(0.5, -160, 0, -150)
local BOARD_SHOWN = UDim2.new(0.5, -160, 0, 16)

local board = Instance.new("Frame")
board.Size = UDim2.new(0, 320, 0, 126)
board.Position = BOARD_HIDDEN
board.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
board.BackgroundTransparency = 0.2
board.BorderSizePixel = 0
board.Parent = screenGui

local boardStroke = Instance.new("UIStroke")
boardStroke.Color = Color3.fromRGB(60, 66, 78)
boardStroke.Parent = board

local boardCorner = Instance.new("UICorner")
boardCorner.CornerRadius = UDim.new(0, 8)
boardCorner.Parent = board

local boardPadding = Instance.new("UIPadding")
boardPadding.PaddingTop = UDim.new(0, 8)
boardPadding.PaddingLeft = UDim.new(0, 14)
boardPadding.PaddingRight = UDim.new(0, 14)
boardPadding.Parent = board

local boardLayout = Instance.new("UIListLayout")
boardLayout.Padding = UDim.new(0, 1)
boardLayout.SortOrder = Enum.SortOrder.LayoutOrder
boardLayout.Parent = board

local function boardLabel(order: number, height: number, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.Font = Enum.Font.Code
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = ""
	label.LayoutOrder = order
	label.Parent = board
	return label
end

local scoreLabel = boardLabel(1, 34, 30, WHITE)
local comboLabel = boardLabel(2, 20, 17, ACCENT)
local gateLabel = boardLabel(3, 18, 14, DIM)
local pointsLabel = boardLabel(4, 18, 14, GREEN)
local planeLabel = boardLabel(5, 18, 13, DIM)

--------------------------------------------------------------------------------
-- Gate marker
--------------------------------------------------------------------------------

local marker = Instance.new("TextLabel")
marker.Size = UDim2.new(0, 200, 0, 46)
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.BackgroundTransparency = 1
marker.TextColor3 = ACCENT
marker.Font = Enum.Font.Code
marker.TextSize = 15
marker.Text = ""
marker.Visible = false
marker.Parent = screenGui

local arrow = Instance.new("TextLabel")
arrow.Size = UDim2.new(0, 40, 0, 40)
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.BackgroundTransparency = 1
arrow.TextColor3 = ACCENT
arrow.Font = Enum.Font.GothamBold
arrow.TextSize = 30
arrow.Text = "\u{25B2}"
arrow.Visible = false
arrow.Parent = screenGui

--------------------------------------------------------------------------------
-- Popups
--------------------------------------------------------------------------------

local function popup(text: string, color: Color3, size: number)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 460, 0, 56)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.36, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.Font = Enum.Font.Code
	label.TextSize = size
	label.Text = text
	label.TextStrokeTransparency = 0.6
	label.Parent = screenGui

	local rise = TweenService:Create(
		label,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.28, 0), TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	rise.Completed:Connect(function()
		label:Destroy()
	end)
	rise:Play()
end

--------------------------------------------------------------------------------
-- The course, drawn locally
--------------------------------------------------------------------------------

type Gate = {
	center: Vector3,
	normal: Vector3,
	radius: number,
	parts: { BasePart },
	faded: boolean,
}

local gates: { Gate } = {}
local courseFolder: Folder? = nil

local function clearCourse()
	if courseFolder then
		courseFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "MyCourse"
	folder.Parent = Workspace
	courseFolder = folder

	table.clear(gates)
end

local function buildGate(index: number, center: Vector3, normal: Vector3, radius: number): Gate
	local model = Instance.new("Model")
	model.Name = string.format("Gate%02d", index)

	-- lookAt puts the LookVector along the direction of travel, so the ring lies
	-- in the frame's XY plane.
	local frame = CFrame.lookAt(center, center + normal)
	local chord = 2 * radius * math.tan(math.pi / RingConfig.Segments)
	local parts: { BasePart } = {}

	for i = 1, RingConfig.Segments do
		local angle = (i / RingConfig.Segments) * math.pi * 2

		local part = Instance.new("Part")
		part.Name = "Segment"
		part.Size = Vector3.new(chord, RingConfig.Thickness, RingConfig.Thickness)
		-- Rotate about the frame's Z, then step out along the rotated Y: the
		-- part lands on the rim with its long axis running round it.
		part.CFrame = frame * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius, 0)
		part.Anchored = true
		part.Material = Enum.Material.Neon
		part.Color = RingConfig.UpcomingColor
		part.Transparency = RingConfig.UpcomingTransparency
		part.CastShadow = false
		part.Locked = true

		-- Invisible to physics and to every raycast. CanQuery above all: these
		-- exist only on this client, but a queryable ring would still register
		-- as solid ground to anything the client casts.
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false

		part.Parent = model
		table.insert(parts, part)
	end

	model.Parent = courseFolder
	return { center = center, normal = normal, radius = radius, parts = parts, faded = false }
end

-- Light the active gate, dim the next few, hide the rest. All thirty at once is
-- a wall of rings you cannot pick a line through.
--
-- A gate that has just been flown fades away rather than snapping to a colour:
-- it flashes green on the way out, which is the confirmation you get without
-- having to look at the scoreboard, and then leaves the sky clear behind you.
local function styleGate(gate: Gate, color: Color3, transparency: number, animate: boolean)
	for _, part in gate.parts do
		part.Color = color
		if animate then
			TweenService:Create(
				part,
				TweenInfo.new(RingConfig.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = transparency }
			):Play()
		else
			part.Transparency = transparency
		end
	end
end

local function refreshVisibility()
	local active = player:GetAttribute("ActiveGate") or 1

	for index, gate in gates do
		if index < active then
			-- Fade out behind you. Only the one just passed animates; anything
			-- further back is already gone.
			local justPassed = index == active - 1
			if justPassed and not gate.faded then
				gate.faded = true
				styleGate(gate, RingConfig.PassedColor, 1, true)
			elseif not justPassed then
				gate.faded = true
				styleGate(gate, RingConfig.PassedColor, 1, false)
			end
		elseif index == active then
			gate.faded = false
			styleGate(gate, RingConfig.ActiveColor, 0, false)
		elseif index <= active + RingConfig.VisibleAhead then
			gate.faded = false
			styleGate(gate, RingConfig.UpcomingColor, RingConfig.UpcomingTransparency, false)
		else
			gate.faded = false
			styleGate(gate, RingConfig.UpcomingColor, 1, false)
		end
	end
end

courseRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	clearCourse()
	for index, entry in payload do
		if typeof(entry.p) == "Vector3" and typeof(entry.n) == "Vector3" then
			table.insert(gates, buildGate(index, entry.p, entry.n, entry.r))
		end
	end
	refreshVisibility()
end)

player:GetAttributeChangedSignal("ActiveGate"):Connect(refreshVisibility)

eventRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.kind == "pass" then
		local grade = if payload.accuracy > 0.8
			then "PERFECT"
			elseif payload.accuracy > 0.5 then "CLEAN"
			else "GATE"
		popup(string.format("%s  +%d", grade, payload.points), GREEN, 30)
	elseif payload.kind == "miss" then
		popup("MISSED", RED, 28)
	elseif payload.kind == "crash" then
		popup("CRASHED  -  RUN LOST", RED, 32)
	elseif payload.kind == "complete" then
		popup(string.format("LAP %d CLEAR  +%d", payload.lap, payload.bonus), ACCENT, 30)
	elseif payload.kind == "bought" then
		popup(payload.name .. " EQUIPPED", GREEN, 26)
	elseif payload.kind == "denied" then
		popup(payload.reason, RED, 24)
	end
end)

--------------------------------------------------------------------------------
-- Per-frame
--------------------------------------------------------------------------------

local function pinToEdge(direction: Vector2, middle: Vector2, margin: number): Vector2
	local unit = if direction.Magnitude > 1e-4 then direction.Unit else Vector2.new(0, -1)
	local reachX = if math.abs(unit.X) > 1e-4 then (middle.X - margin) / math.abs(unit.X) else math.huge
	local reachY = if math.abs(unit.Y) > 1e-4 then (middle.Y - margin) / math.abs(unit.Y) else math.huge
	return middle + unit * math.min(reachX, reachY)
end

local function number(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

-- Slide the scoreboard in on takeoff and out again on landing.
local boardShown = false

local function setBoardShown(shown: boolean)
	if shown == boardShown then
		return
	end
	boardShown = shown

	TweenService:Create(
		board,
		TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = if shown then BOARD_SHOWN else BOARD_HIDDEN }
	):Play()
end

RunService.RenderStepped:Connect(function()
	-- Airborne, or already scoring: a pilot who lands mid-run keeps the board.
	setBoardShown(
		player:GetAttribute("Grounded") == false
			or number("Score") > 0
	)

	scoreLabel.Text = string.format("%d", number("Score"))

	local combo = number("Combo")
	if combo > 1 then
		comboLabel.Text = string.format("x%.2f  -  %d IN A ROW", number("Multiplier"), combo)
	else
		comboLabel.Text = string.format("BEST %d", number("Best"))
	end

	local active = number("ActiveGate")
	local total = number("TotalGates")
	gateLabel.Text = string.format("GATE %d / %d", math.min(active, total), total)
	pointsLabel.Text = string.format("%d POINTS TO SPEND", number("Points"))

	local planeId = player:GetAttribute("PlaneId")
	local plane = if type(planeId) == "string" then UpgradeConfig.findPlane(planeId) else nil
	planeLabel.Text = if plane then string.upper(plane.name) .. "  -  B FOR SHOP" else "B FOR SHOP"

	local gate = gates[active]
	local camera = Workspace.CurrentCamera
	if not gate or not camera then
		marker.Visible = false
		arrow.Visible = false
		return
	end

	local projected, onScreen = camera:WorldToViewportPoint(gate.center)
	local viewport = camera.ViewportSize
	local middle = viewport / 2
	local distance = (gate.center - camera.CFrame.Position).Magnitude

	if onScreen and projected.Z > 0 then
		marker.Position = UDim2.new(0, projected.X, 0, projected.Y)
		marker.Text = string.format("%d studs  -  gate %d wide", distance, gate.radius * 2)
		marker.Visible = true
		arrow.Visible = false
	else
		-- Behind the camera the projection mirrors through the middle, so the
		-- raw offset points the wrong way and has to be reversed.
		local offset = Vector2.new(projected.X, projected.Y) - middle
		if projected.Z <= 0 then
			offset = -offset
		end

		local edge = pinToEdge(offset, middle, 70)
		arrow.Position = UDim2.new(0, edge.X, 0, edge.Y)
		arrow.Rotation = math.deg(math.atan2(offset.Y, offset.X)) + 90
		arrow.Visible = true

		marker.Position = UDim2.new(0, edge.X, 0, edge.Y + 34)
		marker.Text = string.format("%d studs", distance)
		marker.Visible = true
	end
end)
