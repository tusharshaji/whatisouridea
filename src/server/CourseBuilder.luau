--!strict

-- Builds one course: a list of gates, as plain data.
--
-- No instances are created here. Gates are drawn by each client for its own
-- course only -- forty rings times twenty parts times every player on the server
-- is a great deal of replication for something only one person is allowed to fly
-- through, and it also meant everybody could see, and score, everybody else's
-- rings. The server keeps this data and does all the detection from it.
--
-- The search runs almost entirely on the height grid rather than on raycasts, so
-- it can afford to look at twenty bearings per gate and judge each one on what
-- the surrounding kilometre actually looks like. Raycasts are spent only on the
-- winner, to pin its height to the real ground rather than to a 96-stud cell
-- average.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaneConfig = require(ReplicatedStorage.Shared.PlaneConfig)
local RingConfig = require(ReplicatedStorage.Shared.RingConfig)
local TerrainSurvey = require(script.Parent.TerrainSurvey)

export type Gate = {
	index: number,
	center: Vector3,
	normal: Vector3,
	radius: number,
}

local CourseBuilder = {}

-- Turning is now done by rolling and pulling rather than by a heading rate, so
-- the tightest circle the aircraft can fly is set by how fast it can pitch:
-- banked hard over, pulling at PitchRate turns at PitchRate.
local MIN_TURN_RADIUS = PlaneConfig.MaxSpeed / PlaneConfig.PitchRate

-- Climb is no longer capped by a vertical speed -- the aircraft can point
-- straight up -- so this is a course-design choice rather than a limit of the
-- machine: how steep a leg the course is willing to ask for.
local CLIMB_SLOPE = RingConfig.PlanningClimbSlope

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Is the line straight through a gate flyable? Walked on the grid: every sample
-- along the approach and the exit has to have its ground below the gate, or
-- there is a hillside in the way. This is the check that stops the search
-- burying a gate inside the most enclosed rock it can find.
local function corridorOpen(
	survey: TerrainSurvey.Survey,
	center: Vector3,
	direction: Vector3,
	radius: number
): boolean
	local reach = RingConfig.CorridorReach
	local margin = radius * 0.6

	for step = -6, 6 do
		local point = center + direction * (reach * step / 6)
		if TerrainSurvey.heightAt(survey, point.X, point.Z) > center.Y - margin then
			return false
		end
	end

	return true
end

function CourseBuilder.build(
	survey: TerrainSurvey.Survey,
	groundAt: (number, number) -> number?,
	startPosition: Vector3,
	startDirection: Vector3,
	seed: number,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number
): { Gate }
	local rng = Random.new(seed)

	local limitX = (maxX - minX) / 2 - RingConfig.EdgeMargin
	local limitZ = (maxZ - minZ) / 2 - RingConfig.EdgeMargin
	local midX, midZ = (minX + maxX) / 2, (minZ + maxZ) / 2

	local cursor = Vector3.new(startPosition.X, 0, startPosition.Z)
	local direction = Vector3.new(startDirection.X, 0, startDirection.Z)
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)

	-- Aim at broken ground a long way off, and pick somewhere new on arrival.
	-- Without this the walk has no reason to leave the flat country it starts
	-- in, which is exactly what it used to do.
	local targetX, targetZ = TerrainSurvey.findRuggedTarget(
		survey,
		cursor.X,
		cursor.Z,
		RingConfig.TargetMinDistance,
		RingConfig.TargetMaxDistance,
		RingConfig.RuggedRadius,
		rng
	)

	type Node = { position: Vector3, radius: number }
	local nodes: { Node } = {}
	local previousY: number? = nil

	for i = 1, RingConfig.RingCount do
		local t = if RingConfig.RingCount > 1 then (i - 1) / (RingConfig.RingCount - 1) else 0
		local spacing = if i == 1
			then RingConfig.FirstGateDistance
			else lerp(RingConfig.StartSpacing, RingConfig.EndSpacing, t)
		local radius = lerp(RingConfig.StartRadius, RingConfig.EndRadius, t)

		local ramp = lerp(RingConfig.StartTurn, RingConfig.EndTurn, t)
		local geometric = 2 * math.asin(math.clamp(spacing / (2 * MIN_TURN_RADIUS), 0, 1))
		local maxTurn = if i == 1 then 0 else math.min(ramp, geometric * RingConfig.TurnSafety)

		local minClear = lerp(RingConfig.StartMinClearance, RingConfig.EndMinClearance, t)
		local maxClear = lerp(RingConfig.StartMaxClearance, RingConfig.EndMaxClearance, t)

		-- Arrived at the rugged patch we were aiming for: choose another.
		local toTarget = Vector3.new(targetX - cursor.X, 0, targetZ - cursor.Z)
		if toTarget.Magnitude < RingConfig.RetargetWithin then
			targetX, targetZ = TerrainSurvey.findRuggedTarget(
				survey,
				cursor.X,
				cursor.Z,
				RingConfig.TargetMinDistance,
				RingConfig.TargetMaxDistance,
				RingConfig.RuggedRadius,
				rng
			)
			toTarget = Vector3.new(targetX - cursor.X, 0, targetZ - cursor.Z)
		end

		local aimUnit = if toTarget.Magnitude > 1 then toTarget.Unit else direction

		local bestCenter: Vector3? = nil
		local bestHeading: Vector3? = nil
		local bestScore = -math.huge

		for candidate = 1, RingConfig.Candidates do
			-- Bearings are spread evenly across the allowed turn instead of
			-- drawn at random, so the search actually covers the arc rather
			-- than bunching up in the middle of it.
			local spread = if RingConfig.Candidates > 1
				then (candidate - 1) / (RingConfig.Candidates - 1)
				else 0.5
			local turn = (-maxTurn + spread * 2 * maxTurn)
			local heading = if turn ~= 0 then (CFrame.Angles(0, turn, 0) * direction).Unit else direction

			local ahead = cursor + heading * spacing

			-- Turn back before walking off the edge of the map.
			if math.abs(ahead.X - midX) > limitX or math.abs(ahead.Z - midZ) > limitZ then
				local inward = Vector3.new(midX - cursor.X, 0, midZ - cursor.Z)
				if inward.Magnitude > 0.01 then
					heading = heading:Lerp(inward.Unit, 0.6).Unit
					ahead = cursor + heading * spacing
				end
			end

			local ground = TerrainSurvey.heightAt(survey, ahead.X, ahead.Z)
			local clearance = rng:NextNumber(minClear, maxClear)

			local y = ground + clearance + radius
			y = math.max(y, RingConfig.WaterLevel + radius + RingConfig.EndMinClearance)
			y = math.min(y, PlaneConfig.MaxAltitude - RingConfig.CeilingMargin)

			if previousY then
				local reach = spacing * CLIMB_SLOPE * RingConfig.ClimbSafety
				y = math.clamp(y, previousY - reach, previousY + reach)
				y = math.max(y, ground + radius + RingConfig.EndMinClearance)
			end

			local center = Vector3.new(ahead.X, y, ahead.Z)

			if corridorOpen(survey, center, heading, radius) then
				-- How much rock stands above this gate, and how well it heads
				-- where we are trying to go.
				local wall = TerrainSurvey.wallScore(
					survey,
					center.X,
					center.Z,
					center.Y,
					RingConfig.WallRadius
				)
				local aim = (heading:Dot(aimUnit) + 1) / 2
				local score = wall + RingConfig.TargetPull * aim

				-- Clearing the bar is worth more than any amount of good
				-- heading, so a gate genuinely down among the rock always beats
				-- a better-aimed one hanging in open air.
				if wall >= RingConfig.WallTarget then
					score += RingConfig.WallBonus
				end

				if score > bestScore then
					bestScore = score
					bestCenter, bestHeading = center, heading
				end
			end
		end

		-- Nothing threadable in the whole arc: press on straight and high rather
		-- than abandoning the course.
		local center = bestCenter
		local heading = bestHeading

		if not center or not heading then
			heading = direction
			local ahead = cursor + heading * spacing
			local ground = TerrainSurvey.heightAt(survey, ahead.X, ahead.Z)
			center = Vector3.new(
				ahead.X,
				math.min(
					ground + RingConfig.StartMaxClearance + radius,
					PlaneConfig.MaxAltitude - RingConfig.CeilingMargin
				),
				ahead.Z
			)
		end

		-- The grid is a 96-stud average, which is fine for choosing where to go
		-- and much too coarse for deciding how high to sit above a ridge. Pin
		-- the winner to the real surface, sampling the rim as well as the middle
		-- so a slope cannot leave one side of the ring inside the hill.
		local highest = groundAt(center.X, center.Z) or RingConfig.WaterLevel
		for edge = 1, 4 do
			local angle = (edge / 4) * math.pi * 2
			local sample = groundAt(
				center.X + math.cos(angle) * radius,
				center.Z + math.sin(angle) * radius
			)
			if sample and sample > highest then
				highest = sample
			end
		end

		local floor = math.min(
			highest + radius + minClear,
			PlaneConfig.MaxAltitude - RingConfig.CeilingMargin
		)
		if center.Y < floor then
			center = Vector3.new(center.X, floor, center.Z)
		end

		cursor = Vector3.new(center.X, 0, center.Z)
		direction = heading
		previousY = center.Y
		table.insert(nodes, { position = center, radius = radius })

		if i % 4 == 0 then
			task.wait()
		end
	end

	-- Face each gate along the bisector of the leg in and the leg out, so a gate
	-- on a corner is presented squarely rather than edge-on to the turn.
	local gates: { Gate } = {}
	local previous = Vector3.new(startPosition.X, nodes[1].position.Y, startPosition.Z)

	for i, node in nodes do
		local incoming = node.position - previous
		incoming = if incoming.Magnitude > 0.01 then incoming.Unit else direction

		local nextNode = nodes[i + 1]
		local outgoing = if nextNode then (nextNode.position - node.position) else incoming
		outgoing = if outgoing.Magnitude > 0.01 then outgoing.Unit else incoming

		local normal = incoming + outgoing
		normal = if normal.Magnitude > 0.01 then normal.Unit else incoming

		table.insert(gates, {
			index = i,
			center = node.position,
			normal = normal,
			radius = node.radius,
		})
		previous = node.position
	end

	return gates
end

return CourseBuilder
