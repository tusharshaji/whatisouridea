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

-- Play. Built as a fill plus a separate label, because a UIGradient tints its
-- parent's text as well as its background.
local play = Instance.new("TextButton")
play.Size = UDim2.new(0, 220, 0, 54)
play.Position = UDim2.new(0.5, -110, 0.5, 100)
play.BackgroundTransparency = 1
play.Text = ""
play.AutoButtonColor = false
play.Active = false
play.Parent = backdrop

local playFill = Instance.new("Frame")
playFill.Size = UDim2.fromScale(1, 1)
playFill.BackgroundColor3 = NEUTRAL
playFill.BorderSizePixel = 0
playFill.Parent = play

local playCorner = Instance.new("UICorner")
playCorner.CornerRadius = UDim.new(0, 10)
playCorner.Parent = playFill

local playGradient = Instance.new("UIGradient")
playGradient.Color = ColorSequence.new(NEUTRAL, INK_RAISED)
playGradient.Rotation = 90
playGradient.Parent = playFill

local playStroke = Instance.new("UIStroke")
playStroke.Color = LINE
playStroke.Transparency = 0.4
playStroke.Parent = playFill

local playLabel = Instance.new("TextLabel")
playLabel.Size = UDim2.fromScale(1, 1)
playLabel.BackgroundTransparency = 1
playLabel.Font = DISPLAY
playLabel.TextSize = 18
playLabel.TextColor3 = MUTED
playLabel.Text = "LOADING"
playLabel.ZIndex = 2
playLabel.Parent = play

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

local function setPlayReady()
	playLabel.Text = "PLAY"
	playLabel.TextColor3 = ON_ACCENT
	playFill.BackgroundColor3 = GOOD
	playGradient.Color = ColorSequence.new(GOOD, GOOD_DEEP)
	playStroke.Color = GOOD
	playStroke.Transparency = 0.2
	play.Active = true
	play.AutoButtonColor = false

	play.MouseEnter:Connect(function()
		playFill.BackgroundTransparency = 0.15
	end)
	play.MouseLeave:Connect(function()
		playFill.BackgroundTransparency = 0
	end)
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

play.Activated:Connect(function()
	if play.Active then
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
	setPlayReady()
end)
