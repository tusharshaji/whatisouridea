--!strict

-- The loading screen.
--
-- Lives in ReplicatedFirst so it runs before the rest of the game has
-- replicated, which is the whole point: without it the player sits on Roblox's
-- own loading screen and is then dropped into a half-built world, watching
-- terrain stream in and their aircraft appear underneath them.
--
-- It deliberately requires nothing from ReplicatedStorage. Anything in Shared
-- may not have replicated yet, and a WaitForChild here would leave the player
-- staring at a blank screen for exactly as long as the thing it is meant to be
-- covering. The handful of colours and fonts below are therefore repeated from
-- UiTheme rather than imported. Keep them in step by eye.
--
-- Play stays grey until every required step reports ready, so the button going
-- green is a real signal rather than a countdown.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local INK = Color3.fromRGB(15, 17, 23)
local INK_RAISED = Color3.fromRGB(28, 32, 41)
local TROUGH = Color3.fromRGB(40, 45, 56)
local NEUTRAL = Color3.fromRGB(52, 59, 73)
local LINE = Color3.fromRGB(62, 70, 86)
local TEXT = Color3.fromRGB(244, 246, 250)
local MUTED = Color3.fromRGB(146, 155, 172)
local ACCENT = Color3.fromRGB(255, 138, 46)
local GOOD = Color3.fromRGB(92, 214, 143)
local GOOD_DEEP = Color3.fromRGB(38, 152, 92)
local SKY = Color3.fromRGB(112, 174, 240)
local SKY_DEEP = Color3.fromRGB(56, 108, 172)
local ON_ACCENT = Color3.fromRGB(22, 18, 12)

local DISPLAY = Enum.Font.GothamBlack
local STRONG = Enum.Font.GothamBold
local BODY = Enum.Font.GothamMedium

-- Never hold someone hostage to a step that is not coming. Past this, the
-- button goes green regardless and the game copes. Generous, because the server
-- reads saved progress out of a DataStore before it builds anyone an aircraft,
-- and a retrying DataStore can take a good few seconds on its own.
local PATIENCE = 45

-- The default screen goes first and before anything that can yield, or Roblox
-- shows its own until this script gets around to it.
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- Deliberately noisy. If this line is missing from Output then the script is not
-- in the place at all -- which means default.project.json reached Studio without
-- a `rojo serve` restart, and no amount of fixing the code below will help.
print("[LoadingScreen] running")

-- LocalPlayer is not guaranteed to exist yet in ReplicatedFirst -- that is the
-- price of running this early. Indexing it while it is nil throws, the script
-- dies, and the player gets no loading screen at all and no error they can see.
local player = Players.LocalPlayer
while not player do
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	player = Players.LocalPlayer
end

--------------------------------------------------------------------------------
-- Screen
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.Parent = player:WaitForChild("PlayerGui")

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = INK
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local sheen = Instance.new("UIGradient")
sheen.Color = ColorSequence.new(Color3.fromRGB(30, 36, 48), INK)
sheen.Rotation = 90
sheen.Parent = backdrop

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 60)
title.Position = UDim2.new(0, 0, 0.32, 0)
title.BackgroundTransparency = 1
title.Font = DISPLAY
title.TextSize = 46
title.TextColor3 = TEXT
title.Text = "WHATISOURIDEA"
title.Parent = backdrop

local tagline = Instance.new("TextLabel")
tagline.Size = UDim2.new(1, 0, 0, 22)
tagline.Position = UDim2.new(0, 0, 0.32, 58)
tagline.BackgroundTransparency = 1
tagline.Font = BODY
tagline.TextSize = 15
tagline.TextColor3 = MUTED
tagline.Text = "Fly the gates. Do not hit the mountain."
tagline.Parent = backdrop

-- Progress
local trough = Instance.new("Frame")
trough.Size = UDim2.new(0, 420, 0, 8)
trough.Position = UDim2.new(0.5, -210, 0.5, 40)
trough.BackgroundColor3 = TROUGH
trough.BorderSizePixel = 0
trough.Parent = backdrop

local troughCorner = Instance.new("UICorner")
troughCorner.CornerRadius = UDim.new(0, 4)
troughCorner.Parent = trough

local fill = Instance.new("Frame")
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = ACCENT
fill.BorderSizePixel = 0
fill.Parent = trough

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 4)
fillCorner.Parent = fill

local status = Instance.new("TextLabel")
status.Size = UDim2.new(0, 420, 0, 20)
status.Position = UDim2.new(0.5, -210, 0.5, 56)
status.BackgroundTransparency = 1
status.Font = STRONG
status.TextSize = 12
status.TextColor3 = MUTED
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "Connecting"
status.Parent = backdrop

-- The two ways in. Each is built as a fill plus a separate label, because a
-- UIGradient tints its parent's text as well as its background, and a gradient
-- straight on a TextButton drags pale labels down until they are unreadable.
type Choice = {
	button: TextButton,
	fill: Frame,
	gradient: UIGradient,
	stroke: UIStroke,
	label: TextLabel,
	caption: TextLabel,
}

local function choice(offsetX: number, waiting: string): Choice
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 210, 0, 54)
	button.Position = UDim2.new(0.5, offsetX, 0.5, 100)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Active = false
	button.Parent = backdrop

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = NEUTRAL
	fill.BorderSizePixel = 0
	fill.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = fill

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(NEUTRAL, INK_RAISED)
	gradient.Rotation = 90
	gradient.Parent = fill

	local stroke = Instance.new("UIStroke")
	stroke.Color = LINE
	stroke.Transparency = 0.4
	stroke.Parent = fill

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = DISPLAY
	label.TextSize = 18
	label.TextColor3 = MUTED
	label.Text = waiting
	label.ZIndex = 2
	label.Parent = button

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 16)
	caption.Position = UDim2.new(0, 0, 1, 8)
	caption.BackgroundTransparency = 1
	caption.Font = BODY
	caption.TextSize = 12
	caption.TextColor3 = MUTED
	caption.Text = ""
	caption.Parent = button

	return {
		button = button,
		fill = fill,
		gradient = gradient,
		stroke = stroke,
		label = label,
		caption = caption,
	}
end

local play = choice(-218, "LOADING")
local casual = choice(8, "LOADING")

--------------------------------------------------------------------------------
-- What "ready" means
--------------------------------------------------------------------------------

local function ownPlane(): Instance?
	local folder = Workspace:FindFirstChild("Planes")
	if not folder then
		return nil
	end
	return folder:FindFirstChild(`Plane_{player.UserId}`)
end

type Step = { label: string, ready: () -> boolean }

local steps: { Step } = {
	{
		label = "Connecting",
		ready = function()
			return game:IsLoaded()
		end,
	},
	{
		label = "Loading the island",
		ready = function()
			return Workspace:FindFirstChild("Terrain") ~= nil
				and Workspace:FindFirstChild("Runway") ~= nil
		end,
	},
	{
		-- This one covers the DataStore read as well as the build: the server
		-- will not put an aeroplane on the runway until it knows which one you
		-- own, so the aircraft appearing is the signal that both are done.
		label = "Loading your hangar",
		ready = function()
			return ownPlane() ~= nil
		end,
	},
	{
		label = "Plotting your course",
		ready = function()
			return (player:GetAttribute("TotalGates") or 0) > 0
		end,
	},
}

--------------------------------------------------------------------------------

local function arm(item: Choice, text: string, caption: string, colour: Color3, deep: Color3)
	item.label.Text = text
	item.label.TextColor3 = ON_ACCENT
	item.caption.Text = caption
	item.fill.BackgroundColor3 = colour
	item.gradient.Color = ColorSequence.new(colour, deep)
	item.stroke.Color = colour
	item.stroke.Transparency = 0.2
	item.button.Active = true

	-- Hover by hand. AutoButtonColor needs an opaque background and this button
	-- is a transparent shell around the fill that actually carries the colour.
	item.button.MouseEnter:Connect(function()
		item.fill.BackgroundTransparency = 0.15
	end)
	item.button.MouseLeave:Connect(function()
		item.fill.BackgroundTransparency = 0
	end)
end

local function setReady()
	arm(play, "PLAY", "Gates, fuel, and a mountain", GOOD, GOOD_DEEP)
	arm(casual, "CASUAL", "Just fly. Nothing can kill you", SKY, SKY_DEEP)
end

local finished = false

local function dismiss()
	if finished then
		return
	end
	finished = true

	local fade = TweenService:Create(
		backdrop,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)

	for _, item in backdrop:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			TweenService:Create(item, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		elseif item:IsA("Frame") then
			TweenService:Create(item, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		elseif item:IsA("UIStroke") then
			TweenService:Create(item, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end
	end

	fade.Completed:Connect(function()
		gui:Destroy()
	end)
	fade:Play()
end

-- Told to the server only when casual is chosen, and only on the way out. By
-- then everything has replicated, so this is a FindFirstChild and not the
-- WaitForChild this file spends so much effort avoiding -- and if the remote
-- somehow is not there, the player still gets into the game, just in course
-- mode. They can switch in the hangar.
local function chooseMode(mode: string)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local input = remotes and remotes:FindFirstChild("PlaneInput")
	if input and input:IsA("RemoteEvent") then
		input:FireServer({ mode = mode })
	end
end

play.button.Activated:Connect(function()
	if play.button.Active then
		dismiss()
	end
end)

casual.button.Activated:Connect(function()
	if casual.button.Active then
		chooseMode("casual")
		dismiss()
	end
end)

--------------------------------------------------------------------------------
-- Wait for it
--------------------------------------------------------------------------------

task.spawn(function()
	-- Preload the interface itself, so the first frame after Play is not spent
	-- fetching fonts and images.
	pcall(function()
		ContentProvider:PreloadAsync({ backdrop })
	end)

	local started = os.clock()
	local ready = false

	while not ready do
		local done = 0
		local current = "Almost there"

		for _, step in steps do
			local ok = false
			-- A step that errors is a step that is not ready, not a crash.
			pcall(function()
				ok = step.ready()
			end)

			if ok then
				done += 1
			else
				current = step.label
				break
			end
		end

		local fraction = done / #steps
		fill.Size = UDim2.new(fraction, 0, 1, 0)

		local waited = os.clock() - started
		if done >= #steps then
			ready = true
		elseif waited > PATIENCE then
			-- Something is not coming. Let them in anyway rather than trapping
			-- them behind a grey button for ever.
			status.Text = "Taking longer than usual — you can go in"
			ready = true
		else
			status.Text = string.format("%s… (%d/%d)", current, done, #steps)
		end

		if not ready then
			RunService.Heartbeat:Wait()
		end
	end

	fill.Size = UDim2.new(1, 0, 1, 0)
	if not string.find(status.Text, "longer") then
		status.Text = "Ready"
	end
	setReady()
end)
