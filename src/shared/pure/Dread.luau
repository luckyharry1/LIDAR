--!strict
-- When the close encounter happens. A scare has to be rare and earned, so it is not a timer: a
-- level may or may not hold one (a coin toss on arrival), the dread builds only while the
-- player walks in the dark, builds faster when something real is near, and once it is full the
-- scare comes after a random fuse. A long cooldown spans levels. Pure: the caller supplies the
-- dice, so a test can play out a whole session.

export type Settings = {
	minTier: number,
	levelChance: number,
	firstGraceSeconds: number,
	cooldownSeconds: number,
	minLevelSeconds: number,
	buildSeconds: number,
	nearBonus: number,
	fuseMin: number,
	fuseMax: number,
}

export type State = {
	armed: boolean, -- this level holds a scare that has not happened yet
	dread: number, -- 0..1
	levelSeconds: number, -- seconds spent in this level (eligible time only)
	cooldown: number, -- seconds until another scare is allowed
	fuse: number?, -- seconds left once the dread is full
}

local Dread = {}

function Dread.new(settings: Settings): State
	return {
		armed = false,
		dread = 0,
		levelSeconds = 0,
		cooldown = settings.firstGraceSeconds,
		fuse = nil,
	}
end

-- A level begins. `roll` is a random number in [0, 1). The cooldown carries over.
function Dread.enterLevel(state: State, settings: Settings, tier: number, roll: number)
	state.armed = tier >= settings.minTier and roll < settings.levelChance
	state.dread = 0
	state.levelSeconds = 0
	state.fuse = nil
end

-- Advances `dt` seconds. `eligible` is true while a scare would land well (in the dark, no menu,
-- no scene, nothing real close); `moving` is whether the player is walking; `threat` is 0..1
-- for how near a real monster is. `roll` is a random number in [0, 1). Returns true on the
-- step the scare should begin.
function Dread.step(
	state: State,
	settings: Settings,
	dt: number,
	eligible: boolean,
	moving: boolean,
	threat: number,
	roll: number
): boolean
	state.cooldown = math.max(0, state.cooldown - dt)
	if not state.armed or not eligible then
		return false
	end
	state.levelSeconds += dt
	if moving then
		local speed = (1 + settings.nearBonus * math.clamp(threat, 0, 1)) / settings.buildSeconds
		state.dread = math.min(1, state.dread + speed * dt)
	end
	if state.dread < 1 or state.levelSeconds < settings.minLevelSeconds or state.cooldown > 0 then
		return false
	end
	local fuse = state.fuse
	if fuse == nil then
		fuse = settings.fuseMin + roll * (settings.fuseMax - settings.fuseMin)
	end
	fuse -= dt
	if fuse > 0 then
		state.fuse = fuse
		return false
	end
	state.fuse = nil
	state.armed = false
	state.dread = 0
	state.cooldown = settings.cooldownSeconds
	return true
end

return Dread
