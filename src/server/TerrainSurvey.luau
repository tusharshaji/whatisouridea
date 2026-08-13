--!strict

-- A coarse height map of the world, sampled once at startup.
--
-- The course generator used to ask the terrain questions with raycasts, one
-- candidate position at a time. That is both slow and, worse, blind: it can only
-- see the few hundred studs around wherever the walk had already decided to go,
-- so if there was no mountain there, no gate ever went near a mountain. The
-- course drifted around the flat ground near the runway because that is where it
-- started and it had no way of knowing anything else existed.
--
-- Sampling a grid up front inverts that. A few thousand rays, once, and after
-- that every question -- how high is it there, how broken up is that ground, am
-- I below the ridge line -- is a table lookup costing nothing. The generator can
-- then afford to look at the whole map and steer toward the interesting parts.

local Workspace = game:GetService("Workspace")

export type Survey = {
	minX: number,
	minZ: number,
	cell: number,
	cols: number,
	rows: number,
	heights: { number },
	floor: number,
}

local TerrainSurvey = {}

-- Column and row for a world position, clamped to the grid so points off the
-- edge of the map answer with the edge rather than erroring.
local function indexFor(survey: Survey, x: number, z: number): number
	local col = math.clamp(math.floor((x - survey.minX) / survey.cell), 0, survey.cols - 1)
	local row = math.clamp(math.floor((z - survey.minZ) / survey.cell), 0, survey.rows - 1)
	return row * survey.cols + col + 1
end

function TerrainSurvey.build(
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	cell: number,
	params: RaycastParams,
	top: number,
	bottom: number
): Survey
	-- A bigger map than expected must not turn into tens of thousands of rays.
	-- Coarsen the grid instead of sampling forever: a rough picture of a large
	-- world beats a precise picture that arrives after the player has left.
	local MAX_SIDE = 110
	local widest = math.max(maxX - minX, maxZ - minZ)
	if widest / cell > MAX_SIDE then
		cell = widest / MAX_SIDE
		warn(`[TerrainSurvey] map is large; coarsening the grid to {math.floor(cell)} studs`)
	end

	local cols = math.max(2, math.ceil((maxX - minX) / cell))
	local rows = math.max(2, math.ceil((maxZ - minZ) / cell))

	local survey: Survey = {
		minX = minX,
		minZ = minZ,
		cell = cell,
		cols = cols,
		rows = rows,
		heights = table.create(cols * rows, bottom),
		floor = bottom,
	}

	local reach = top - bottom
	local sampled = 0

	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			local x = minX + (col + 0.5) * cell
			local z = minZ + (row + 0.5) * cell

			local hit = Workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -reach, 0), params)
			survey.heights[row * cols + col + 1] = if hit then hit.Position.Y else bottom
			sampled += 1
		end

		-- One frame per row. The survey runs while the game is already up, so a
		-- big map costs a moment of the course arriving late, not a freeze.
		if row % 4 == 3 then
			task.wait()
		end
	end

	print(`[TerrainSurvey] sampled {sampled} points at {cell} studs across {cols}x{rows}`)
	return survey
end

function TerrainSurvey.heightAt(survey: Survey, x: number, z: number): number
	return survey.heights[indexFor(survey, x, z)]
end

-- How broken up the ground is: the height spread across the neighbourhood.
-- Flat plains and open water score near zero, mountainsides and canyon rims
-- score high. This is what the generator steers toward.
function TerrainSurvey.ruggedness(survey: Survey, x: number, z: number, radius: number): number
	local steps = math.max(1, math.floor(radius / survey.cell))
	local lowest, highest = math.huge, -math.huge

	for dz = -steps, steps do
		for dx = -steps, steps do
			local height = TerrainSurvey.heightAt(
				survey,
				x + dx * survey.cell,
				z + dz * survey.cell
			)
			lowest = math.min(lowest, height)
			highest = math.max(highest, height)
		end
	end

	return highest - lowest
end

-- How much terrain stands above a given height nearby, as a fraction of the
-- neighbourhood. This is the measure that actually matters for a gate: it says
-- the aircraft will be flying *below the ridge line*, down in a pass or a canyon
-- with rock above it, rather than sailing over the top of everything.
function TerrainSurvey.wallScore(
	survey: Survey,
	x: number,
	z: number,
	y: number,
	radius: number
): number
	local steps = math.max(1, math.floor(radius / survey.cell))
	local above, total = 0, 0

	for dz = -steps, steps do
		for dx = -steps, steps do
			local height = TerrainSurvey.heightAt(
				survey,
				x + dx * survey.cell,
				z + dz * survey.cell
			)
			if height > y then
				above += 1
			end
			total += 1
		end
	end

	return if total > 0 then above / total else 0
end

-- Somewhere worth flying to: the most broken-up ground within a distance band of
-- where we are. The generator aims the walk at one of these and re-picks when it
-- arrives, which is what keeps the course out among the mountains instead of
-- wandering in circles round the runway.
function TerrainSurvey.findRuggedTarget(
	survey: Survey,
	fromX: number,
	fromZ: number,
	minDistance: number,
	maxDistance: number,
	radius: number,
	rng: Random
): (number, number)
	local best: { { x: number, z: number, score: number } } = {}

	for row = 0, survey.rows - 1 do
		for col = 0, survey.cols - 1 do
			local x = survey.minX + (col + 0.5) * survey.cell
			local z = survey.minZ + (row + 0.5) * survey.cell
			local distance = math.sqrt((x - fromX) ^ 2 + (z - fromZ) ^ 2)

			if distance >= minDistance and distance <= maxDistance then
				table.insert(best, {
					x = x,
					z = z,
					score = TerrainSurvey.ruggedness(survey, x, z, radius),
				})
			end
		end
	end

	if #best == 0 then
		return fromX, fromZ
	end

	table.sort(best, function(a, b)
		return a.score > b.score
	end)

	-- Pick from the top of the list rather than the single best, so repeated
	-- courses on the same map do not all march to the same peak.
	local pick = best[rng:NextInteger(1, math.min(#best, 12))]
	return pick.x, pick.z
end

return TerrainSurvey
