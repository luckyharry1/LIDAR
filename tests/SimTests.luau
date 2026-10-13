--!strict
-- Headless simulation: a scripted bot plays every tier against the real enemy logic.
local Sim = require("./Sim")

local RUNS_PER_TIER = 25
local MAX_SECONDS = 900 -- simulated seconds allowed per level
local LAST_TIER = 11 -- eight authored tiers plus three endless ones
local MIN_CLEAR_RATE = 0.8

local tests: { [string]: () -> () } = {}

tests["every tier is completable and nothing deadlocks"] = function()
	for tier = 1, LAST_TIER do
		local cleared = 0
		for seed = 1, RUNS_PER_TIER do
			local result = Sim.run(tier, seed * 101 + tier, MAX_SECONDS)
			assert(not result.stuck, `bot deadlocked at tier {tier}, seed {seed}`)
			if result.cleared then
				cleared += 1
			end
		end
		local rate = cleared / RUNS_PER_TIER
		assert(rate >= MIN_CLEAR_RATE, `tier {tier} clear rate {rate} is below {MIN_CLEAR_RATE}`)
	end
end

tests["simulation is deterministic"] = function()
	local a = Sim.run(5, 77, MAX_SECONDS)
	local b = Sim.run(5, 77, MAX_SECONDS)
	assert(
		a.cleared == b.cleared and a.seconds == b.seconds and a.deaths == b.deaths,
		"two identical runs diverged"
	)
end

tests["tier one is forgiving"] = function()
	local deaths = 0
	for seed = 1, RUNS_PER_TIER do
		local result = Sim.run(1, seed, MAX_SECONDS)
		assert(result.cleared, "bot failed tier one with seed " .. seed)
		deaths += result.deaths
	end
	assert(
		deaths / RUNS_PER_TIER < 1,
		"tier one kills the bot too often: " .. deaths / RUNS_PER_TIER
	)
end

return tests
