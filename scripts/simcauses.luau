local process = require("@lune/process")
local Sim = require("../tests/Sim")
local tier = tonumber(process.args[1]) or 1
local runs = tonumber(process.args[2]) or 20
local counts = {}
local modes = {}
local cleared = 0
for seed = 1, runs do
	local r = Sim.run(tier, seed * 101 + tier, 900, function(line)
		local kind, state, mode = string.match(line, "caught by (%w+) %((%w+)%).*mode=(%w+)")
		local key = kind .. "/" .. state .. " while " .. mode
		counts[key] = (counts[key] or 0) + 1
	end)
	if r.cleared then
		cleared += 1
	end
	for mode, seconds in r.modeSeconds do
		modes[mode] = (modes[mode] or 0) + seconds
	end
end
print("tier", tier, "cleared", cleared .. "/" .. runs)
local keys = {}
for key in counts do
	table.insert(keys, key)
end
table.sort(keys, function(a, b)
	return counts[a] > counts[b]
end)
for _, key in keys do
	print(string.format("  %4d  %s", counts[key], key))
end
local parts = {}
for mode, seconds in modes do
	table.insert(parts, string.format("%s=%.0f", mode, seconds / runs))
end
table.sort(parts)
print("  mean seconds per mode: " .. table.concat(parts, " "))
