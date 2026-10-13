--!strict
-- Prints per-tier results of the headless bot simulation as a Markdown table.
-- Usage: lune run scripts/simstats [runsPerTier]
local process = require("@lune/process")
local Sim = require("../tests/Sim")

local runs = tonumber(process.args[1]) or 100
local MAX_SECONDS = 900
local LAST_TIER = 11

print("| Tier | Clear rate | Mean time to clear (s) | Mean catches per run | Deadlocks |")
print("| --- | --- | --- | --- | --- |")
for tier = 1, LAST_TIER do
	local cleared, seconds, deaths, stuck = 0, 0, 0, 0
	for seed = 1, runs do
		local result = Sim.run(tier, seed * 101 + tier, MAX_SECONDS)
		deaths += result.deaths
		if result.stuck then
			stuck += 1
		end
		if result.cleared then
			cleared += 1
			seconds += result.seconds
		end
	end
	local mean = if cleared > 0 then seconds / cleared else 0
	print(
		string.format(
			"| %d | %.0f%% | %.0f | %.2f | %d |",
			tier,
			100 * cleared / runs,
			mean,
			deaths / runs,
			stuck
		)
	)
end
