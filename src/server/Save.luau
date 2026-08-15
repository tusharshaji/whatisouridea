--!strict

-- Saved progress, per player.
--
-- What persists is the bank and what it bought: points, best score, which
-- aircraft are owned, which one is being flown, and every upgrade level. What
-- does not persist is the run -- the score, the combo and the course are all
-- meant to be started again.
--
-- Two rules run through everything here.
--
-- FIRST: a failed load must never be saved over. If DataStore is down, or
-- throttled, or the request simply times out, the honest answer is "we do not
-- know what this player owns", and writing a fresh empty profile on top of that
-- would delete an evening's flying for good. A profile that failed to load is
-- marked unsaveable and stays that way for the session -- the player flies with
-- defaults, is told so, and their real data is still on the server when they
-- come back.
--
-- SECOND: nothing that comes back out of the store is trusted. It was written by
-- an older version of this code, or a different one, or half-written during a
-- shutdown. Every field is checked and replaced with a default if it is the
-- wrong shape, so a bad blob costs a player their progress and never takes the
-- server down with it.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)

-- Bump the version to start everyone from scratch. The old data stays in the
-- old store, so it is a rollback rather than a deletion.
local STORE_NAME = "PilotProgress_v1"
local KEY_PREFIX = "Pilot_"

local ATTEMPTS = 4
local RETRY_DELAY = 1.5

-- Failures worth retrying are the transient ones: throttling, a timeout, a
-- service having a bad minute. These are not. Retrying "Studio access to APIs
-- is not allowed" four times with a backoff means twelve seconds of waiting for
-- an answer that was decided before the server started, and if anything is
-- waiting on the load -- a player wanting an aeroplane, say -- twelve seconds is
-- an eternity. Match one of these and the store is switched off for the session.
local PERMANENT = {
	"not allowed",
	"403",
	"not enabled",
	"api services",
	"publish",
}

local Save = {}

export type Profile = {
	points: number,
	best: number,
	planeId: string,
	owned: { [string]: boolean },
	levels: { [string]: number },
	-- False when the load failed. Saving is then refused for the session.
	saveable: boolean,
}

local store: DataStore? = nil
local storeError: string? = nil

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		storeError = tostring(result)
		warn(`[Save] no DataStore available: {storeError}`)
		if RunService:IsStudio() then
			warn(
				"[Save] In Studio this is almost always Game Settings -> Security -> "
					.. "Enable Studio Access to API Services. Progress will not persist until it is on."
			)
		end
	end
end

--------------------------------------------------------------------------------
-- Defaults and sanitising
--------------------------------------------------------------------------------

local function defaults(): Profile
	return {
		points = 0,
		best = 0,
		planeId = UpgradeConfig.Planes[1].id,
		owned = { [UpgradeConfig.Planes[1].id] = true },
		levels = {},
		saveable = true,
	}
end

local function positiveNumber(value: any): number
	if type(value) ~= "number" then
		return 0
	end
	-- NaN fails every comparison including its own, which is exactly how it gets
	-- into a save file and then poisons every sum it touches afterwards.
	if value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.max(math.floor(value), 0)
end

-- Turn whatever came out of the store into something the rest of the game can
-- rely on. Unknown aircraft and upgrade ids are dropped rather than kept, so
-- renaming one in UpgradeConfig cannot leave a player holding a ghost.
local function sanitise(raw: any): Profile
	local profile = defaults()
	if type(raw) ~= "table" then
		return profile
	end

	profile.points = positiveNumber(raw.points)
	profile.best = positiveNumber(raw.best)

	if type(raw.owned) == "table" then
		for _, id in raw.owned do
			if type(id) == "string" and UpgradeConfig.findPlane(id) then
				profile.owned[id] = true
			end
		end
	end

	if type(raw.planeId) == "string" and profile.owned[raw.planeId] then
		profile.planeId = raw.planeId
	end

	if type(raw.levels) == "table" then
		for id, level in raw.levels do
			local upgrade = if type(id) == "string" then UpgradeConfig.findUpgrade(id) else nil
			if upgrade then
				profile.levels[id] = math.clamp(positiveNumber(level), 0, upgrade.levels)
			end
		end
	end

	return profile
end

--------------------------------------------------------------------------------
-- Failure handling
--------------------------------------------------------------------------------

-- Switch the store off for the rest of the session when an error says it is
-- never going to work. Every profile loaded from here on is marked unsaveable,
-- which is the safe direction: the game runs on defaults and writes nothing.
local function shutDown(reason: string)
	if not store then
		return
	end
	store = nil
	warn(`[Save] disabling saved progress for this session: {reason}`)
	if RunService:IsStudio() then
		warn(
			"[Save] If that mentions API services, it is Game Settings -> Security -> "
				.. "Enable Studio Access to API Services. Everything else still works without it."
		)
	end
end

local function isPermanent(err: any): boolean
	local text = string.lower(tostring(err))
	for _, needle in PERMANENT do
		if string.find(text, needle, 1, true) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Load
--------------------------------------------------------------------------------

-- Yields. Call it in its own thread, once, before the player is given a plane.
function Save.load(player: Player): Profile
	if not store then
		local profile = defaults()
		profile.saveable = false
		return profile
	end

	local key = KEY_PREFIX .. player.UserId

	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(key)
		end)

		if ok then
			if result == nil then
				-- Genuinely new. Saveable, and the first save creates the record.
				return defaults()
			end
			return sanitise(result)
		end

		if isPermanent(result) then
			shutDown(tostring(result))
			local profile = defaults()
			profile.saveable = false
			return profile
		end

		warn(`[Save] load {attempt}/{ATTEMPTS} failed for {player.Name}: {result}`)
		if attempt < ATTEMPTS then
			task.wait(RETRY_DELAY * attempt)
		end
	end

	-- Out of attempts. Give them something to fly, and refuse to write it back.
	warn(`[Save] giving up on {player.Name}; their progress will NOT be saved this session`)
	local profile = defaults()
	profile.saveable = false
	return profile
end

--------------------------------------------------------------------------------
-- Store
--------------------------------------------------------------------------------

-- Yields. Returns whether it actually got written.
function Save.store(player: Player, profile: Profile): boolean
	if not store or not profile.saveable then
		return false
	end

	local ownedList: { string } = {}
	for id in profile.owned do
		table.insert(ownedList, id)
	end
	table.sort(ownedList)

	local payload = {
		points = profile.points,
		best = profile.best,
		planeId = profile.planeId,
		owned = ownedList,
		levels = profile.levels,
		stamp = os.time(),
	}

	local key = KEY_PREFIX .. player.UserId

	-- UpdateAsync rather than SetAsync: if the player bounced between servers the
	-- older one can still be flushing, and this at least keeps the higher best
	-- score instead of letting whichever write lands last win outright.
	local function merge(existing: any)
		if type(existing) == "table" and type(existing.best) == "number" then
			payload.best = math.max(payload.best, existing.best)
		end
		return payload
	end

	for attempt = 1, ATTEMPTS do
		local target = store :: DataStore
		local ok, err = pcall(function()
			target:UpdateAsync(key, merge)
		end)

		if ok then
			return true
		end

		if isPermanent(err) then
			shutDown(tostring(err))
			return false
		end

		warn(`[Save] save {attempt}/{ATTEMPTS} failed for {player.Name}: {err}`)
		if attempt < ATTEMPTS then
			task.wait(RETRY_DELAY * attempt)
		end
	end

	return false
end

-- A fresh profile, for a caller that needs something to fly on while the real
-- one is still being read.
function Save.blank(): Profile
	return defaults()
end

function Save.isAvailable(): boolean
	return store ~= nil
end

return Save
