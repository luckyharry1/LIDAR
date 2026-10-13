--!strict
-- Lune test runner: executes every suite and exits non-zero on failure.
local process = require("@lune/process")

local suites = {
	require("./MazeTests"),
}

local failed = 0
for _, suite in suites do
	for name, fn in suite do
		local ok, err = pcall(fn)
		if ok then
			print("PASS " .. name)
		else
			failed += 1
			print("FAIL " .. name .. ": " .. tostring(err))
		end
	end
end
if failed > 0 then
	process.exit(1)
end
print("all tests passed")
