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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RingConfig = require(Shared:WaitForChild("RingConfig"))
local Theme = require(Shared:WaitForChild("UiTheme"))
local UpgradeConfig = require(Shared:WaitForChild("UpgradeConfig"))

local C = Theme.Colour

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local courseRemote = remotes:WaitForChild("CourseData") :: RemoteEvent
local eventRemote = remotes:WaitForChild("GameEvent") :: RemoteEvent

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RingHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local function number(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

--------------------------------------------------------------------------------
-- Scoreboard
--
-- Parked off the top of the screen. It drops in on takeoff, so the runway is
-- uncluttered and the board arriving is itself the cue that the run has begun.
--------------------------------------------------------------------------------

local BOARD_HIDDEN = UDim2.new(0.5, -170, 0, -160)
local BOARD_SHOWN = UDim2.new(0.5, -170, 0, 20)

local board = Theme.panel(screenGui, UDim2.new(0, 340, 0, 122), BOARD_HIDDEN)

local scoreValue = Theme.text(board, Theme.Font.Display, 40, C.Text, Enum.TextXAlignment.Center)
scoreValue.Size = UDim2.new(1, 0, 0, 44)
scoreValue.Position = UDim2.new(0, 0, 0, 10)

local scoreCaption = Theme.text(board, Theme.Font.Strong, 11, C.Muted, Enum.TextXAlignment.Center)
scoreCaption.Size = UDim2.new(1, 0, 0, 12)
scoreCaption.Position = UDim2.new(0, 0, 0, 52)
scoreCaption.Text = "SCORE"

local comboPill, comboLabel = Theme.pill(
	board,
	UDim2.new(0, 128, 0, 24),
	UDim2.new(0.5, -64, 0, 70),
	C.Accent
)
comboPill.Visible = false

local gatePill, gateLabel = Theme.pill(board, UDim2.new(0, 96, 0, 22), UDim2.new(0, 16, 0, 90), C.Muted)
local pointsPill, pointsLabel = Theme.pill(board, UDim2.new(0, 110, 0, 22), UDim2.new(1, -126, 0, 90), C.Good)

-- Sits in the gap between the two pills rather than across the whole board,
-- which would put it underneath both of them.
local planeLabel = Theme.text(board, Theme.Font.Strong, 11, C.Muted, Enum.TextXAlignment.Center)
planeLabel.Size = UDim2.new(0, 100, 0, 22)
planeLabel.Position = UDim2.new(0, 120, 0, 90)

--------------------------------------------------------------------------------
-- Gate marker
--------------------------------------------------------------------------------

local marker = Theme.text(screenGui, Theme.Font.Strong, 14, C.Accent, Enum.TextXAlignment.Center)
marker.Size = UDim2.new(0, 220, 0, 44)
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.TextStrokeTransparency = 0.55
marker.Visible = false

local arrow = Theme.text(screenGui, Theme.Font.Display, 30, C.Accent, Enum.TextXAlignment.Center)
arrow.Size = UDim2.new(0, 40, 0, 40)
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.TextStrokeTransparency = 0.5
arrow.Text = "\u{25B2}"
arrow.Visible = false

--------------------------------------------------------------------------------
-- Popups
--------------------------------------------------------------------------------

local function popup(text: string, colour: Color3, size: number)
	local label = Theme.text(screenGui, Theme.Font.Display, size, colour, Enum.TextXAlignment.Center)
	label.Size = UDim2.new(0, 500, 0, 60)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.36, 0)
	label.TextStrokeTransparency = 0.45
	label.Text = text

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

local function styleGate(gate: Gate, colour: Color3, transparency: number, animate: boolean)
	for _, part in gate.parts do
		part.Color = colour
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

-- Light the active gate, dim the next few, hide the rest. All thirty at once is
-- a wall of rings you cannot pick a line through. The one just flown fades away
-- behind you, which is the confirmation you get without looking at the score.
local function refreshVisibility()
	local active = player:GetAttribute("ActiveGate") or 1

	for index, gate in gates do
		if index < active then
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
		popup(string.format("%s   +%d", grade, payload.points), C.Good, 32)
	elseif payload.kind == "miss" then
		popup("MISSED", C.Bad, 28)
	elseif payload.kind == "crash" then
		popup("CRASHED — RUN LOST", C.Bad, 32)
	elseif payload.kind == "complete" then
		popup(string.format("LAP %d CLEAR   +%d", payload.lap, payload.bonus), C.Accent, 32)
	elseif payload.kind == "bought" then
		popup(string.upper(payload.name) .. " EQUIPPED", C.Good, 26)
	elseif payload.kind == "denied" then
		popup(string.upper(payload.reason), C.Bad, 24)
	end
end)

--------------------------------------------------------------------------------
-- Per frame
--------------------------------------------------------------------------------

local function pinToEdge(direction: Vector2, middle: Vector2, margin: number): Vector2
	local unit = if direction.Magnitude > 1e-4 then direction.Unit else Vector2.new(0, -1)
	local reachX = if math.abs(unit.X) > 1e-4 then (middle.X - margin) / math.abs(unit.X) else math.huge
	local reachY = if math.abs(unit.Y) > 1e-4 then (middle.Y - margin) / math.abs(unit.Y) else math.huge
	return middle + unit * math.min(reachX, reachY)
end

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
	setBoardShown(player:GetAttribute("Grounded") == false or number("Score") > 0)

	scoreValue.Text = string.format("%d", number("Score"))

	local combo = number("Combo")
	if combo > 1 then
		comboPill.Visible = true
		comboLabel.Text = string.format("×%.2f   %d IN A ROW", number("Multiplier"), combo)
		scoreCaption.Text = "SCORE"
	else
		comboPill.Visible = false
		scoreCaption.Text = string.format("SCORE     BEST %d", number("Best"))
	end

	local active = number("ActiveGate")
	local total = number("TotalGates")
	gateLabel.Text = string.format("GATE %d/%d", math.min(active, total), total)
	pointsLabel.Text = string.format("%d PTS", number("Points"))

	local planeId = player:GetAttribute("PlaneId")
	local plane = if type(planeId) == "string" then UpgradeConfig.findPlane(planeId) else nil
	planeLabel.Text = if plane then string.upper(plane.name) else ""

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
		marker.Text = string.format("%d studs   •   %d wide", distance, gate.radius * 2)
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
