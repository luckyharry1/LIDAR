local process = require("@lune/process")
local Sim = require("../tests/Sim")
local tier = tonumber(process.args[1]) or 1
local first = tonumber(process.args[2]) or 1
local last = tonumber(process.args[3]) or first
for seed = first, last do
	local lines = {}
	local r = Sim.run(tier, seed * 101 + tier, 900, function(line)
		table.insert(lines, line)
	end)
	print(
		string.format(
			"seed %d cleared=%s t=%.0f deaths=%d",
			seed,
			tostring(r.cleared),
			r.seconds,
			r.deaths
		)
	)
	for i = 1, math.min(#lines, 4) do
		print("   " .. lines[i])
	end
	local parts = {}
	for mode, seconds in r.modeSeconds do
		table.insert(parts, string.format("%s=%.0f", mode, seconds))
	end
	table.sort(parts)
	print("   " .. table.concat(parts, " "))
end
