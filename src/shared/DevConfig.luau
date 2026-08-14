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
-- owner or listed below by user id.

local RunService = game:GetService("RunService")

local DevConfig = {}

DevConfig.AllowInStudio = true

-- Extra user ids allowed in a live server. Add collaborators here.
DevConfig.UserIds = {} :: { number }

-- How much a single Points grant is worth.
DevConfig.PointsGrant = 25000

function DevConfig.isDeveloper(player: Player): boolean
	if DevConfig.AllowInStudio and RunService:IsStudio() then
		return true
	end

	for _, id in DevConfig.UserIds do
		if player.UserId == id then
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
