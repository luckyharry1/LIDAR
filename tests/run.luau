--!strict
-- Lune test runner: executes every suite and exits non-zero on failure.
-- Usage: lune run tests/run
local process = require("@lune/process")

local suites: { { name: string, tests: { [string]: () -> () } } } = {
	{ name = "Maze", tests = require("./MazeTests") },
	{ name = "LevelPlan", tests = require("./LevelPlanTests") },
	{ name = "DotRules", tests = require("./DotRulesTests") },
	{ name = "EnemyBrain", tests = require("./EnemyBrainTests") },
	{ name = "Progression", tests = require("./ProgressionTests") },
	{ name = "SaveData", tests = require("./SaveDataTests") },
	{ name = "Daily", tests = require("./DailyTests") },
	{ name = "Simulation", tests = require("./SimTests") },
	{ name = "Lore", tests = require("./LoreTests") },
	{ name = "Source", tests = require("./SourceTests") },
}

local passed, failed = 0, 0
for _, suite in suites do
	local names = {}
	for name in suite.tests do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local ok, err = pcall(suite.tests[name])
		if ok then
			passed += 1
			print(`PASS {suite.name}: {name}`)
		else
			failed += 1
			print(`FAIL {suite.name}: {name}\n     {err}`)
		end
	end
end
print(`{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
