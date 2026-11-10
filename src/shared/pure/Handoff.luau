--!strict
-- What a lobby server tells the reserved server a party is teleported to: which way into the run
-- they chose and how many are coming, so the new server can start them together without a second
-- press of Play. Teleport data comes from the client's side of Roblox, so decode trusts nothing.

local Handoff = {}

export type Handoff = { mode: string, size: number }

local MODES: { [string]: boolean } = { continue = true, new = true, daily = true }

function Handoff.encode(mode: string, size: number): Handoff
	return { mode = if MODES[mode] then mode else "continue", size = size }
end

-- nil for anything that is not a handoff from a lobby (a normal join, or tampered data).
function Handoff.decode(data: any, maxSize: number): Handoff?
	if type(data) ~= "table" then
		return nil
	end
	local mode = data.mode
	local size = data.size
	if type(mode) ~= "string" or not MODES[mode] then
		return nil
	end
	if type(size) ~= "number" or size ~= size or size < 1 then
		return nil
	end
	return { mode = mode, size = math.min(math.floor(size), maxSize) }
end

-- The people who go in together: the leader first, then the ready ones, never more than fit.
function Handoff.crew<T>(leader: T, ready: { T }, maxSize: number): { T }
	local crew: { T } = { leader }
	for _, other in ready do
		if #crew >= maxSize then
			break
		end
		if other ~= leader then
			table.insert(crew, other)
		end
	end
	return crew
end

return Handoff
