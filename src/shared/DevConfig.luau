--!strict

-- Who is allowed to use the dev panel.
--
-- The panel hands out points and unlocks, so this is the only thing standing
-- between a test tool and a cheat menu. It is checked on the server for every
-- action, not just used to decide whether to draw the buttons -- a client can
-- draw whatever it likes and fire the remote regardless.
--
-- In Studio everyone counts, because that is where testing happens and the only
-- person there is you. In a live server nobody does unless they are the place
-- owner, listed below by user id, or listed below by name.

local RunService = game:GetService("RunService")

local DevConfig = {}

DevConfig.AllowInStudio = true

-- Extra user ids allowed in a live server. This is the one that cannot be
-- spoofed: a user id belongs to an account for ever.
DevConfig.UserIds = {} :: { number }

-- The same thing by username, matched case-insensitively.
--
-- Convenient, and weaker than a user id on purpose-of-record: a Roblox username
-- can be changed by its owner, and once released the old name can be claimed by
-- somebody else, who would then inherit dev access here. The server prints the
-- user id of anyone let in by name -- move those ids into UserIds above and
-- delete the name to close that hole.
DevConfig.UserNames = {
	"tushar123tushar",
	"c_pnz",
	"GoneFishingAgain",
} :: { string }

-- How much a single Points grant is worth.
DevConfig.PointsGrant = 25000

-- Names are only warned about once each, or every dev action would print.
local announced: { [number]: boolean } = {}

function DevConfig.isDeveloper(player: Player): boolean
	if DevConfig.AllowInStudio and RunService:IsStudio() then
		return true
	end

	for _, id in DevConfig.UserIds do
		if player.UserId == id then
			return true
		end
	end

	local lowered = string.lower(player.Name)
	for _, name in DevConfig.UserNames do
		if string.lower(name) == lowered then
			if not announced[player.UserId] then
				announced[player.UserId] = true
				print(string.format(
					"[DevConfig] %s matched a dev username. Their user id is %d -- "
						.. "put that in DevConfig.UserIds to make it survive a name change.",
					player.Name,
					player.UserId
				))
			end
			return true
		end
	end

	-- CreatorId is the group id on a group-owned place, which would let every
	-- member of that group in, so the type has to be checked too.
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end

	return false
end

return DevConfig
