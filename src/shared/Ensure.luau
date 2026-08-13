--!strict

-- Fetch a child, creating it if it is not there.
--
-- This exists because `WaitForChild` with no timeout waits forever. State values
-- and remotes are declared in default.project.json, and that file only reaches
-- Studio when `rojo serve` is restarted -- editing it does not hot-reload. Miss
-- that restart after adding a value and every script that waits on the new
-- instance hangs at startup, silently and permanently: the aircraft never
-- responds, no course is ever generated, and the only symptom is that nothing
-- happens. It gives no error to search for.
--
-- Anything the server can simply create should therefore be created rather than
-- waited on. Real geometry -- the fuselage, the seat, the attachments -- still
-- uses WaitForChild, because a missing wing is a genuine authoring mistake that
-- should not be papered over with an empty Part.
--
-- Server-side only. A client calling this would build a local instance that
-- replicates nowhere and quietly reads zero forever, which hides the very
-- problem it is meant to prevent.

return function(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end

	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end
