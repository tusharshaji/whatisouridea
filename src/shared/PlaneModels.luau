--!strict

-- What each aircraft is made of.
--
-- Every plane is built from one of these specs at runtime rather than cloned
-- from a single authored model, which is how a jet can actually look like a jet
-- instead of like the trainer in a different colour.
--
-- Offsets are in aircraft space: +X right, +Y up, -Z forward (Roblox convention,
-- so the nose is at negative Z). The builder welds everything to the Fuselage
-- and hangs the constraints off it, so the only truly required part is that one.
--
-- Named parts the controller looks for, all optional except Fuselage:
--   Fuselage    the root everything welds to
--   RotorHub    spun by a HingeConstraint; propeller aircraft only
--   AileronL/R, Elevator, Rudder   hinged control surfaces
--   Thruster    marks a jet exhaust; gets fire and a glow

export type PartSpec = {
	name: string?,
	size: Vector3,
	offset: CFrame,
	color: Color3?,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
}

export type ModelSpec = {
	parts: { PartSpec },
	rotor: boolean,
	thrusters: { CFrame },
	thrusterSize: number,
	trailColor: Color3,
}

local function part(
	name: string?,
	size: Vector3,
	offset: CFrame,
	color: Color3?,
	material: Enum.Material?,
	shape: Enum.PartType?
): PartSpec
	return {
		name = name,
		size = size,
		offset = offset,
		color = color,
		material = material,
		shape = shape,
	}
end

local GLASS = Color3.fromRGB(120, 190, 230)
local DARK = Color3.fromRGB(45, 45, 52)
local TYRE = Color3.fromRGB(28, 28, 30)

local PlaneModels = {}

--------------------------------------------------------------------------------
-- Trainer: high wing, big propeller, fixed gear. Slow and obvious.
--------------------------------------------------------------------------------

local function trainer(body: Color3): ModelSpec
	return {
		rotor = true,
		thrusters = {},
		thrusterSize = 0,
		trailColor = body,
		parts = {
			part("Fuselage", Vector3.new(4, 4, 18), CFrame.new(), body, Enum.Material.SmoothPlastic),
			part("Nose", Vector3.new(3.6, 3.6, 4), CFrame.new(0, 0, -10), body, Enum.Material.SmoothPlastic),
			part("Canopy", Vector3.new(3.4, 2.2, 6), CFrame.new(0, 2.4, -2), GLASS, Enum.Material.Glass),
			part("Wings", Vector3.new(30, 0.9, 6.5), CFrame.new(0, 2.6, -1), body, Enum.Material.SmoothPlastic),
			part("WingStrutL", Vector3.new(0.5, 2.8, 0.6), CFrame.new(-6, 1.2, -1), DARK),
			part("WingStrutR", Vector3.new(0.5, 2.8, 0.6), CFrame.new(6, 1.2, -1), DARK),
			part("TailBoom", Vector3.new(2.2, 2.2, 6), CFrame.new(0, 0.4, 10), body),
			part("TailWing", Vector3.new(11, 0.8, 3.2), CFrame.new(0, 1.4, 12.5), body),
			part("TailFin", Vector3.new(0.8, 6, 4), CFrame.new(0, 4, 12.5), body),
			part("AileronL", Vector3.new(8, 0.6, 2.4), CFrame.new(-10, 2.6, 2.2), DARK),
			part("AileronR", Vector3.new(8, 0.6, 2.4), CFrame.new(10, 2.6, 2.2), DARK),
			part("Elevator", Vector3.new(11, 0.6, 2.2), CFrame.new(0, 1.4, 14.4), DARK),
			part("Rudder", Vector3.new(0.7, 5, 2.4), CFrame.new(0, 4, 14.6), DARK),
			part("GearL", Vector3.new(1.6, 2.2, 2.2), CFrame.new(-3.4, -2.6, -4), TYRE, nil, Enum.PartType.Cylinder),
			part("GearR", Vector3.new(1.6, 2.2, 2.2), CFrame.new(3.4, -2.6, -4), TYRE, nil, Enum.PartType.Cylinder),
			part("GearTail", Vector3.new(1, 1.2, 1.2), CFrame.new(0, -1.6, 12), TYRE, nil, Enum.PartType.Cylinder),
			part("RotorHub", Vector3.new(1.4, 1.4, 1.2), CFrame.new(0, 0, -12.4), DARK, nil, Enum.PartType.Cylinder),
			part("RotorBladeA", Vector3.new(0.4, 15, 1.4), CFrame.new(0, 0, -12.9), DARK),
			part("RotorBladeB", Vector3.new(15, 0.4, 1.4), CFrame.new(0, 0, -12.9), DARK),
		},
	}
end

--------------------------------------------------------------------------------
-- Sport: low wing, tighter, retract-look gear, small propeller.
--------------------------------------------------------------------------------

local function sport(body: Color3): ModelSpec
	return {
		rotor = true,
		thrusters = {},
		thrusterSize = 0,
		trailColor = body,
		parts = {
			part("Fuselage", Vector3.new(3.4, 3.2, 19), CFrame.new(), body, Enum.Material.Metal),
			part("Nose", Vector3.new(2.8, 2.8, 5), CFrame.new(0, -0.2, -11), body, Enum.Material.Metal),
			part("Canopy", Vector3.new(2.8, 1.8, 7), CFrame.new(0, 1.9, -1.5), GLASS, Enum.Material.Glass),
			part("Wings", Vector3.new(26, 0.8, 7.5), CFrame.new(0, -1.1, 0.5), body, Enum.Material.Metal),
			part("WingTipL", Vector3.new(1.2, 2.4, 4), CFrame.new(-13, -0.2, 0.5), body),
			part("WingTipR", Vector3.new(1.2, 2.4, 4), CFrame.new(13, -0.2, 0.5), body),
			part("TailWing", Vector3.new(10, 0.7, 3), CFrame.new(0, 0.6, 11.5), body),
			part("TailFin", Vector3.new(0.8, 5.4, 4.4), CFrame.new(0, 3.4, 11.8), body),
			part("AileronL", Vector3.new(7, 0.5, 2.2), CFrame.new(-9, -1.1, 3.6), DARK),
			part("AileronR", Vector3.new(7, 0.5, 2.2), CFrame.new(9, -1.1, 3.6), DARK),
			part("Elevator", Vector3.new(10, 0.5, 2), CFrame.new(0, 0.6, 13.2), DARK),
			part("Rudder", Vector3.new(0.7, 4.6, 2.2), CFrame.new(0, 3.4, 13.8), DARK),
			part("GearL", Vector3.new(1.3, 1.8, 1.8), CFrame.new(-3, -2.6, -3), TYRE, nil, Enum.PartType.Cylinder),
			part("GearR", Vector3.new(1.3, 1.8, 1.8), CFrame.new(3, -2.6, -3), TYRE, nil, Enum.PartType.Cylinder),
			part("GearTail", Vector3.new(0.9, 1.1, 1.1), CFrame.new(0, -1.6, 11), TYRE, nil, Enum.PartType.Cylinder),
			part("RotorHub", Vector3.new(1.2, 1.2, 1), CFrame.new(0, -0.2, -13.4), DARK, nil, Enum.PartType.Cylinder),
			part("RotorBladeA", Vector3.new(0.4, 12, 1.1), CFrame.new(0, -0.2, -13.8), DARK),
			part("RotorBladeB", Vector3.new(12, 0.4, 1.1), CFrame.new(0, -0.2, -13.8), DARK),
		},
	}
end

--------------------------------------------------------------------------------
-- Jet: no propeller. Swept wings, twin tail fins, two exhausts with fire.
--------------------------------------------------------------------------------

local function jet(body: Color3): ModelSpec
	return {
		rotor = false,
		thrusters = { CFrame.new(-1.7, 0, 11.5), CFrame.new(1.7, 0, 11.5) },
		thrusterSize = 2.4,
		trailColor = Color3.fromRGB(120, 200, 255),
		parts = {
			part("Fuselage", Vector3.new(3.6, 3.4, 24), CFrame.new(), body, Enum.Material.Metal),
			part("Nose", Vector3.new(2.4, 2.4, 7), CFrame.new(0, -0.1, -14), body, Enum.Material.Metal),
			part("NoseTip", Vector3.new(1, 1, 3), CFrame.new(0, -0.1, -18), DARK),
			part("Canopy", Vector3.new(2.6, 1.9, 6.5), CFrame.new(0, 1.9, -5), GLASS, Enum.Material.Glass),
			-- Swept main wing, built as two panels angled back.
			part("Wings", Vector3.new(11, 0.8, 9), CFrame.new(-7.5, -0.6, 3) * CFrame.Angles(0, math.rad(-18), 0), body, Enum.Material.Metal),
			part("WingsR", Vector3.new(11, 0.8, 9), CFrame.new(7.5, -0.6, 3) * CFrame.Angles(0, math.rad(18), 0), body, Enum.Material.Metal),
			part("Strake", Vector3.new(9, 0.6, 7), CFrame.new(0, -0.6, 1), body, Enum.Material.Metal),
			part("IntakeL", Vector3.new(2, 2, 8), CFrame.new(-2.6, -0.8, -2), DARK, Enum.Material.Metal),
			part("IntakeR", Vector3.new(2, 2, 8), CFrame.new(2.6, -0.8, -2), DARK, Enum.Material.Metal),
			part("TailWing", Vector3.new(9, 0.7, 4), CFrame.new(0, 0.2, 11), body),
			part("TailFin", Vector3.new(0.7, 5, 5) , CFrame.new(-2.2, 3, 10.5) * CFrame.Angles(0, 0, math.rad(14)), body),
			part("TailFinR", Vector3.new(0.7, 5, 5), CFrame.new(2.2, 3, 10.5) * CFrame.Angles(0, 0, math.rad(-14)), body),
			part("AileronL", Vector3.new(6, 0.5, 2.2), CFrame.new(-10, -0.6, 7), DARK),
			part("AileronR", Vector3.new(6, 0.5, 2.2), CFrame.new(10, -0.6, 7), DARK),
			part("Elevator", Vector3.new(9, 0.5, 2), CFrame.new(0, 0.2, 12.8), DARK),
			part("Rudder", Vector3.new(0.7, 4.4, 2), CFrame.new(0, 3, 12.6), DARK),
			part("GearL", Vector3.new(1.2, 1.6, 1.6), CFrame.new(-2.6, -2.5, -1), TYRE, nil, Enum.PartType.Cylinder),
			part("GearR", Vector3.new(1.2, 1.6, 1.6), CFrame.new(2.6, -2.5, -1), TYRE, nil, Enum.PartType.Cylinder),
			part("GearNose", Vector3.new(1, 1.3, 1.3), CFrame.new(0, -2.3, -11), TYRE, nil, Enum.PartType.Cylinder),
		},
	}
end

--------------------------------------------------------------------------------
-- Delta: one big triangular wing, single fin, three exhausts. Very fast.
--------------------------------------------------------------------------------

local function delta(body: Color3): ModelSpec
	return {
		rotor = false,
		thrusters = {
			CFrame.new(-2.4, 0, 9.5),
			CFrame.new(0, 0, 10),
			CFrame.new(2.4, 0, 9.5),
		},
		thrusterSize = 2.2,
		trailColor = Color3.fromRGB(220, 140, 255),
		parts = {
			part("Fuselage", Vector3.new(4, 3, 22), CFrame.new(), body, Enum.Material.Metal),
			part("Nose", Vector3.new(2.2, 2, 8), CFrame.new(0, -0.2, -13), body, Enum.Material.Metal),
			part("NoseTip", Vector3.new(0.9, 0.9, 3.5), CFrame.new(0, -0.2, -17.5), DARK),
			part("Canopy", Vector3.new(2.6, 1.7, 6), CFrame.new(0, 1.7, -6), GLASS, Enum.Material.Glass),
			-- The delta itself: three panels of decreasing span faked into a
			-- triangle, because a Part cannot be a triangle.
			part("Wings", Vector3.new(30, 0.7, 7), CFrame.new(0, -0.6, 6.5), body, Enum.Material.Metal),
			part("WingMid", Vector3.new(22, 0.7, 6), CFrame.new(0, -0.6, 1), body, Enum.Material.Metal),
			part("WingFore", Vector3.new(13, 0.7, 6), CFrame.new(0, -0.6, -4.5), body, Enum.Material.Metal),
			part("CanardL", Vector3.new(5, 0.5, 2.4), CFrame.new(-4.4, 0.6, -10), body),
			part("CanardR", Vector3.new(5, 0.5, 2.4), CFrame.new(4.4, 0.6, -10), body),
			part("TailFin", Vector3.new(0.8, 6.5, 6), CFrame.new(0, 3.6, 8.5), body),
			part("AileronL", Vector3.new(9, 0.5, 2.4), CFrame.new(-9, -0.6, 10.2), DARK),
			part("AileronR", Vector3.new(9, 0.5, 2.4), CFrame.new(9, -0.6, 10.2), DARK),
			part("Elevator", Vector3.new(7, 0.5, 2.2), CFrame.new(0, -0.6, 10.2), DARK),
			part("Rudder", Vector3.new(0.7, 5.5, 2.2), CFrame.new(0, 3.6, 12), DARK),
			part("GearL", Vector3.new(1.2, 1.6, 1.6), CFrame.new(-3, -2.3, 1), TYRE, nil, Enum.PartType.Cylinder),
			part("GearR", Vector3.new(1.2, 1.6, 1.6), CFrame.new(3, -2.3, 1), TYRE, nil, Enum.PartType.Cylinder),
			part("GearNose", Vector3.new(1, 1.3, 1.3), CFrame.new(0, -2.1, -10), TYRE, nil, Enum.PartType.Cylinder),
		},
	}
end

local BUILDERS: { [string]: (Color3) -> ModelSpec } = {
	trainer = trainer,
	sport = sport,
	jet = jet,
	delta = delta,
}

function PlaneModels.get(id: string, color: Color3): ModelSpec
	local builder = BUILDERS[id] or trainer
	return builder(color)
end

return PlaneModels
