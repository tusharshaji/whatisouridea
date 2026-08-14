-- Measures your island and prints the numbers the course generator needs.
--
-- HOW TO RUN
--   1. Open your place in Roblox Studio (do NOT press Play -- edit mode is fine)
--   2. View tab -> Command Bar
--   3. Paste this whole file in and press Enter
--   4. Copy everything it prints from the Output window
--
-- If the Command Bar will not take a multi-line paste, put this in a Script
-- inside ServerScriptService instead, press Play, read the output, then delete
-- the script again.
--
-- Read-only. It creates nothing, moves nothing and saves nothing.

local Workspace = game:GetService("Workspace")

local TOP = 6000 -- cast from well above anything
local DROP = 14000 -- ...down through everything

local extents = Workspace.Terrain.MaxExtents
local exMinX, exMaxX = extents.Min.X * 4, extents.Max.X * 4
local exMinZ, exMaxZ = extents.Min.Z * 4, extents.Max.Z * 4
local exMinY, exMaxY = extents.Min.Y * 4, extents.Max.Y * 4

print("==================== MAP REPORT ====================")
print(string.format(
	"Terrain.MaxExtents (what the game currently reads):\n" ..
	"    X %d .. %d      Z %d .. %d      Y %d .. %d",
	exMinX, exMaxX, exMinZ, exMaxZ, exMinY, exMaxY
))

-- Two passes. A wide coarse sweep finds roughly where the land is, then a finer
-- sweep measures it properly. A single fixed box cannot do this: too small and
-- the island runs off the edge and reports the edge as its own boundary, too
-- large and a fine enough scan takes all day.
local SEARCH = 16000
local COARSE = 320

-- Ignore the aeroplane; it is not scenery.
local skip: { Instance } = {}
local airplane = Workspace:FindFirstChild("Airplane")
if airplane then
	table.insert(skip, airplane)
end
local planes = Workspace:FindFirstChild("Planes")
if planes then
	table.insert(skip, planes)
end

local solidOnly = RaycastParams.new()
solidOnly.FilterType = Enum.RaycastFilterType.Exclude
solidOnly.FilterDescendantsInstances = skip
solidOnly.IgnoreWater = true

local includeWater = RaycastParams.new()
includeWater.FilterType = Enum.RaycastFilterType.Exclude
includeWater.FilterDescendantsInstances = skip
includeWater.IgnoreWater = false

-- Pass one: where is there anything at all?
local roughMinX, roughMaxX = math.huge, -math.huge
local roughMinZ, roughMaxZ = math.huge, -math.huge
local coarseHits = 0

for x = -SEARCH, SEARCH, COARSE do
	for z = -SEARCH, SEARCH, COARSE do
		local hit = Workspace:Raycast(
			Vector3.new(x, TOP, z),
			Vector3.new(0, -DROP, 0),
			includeWater
		)
		if hit then
			coarseHits += 1
			roughMinX = math.min(roughMinX, x)
			roughMaxX = math.max(roughMaxX, x)
			roughMinZ = math.min(roughMinZ, z)
			roughMaxZ = math.max(roughMaxZ, z)
		end
	end
end

if coarseHits == 0 then
	warn(string.format("Found nothing at all within %d studs of the origin.", SEARCH))
	return
end

if roughMinX <= -SEARCH or roughMaxX >= SEARCH or roughMinZ <= -SEARCH or roughMaxZ >= SEARCH then
	warn(string.format(
		"The map reaches the edge of even a %d stud search. Raise SEARCH at the top "
			.. "of this script and run it again.",
		SEARCH
	))
end

-- Pass two: measure that region properly.
local minX = roughMinX - COARSE
local maxX = roughMaxX + COARSE
local minZ = roughMinZ - COARSE
local maxZ = roughMaxZ + COARSE
local step = math.max(48, math.floor(math.max(maxX - minX, maxZ - minZ) / 110))

local landMinX, landMaxX = math.huge, -math.huge
local landMinZ, landMaxZ = math.huge, -math.huge
local lowestLand, highestLand = math.huge, -math.huge
local waterTop = nil :: number?
local landCount, waterCount, total = 0, 0, 0
local sumHeight = 0

-- Dry land is the only part that matters for a course. Seabed is "ground" to a
-- raycast and is no use to anybody.
local dryCount = 0
local dryMin, dryMax = math.huge, -math.huge
local dryMinX, dryMaxX = math.huge, -math.huge
local dryMinZ, dryMaxZ = math.huge, -math.huge

for x = minX, maxX, step do
	for z = minZ, maxZ, step do
		total += 1
		local origin = Vector3.new(x, TOP, z)
		local direction = Vector3.new(0, -DROP, 0)

		local ground = Workspace:Raycast(origin, direction, solidOnly)
		local anything = Workspace:Raycast(origin, direction, includeWater)

		if ground then
			landCount += 1
			landMinX = math.min(landMinX, x)
			landMaxX = math.max(landMaxX, x)
			landMinZ = math.min(landMinZ, z)
			landMaxZ = math.max(landMaxZ, z)
			lowestLand = math.min(lowestLand, ground.Position.Y)
			highestLand = math.max(highestLand, ground.Position.Y)
			sumHeight += ground.Position.Y
		end

		-- Water shows up as a hit the solid-only cast went straight past.
		local submerged = anything ~= nil
			and (not ground or anything.Position.Y > ground.Position.Y + 0.5)

		if submerged then
			waterCount += 1
			waterTop = math.max(waterTop or -math.huge, (anything :: RaycastResult).Position.Y)
		elseif ground then
			dryCount += 1
			dryMin = math.min(dryMin, ground.Position.Y)
			dryMax = math.max(dryMax, ground.Position.Y)
			dryMinX = math.min(dryMinX, x)
			dryMaxX = math.max(dryMaxX, x)
			dryMinZ = math.min(dryMinZ, z)
			dryMaxZ = math.max(dryMaxZ, z)
		end
	end
end

print(string.format(
	"\nCoarse sweep found something between X %d..%d and Z %d..%d.\n" ..
	"Measured that region with %d points every %d studs.",
	roughMinX, roughMaxX, roughMinZ, roughMaxZ, total, step
))

if landCount == 0 then
	warn("Found water but no solid ground. Is the terrain all below the surface?")
	return
end

print(string.format(
	"\nLAND FOUND:\n" ..
	"    X %d .. %d        (%d studs wide)\n" ..
	"    Z %d .. %d        (%d studs deep)\n" ..
	"    Ground height %d .. %d   (average %d)\n" ..
	"    %d of %d samples were land (%.0f%%)",
	landMinX, landMaxX, landMaxX - landMinX,
	landMinZ, landMaxZ, landMaxZ - landMinZ,
	math.floor(lowestLand), math.floor(highestLand), math.floor(sumHeight / landCount),
	landCount, total, landCount / total * 100
))

if waterTop then
	print(string.format("\nWATER surface at Y = %d   (%d samples)", math.floor(waterTop), waterCount))
else
	print("\nWATER: none found -- WaterLevel can stay at 0")
end

if dryCount == 0 then
	warn("Every sample was underwater. The whole map is below the surface.")
	return
end

print(string.format(
	"\nDRY LAND (the only part worth flying through):\n" ..
	"    X %d .. %d        Z %d .. %d\n" ..
	"    Height %d .. %d   (%d studs of relief)\n" ..
	"    %d of %d samples (%.0f%%)",
	dryMinX, dryMaxX, dryMinZ, dryMaxZ,
	math.floor(dryMin), math.floor(dryMax), math.floor(dryMax - dryMin),
	dryCount, total, dryCount / total * 100
))

print(string.format(
	"\n---------- PASTE THIS BACK ----------\n" ..
	"maxextents X:  %d to %d\n" ..
	"maxextents Z:  %d to %d\n" ..
	"dry land X:    %d to %d\n" ..
	"dry land Z:    %d to %d\n" ..
	"dry land Y:    %d to %d\n" ..
	"seabed low:    %d\n" ..
	"water level:   %s\n" ..
	"dry coverage:  %.0f%%\n" ..
	"-------------------------------------",
	exMinX, exMaxX,
	exMinZ, exMaxZ,
	dryMinX, dryMaxX,
	dryMinZ, dryMaxZ,
	math.floor(dryMin), math.floor(dryMax),
	math.floor(lowestLand),
	if waterTop then tostring(math.floor(waterTop)) else "none",
	dryCount / total * 100
))
