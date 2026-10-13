--!strict
-- Pure dot classification: which colour class a hit gets, given the tags on it or its ancestors.

export type DotClass = "terrain" | "friend" | "enemy"

local DotRules = {}

-- Enemy wins over friend wins over terrain, so a Mimic tagged both ways reads as enemy only to
-- the server; clients pass `mimicDisguised` to keep it green until revealed.
function DotRules.classify(
	tags: { string },
	tagNames: { terrain: string, friend: string, enemy: string },
	mimicDisguised: boolean
): DotClass
	local has: { [string]: boolean } = {}
	for _, t in tags do
		has[t] = true
	end
	if has[tagNames.enemy] then
		if mimicDisguised and has[tagNames.friend] then
			return "friend"
		end
		return "enemy"
	end
	if has[tagNames.friend] then
		return "friend"
	end
	return "terrain"
end

-- Lifetime in seconds for a class.
function DotRules.lifetime(
	class: DotClass,
	lifetimes: { terrain: number, friend: number, enemy: number }
): number
	return lifetimes[class]
end

-- Heat update: returns new heat in [0,1] and whether the gun is locked out.
function DotRules.stepHeat(
	heat: number,
	focusing: boolean,
	dt: number,
	heatRate: number,
	coolRate: number
): number
	if focusing then
		return math.min(1, heat + heatRate * dt)
	end
	return math.max(0, heat - coolRate * dt)
end

return DotRules
