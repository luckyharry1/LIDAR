--!strict
local Config = require("../src/shared/Config")
local Dread = require("../src/shared/pure/Dread")
local Rng = require("../src/shared/pure/Rng")

local settings = Config.Scare
local tests: { [string]: () -> () } = {}

-- Plays `seconds` of walking in the dark at 10 steps a second; returns when the scare fired.
local function walk(state: Dread.State, seconds: number, threat: number, rng: Rng.Rng): number?
	local dt = 0.1
	for step = 1, math.floor(seconds / dt) do
		if Dread.step(state, settings, dt, true, true, threat, rng:next()) then
			return step * dt
		end
	end
	return nil
end

tests["the first floor never holds a scare"] = function()
	for roll = 0, 99 do
		local state = Dread.new(settings)
		Dread.enterLevel(state, settings, settings.minTier - 1, roll / 100)
		assert(not state.armed, "armed on the first floor")
	end
end

tests["a level holds a scare only some of the time"] = function()
	local armed = 0
	for roll = 0, 99 do
		local state = Dread.new(settings)
		Dread.enterLevel(state, settings, 3, roll / 100)
		if state.armed then
			armed += 1
		end
	end
	assert(armed > 20 and armed < 70, `{armed} of 100 levels armed`)
end

tests["nothing happens before the grace period, the minimum time or the dread"] = function()
	local rng = Rng.new(5)
	local state = Dread.new(settings)
	Dread.enterLevel(state, settings, 3, 0)
	assert(state.armed, "level not armed")
	assert(walk(state, 60, 1, rng) == nil, "scared in the first minute")
end

tests["the dread fills and the scare comes within the fuse"] = function()
	local rng = Rng.new(9)
	local state = Dread.new(settings)
	state.cooldown = 0
	Dread.enterLevel(state, settings, 4, 0)
	local latest = settings.buildSeconds + settings.fuseMax + 1
	local fired = walk(state, latest, 0, rng)
	assert(fired ~= nil, "no scare in a full level of walking")
	assert(fired >= settings.minLevelSeconds, "fired before the minimum time")
	assert(not state.armed, "still armed after firing")
	assert(walk(state, 600, 1, rng) == nil, "a second scare in the same level")
end

tests["standing still builds nothing"] = function()
	local state = Dread.new(settings)
	state.cooldown = 0
	Dread.enterLevel(state, settings, 4, 0)
	for _ = 1, 20000 do
		assert(not Dread.step(state, settings, 0.1, true, false, 0, 0.5), "scared a still player")
	end
	assert(state.dread == 0, "dread built while standing still")
end

tests["a real monster nearby makes it come sooner"] = function()
	local calm, tense = Dread.new(settings), Dread.new(settings)
	for _, state in { calm, tense } do
		state.cooldown = 0
		Dread.enterLevel(state, settings, 4, 0)
	end
	local rng = Rng.new(3)
	local a = walk(calm, 600, 0, rng)
	local b = walk(tense, 600, 1, Rng.new(3))
	assert(a ~= nil and b ~= nil and b < a, "threat did not speed the dread up")
end

tests["an ineligible moment pauses everything"] = function()
	local state = Dread.new(settings)
	state.cooldown = 0
	Dread.enterLevel(state, settings, 4, 0)
	for _ = 1, 20000 do
		assert(not Dread.step(state, settings, 0.1, false, true, 0, 0.5), "scared at a bad time")
	end
	assert(state.dread == 0 and state.levelSeconds == 0, "time counted while ineligible")
end

tests["the cooldown spans levels"] = function()
	local rng = Rng.new(2)
	local state = Dread.new(settings)
	state.cooldown = 0
	Dread.enterLevel(state, settings, 4, 0)
	assert(walk(state, 600, 0, rng) ~= nil, "no first scare")
	Dread.enterLevel(state, settings, 5, 0)
	assert(state.armed, "next level not armed")
	local fired = walk(state, 600, 1, rng)
	assert(fired == nil or fired >= settings.cooldownSeconds, "ignored the cooldown")
end

return tests
