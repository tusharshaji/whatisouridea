--!strict

-- Aircraft and upgrades.
--
-- Everything a pilot can buy is defined here and nowhere else. Both the shop UI
-- and the server's purchase validation read this same table, so a price or a
-- effect can never be listed as one thing and charged as another.
--
-- Two currencies, deliberately:
--
--   Score   the run you are flying. A crash wipes it. This is what the
--           scoreboard shows and what "best" is measured against.
--   Points  banked. Gates pay into it as well, and crashing does not touch it.
--
-- If crashing burned the currency too, an hour of flying could leave a pilot
-- with nothing at all to show, and the whole progression would feel like
-- punishment. The run is the risk; the bank is the progress.
--
-- Stats are multipliers on PlaneConfig, applied per player:
--
--   speed      MaxSpeed and MinFlightSpeed
--   handling   RollRate and YawRate
--   climb      PitchRate, so it is really "how hard it pulls"
--   fuel       tank capacity
--   stability  how strongly the wings self-level. Per aircraft only, not
--              buyable: it is the character of the machine, not an upgrade.
--
-- Nothing here touches the crash rules or the gate sizes, so a fully upgraded
-- delta is faster and sharper but still has to be flown through the same rock.

export type PlaneDef = {
	id: string,
	name: string,
	cost: number,
	speed: number,
	handling: number,
	climb: number,
	fuel: number,
	stability: number, -- how hard the wings self-level. Low is twitchy and
	-- rewards a good pilot; high is forgiving and slow to point anywhere new.
	color: Color3,
	blurb: string,
}

export type UpgradeDef = {
	id: string,
	name: string,
	stat: string,
	levels: number,
	baseCost: number,
	costGrowth: number,
	perLevel: number,
	blurb: string,
}

local UpgradeConfig = {}

UpgradeConfig.Planes = {
	{
		id = "trainer",
		name = "Trainer",
		cost = 0,
		speed = 1,
		handling = 1,
		climb = 1,
		fuel = 1,
		stability = 1.35,
		color = Color3.fromRGB(225, 225, 235),
		blurb = "High wing, big propeller. Slow, and it wants to fly level.",
	},
	{
		id = "sport",
		name = "Sport",
		cost = 3000,
		speed = 1.2,
		handling = 1.25,
		climb = 1.1,
		fuel = 1.15,
		stability = 1,
		color = Color3.fromRGB(255, 132, 48),
		blurb = "Low wing, clipped tips. Rolls quickly and will hold inverted.",
	},
	{
		id = "jet",
		name = "Jet",
		cost = 9000,
		speed = 1.5,
		handling = 1.45,
		climb = 1.35,
		fuel = 0.85,
		stability = 0.7,
		color = Color3.fromRGB(90, 170, 255),
		blurb = "Twin exhausts, swept wing. Drinks fuel and forgives nothing.",
	},
	{
		id = "delta",
		name = "Delta",
		cost = 22000,
		speed = 1.85,
		handling = 1.8,
		climb = 1.6,
		fuel = 0.7,
		stability = 0.45,
		color = Color3.fromRGB(190, 110, 255),
		blurb = "Three engines and a wing like a dart. Loops in its own length.",
	},
} :: { PlaneDef }

UpgradeConfig.Upgrades = {
	{
		id = "engine",
		name = "Engine",
		stat = "speed",
		levels = 5,
		baseCost = 700,
		costGrowth = 1.75,
		perLevel = 0.07,
		blurb = "Top speed. Also raises the speed you cannot slow below.",
	},
	{
		id = "wings",
		name = "Wings",
		stat = "handling",
		levels = 5,
		baseCost = 650,
		costGrowth = 1.75,
		perLevel = 0.08,
		blurb = "Turn rate and roll rate. The tight gates live here.",
	},
	{
		id = "lift",
		name = "Lift",
		stat = "climb",
		levels = 5,
		baseCost = 600,
		costGrowth = 1.75,
		perLevel = 0.09,
		blurb = "Pitch authority. Tighter loops, sharper pull-ups.",
	},
	{
		id = "tank",
		name = "Fuel Tank",
		stat = "fuel",
		levels = 6,
		baseCost = 500,
		costGrowth = 1.6,
		perLevel = 0.22,
		blurb = "How long you can stay up. Run dry and the engine quits.",
	},
} :: { UpgradeDef }

function UpgradeConfig.findPlane(id: string): PlaneDef?
	for _, plane in UpgradeConfig.Planes do
		if plane.id == id then
			return plane
		end
	end
	return nil
end

function UpgradeConfig.findUpgrade(id: string): UpgradeDef?
	for _, upgrade in UpgradeConfig.Upgrades do
		if upgrade.id == id then
			return upgrade
		end
	end
	return nil
end

-- Price of taking an upgrade from `level` to `level + 1`. Returns nil when the
-- track is already maxed, which is what both the shop and the server test.
function UpgradeConfig.upgradeCost(upgrade: UpgradeDef, level: number): number?
	if level >= upgrade.levels then
		return nil
	end
	return math.floor(upgrade.baseCost * upgrade.costGrowth ^ level)
end

-- The multipliers a pilot is actually flying with: their aircraft's base stats
-- with every upgrade level stacked on top.
function UpgradeConfig.statsFor(planeId: string, levels: { [string]: number }): { [string]: number }
	local plane = UpgradeConfig.findPlane(planeId) or UpgradeConfig.Planes[1]
	local stats: { [string]: number } = {
		speed = plane.speed,
		handling = plane.handling,
		climb = plane.climb,
		fuel = plane.fuel,
		stability = plane.stability,
	}

	for _, upgrade in UpgradeConfig.Upgrades do
		local level = levels[upgrade.id] or 0
		if level > 0 then
			stats[upgrade.stat] = (stats[upgrade.stat] or 1) * (1 + upgrade.perLevel * level)
		end
	end

	return stats
end

return UpgradeConfig
