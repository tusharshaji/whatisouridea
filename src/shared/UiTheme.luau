--!strict

-- One place for how the game looks.
--
-- Every screen used to build its own labels with Font.Code, which is a monospace
-- face meant for source listings. Combined with terminal-style abbreviations it
-- made the whole game read like a debug overlay someone forgot to take out.
--
-- The house style here is the one Roblox games actually use: the Gotham family,
-- big bold numerals with small quiet labels under them, generous corner radii,
-- and a little gradient on anything that would otherwise be a flat rectangle.
--
-- Rules worth keeping to:
--   * numbers are large and set in Display; their labels are small and Muted
--   * nothing is pure black or pure white
--   * a panel gets a radius, a stroke and a gradient, never just a fill
--   * colour carries meaning -- Accent is you, Good is earned, Bad is trouble

local UiTheme = {}

--------------------------------------------------------------------------------
-- Type
--------------------------------------------------------------------------------

UiTheme.Font = {
	Display = Enum.Font.GothamBlack, -- speed, score, anything big
	Strong = Enum.Font.GothamBold, -- labels, buttons, headings
	Body = Enum.Font.GothamMedium, -- descriptions
}

--------------------------------------------------------------------------------
-- Colour
--------------------------------------------------------------------------------

UiTheme.Colour = {
	Ink = Color3.fromRGB(15, 17, 23), -- panel base
	InkRaised = Color3.fromRGB(28, 32, 41), -- cards sitting on a panel
	Trough = Color3.fromRGB(40, 45, 56), -- empty part of a bar
	Line = Color3.fromRGB(62, 70, 86),

	Text = Color3.fromRGB(244, 246, 250),
	Muted = Color3.fromRGB(146, 155, 172),
	OnAccent = Color3.fromRGB(22, 18, 12), -- text on a filled accent button

	Accent = Color3.fromRGB(255, 138, 46),
	AccentDeep = Color3.fromRGB(206, 88, 16),
	Good = Color3.fromRGB(92, 214, 143),
	GoodDeep = Color3.fromRGB(38, 152, 92),
	Warn = Color3.fromRGB(255, 198, 76),
	WarnDeep = Color3.fromRGB(214, 148, 22),
	Bad = Color3.fromRGB(242, 88, 88),
	BadDeep = Color3.fromRGB(180, 40, 40),
	Sky = Color3.fromRGB(72, 128, 190),
	Ground = Color3.fromRGB(124, 92, 58),
}

local C = UiTheme.Colour

--------------------------------------------------------------------------------
-- Small parts
--------------------------------------------------------------------------------

function UiTheme.corner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function UiTheme.stroke(parent: Instance, colour: Color3?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = colour or C.Line
	stroke.Transparency = transparency or 0.35
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

-- A vertical sheen. Subtle on purpose: it should read as a surface catching
-- light, not as a coloured stripe.
function UiTheme.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
	return gradient
end

function UiTheme.padding(parent: Instance, top: number, right: number, bottom: number, left: number)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, top)
	pad.PaddingRight = UDim.new(0, right)
	pad.PaddingBottom = UDim.new(0, bottom)
	pad.PaddingLeft = UDim.new(0, left)
	pad.Parent = parent
	return pad
end

--------------------------------------------------------------------------------
-- Surfaces
--------------------------------------------------------------------------------

function UiTheme.panel(parent: Instance, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = C.Ink
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = parent

	UiTheme.corner(frame, 14)
	UiTheme.stroke(frame, C.Line, 0.4)
	UiTheme.gradient(frame, Color3.fromRGB(34, 39, 50), C.Ink)

	return frame
end

function UiTheme.card(parent: Instance, height: number): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundColor3 = C.InkRaised
	frame.BorderSizePixel = 0
	frame.Parent = parent

	UiTheme.corner(frame, 10)
	UiTheme.stroke(frame, C.Line, 0.6)

	return frame
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

function UiTheme.text(
	parent: Instance,
	font: Enum.Font,
	size: number,
	colour: Color3,
	alignment: Enum.TextXAlignment?
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = colour
	label.TextXAlignment = alignment or Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

-- The house pattern: a big numeral with a small quiet caption beneath it.
-- Returns the value label, since the caption never changes.
function UiTheme.readout(
	parent: Instance,
	position: UDim2,
	width: number,
	valueSize: number,
	caption: string
): TextLabel
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, width, 0, valueSize + 16)
	holder.Position = position
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local value = UiTheme.text(holder, UiTheme.Font.Display, valueSize, C.Text)
	value.Size = UDim2.new(1, 0, 0, valueSize + 2)

	local label = UiTheme.text(holder, UiTheme.Font.Strong, 11, C.Muted)
	label.Size = UDim2.new(1, 0, 0, 12)
	label.Position = UDim2.new(0, 0, 0, valueSize + 2)
	label.Text = caption

	return value
end

--------------------------------------------------------------------------------
-- Bars
--------------------------------------------------------------------------------

export type Bar = {
	fill: Frame,
	gradient: UIGradient,
	caption: TextLabel,
	value: TextLabel,
}

-- A labelled meter: caption on the left, percentage on the right, rounded
-- trough beneath. Replaces a row of hash characters.
function UiTheme.bar(
	parent: Instance,
	position: UDim2,
	width: number,
	caption: string,
	colour: Color3,
	deep: Color3
): Bar
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, width, 0, 30)
	holder.Position = position
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local captionLabel = UiTheme.text(holder, UiTheme.Font.Strong, 11, C.Muted)
	captionLabel.Size = UDim2.new(1, 0, 0, 12)
	captionLabel.Text = caption

	local valueLabel = UiTheme.text(holder, UiTheme.Font.Strong, 12, C.Text, Enum.TextXAlignment.Right)
	valueLabel.Size = UDim2.new(1, 0, 0, 12)

	local trough = Instance.new("Frame")
	trough.Size = UDim2.new(1, 0, 0, 10)
	trough.Position = UDim2.new(0, 0, 0, 17)
	trough.BackgroundColor3 = C.Trough
	trough.BorderSizePixel = 0
	trough.Parent = holder
	UiTheme.corner(trough, 5)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = colour
	fill.BorderSizePixel = 0
	fill.Parent = trough
	UiTheme.corner(fill, 5)

	local fillGradient = UiTheme.gradient(fill, colour, deep)

	return { fill = fill, gradient = fillGradient, caption = captionLabel, value = valueLabel }
end

function UiTheme.setBar(bar: Bar, fraction: number, colour: Color3, deep: Color3)
	bar.fill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
	bar.fill.BackgroundColor3 = colour
	bar.gradient.Color = ColorSequence.new(colour, deep)
end

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

function UiTheme.button(parent: Instance, height: number, text: string, colour: Color3, deep: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, height)
	button.BackgroundColor3 = colour
	button.BorderSizePixel = 0
	button.Font = UiTheme.Font.Strong
	button.TextSize = 14
	button.TextColor3 = C.OnAccent
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = parent

	UiTheme.corner(button, 8)
	UiTheme.gradient(button, colour, deep)

	return button
end

function UiTheme.setButton(button: TextButton, text: string, colour: Color3, deep: Color3, onDark: boolean?)
	button.Text = text
	button.BackgroundColor3 = colour
	button.TextColor3 = if onDark then C.Text else C.OnAccent

	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(colour, deep)
	end
end

-- A small rounded chip, for counters and status.
function UiTheme.pill(parent: Instance, size: UDim2, position: UDim2, colour: Color3): (Frame, TextLabel)
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = colour
	frame.BackgroundTransparency = 0.82
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UiTheme.corner(frame, 999)
	UiTheme.stroke(frame, colour, 0.55)

	local label = UiTheme.text(frame, UiTheme.Font.Strong, 12, colour, Enum.TextXAlignment.Center)
	label.Size = UDim2.fromScale(1, 1)

	return frame, label
end

return UiTheme
