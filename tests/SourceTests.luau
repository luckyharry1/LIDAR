--!strict
-- Guards against mistakes the linter and the type checker both miss.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ROOT = "src"

local function sources(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			sources(path, out)
		elseif path:match("%.luau$") then
			table.insert(out, path)
		end
	end
end

local tests: { [string]: () -> () } = {}

-- Every script compiles (syntax, local limits).
tests["every source file compiles"] = function()
	local files = {}
	sources(ROOT, files)
	for _, path in files do
		local ok, err = pcall(function()
			luau.compile(fs.readFile(path))
		end)
		assert(ok, path .. ": " .. tostring(err))
	end
end

-- `Ui.new({...})(Net.get("X"))` is what a statement starting with "(" becomes when the line
-- before it has no semicolon: Luau calls the previous expression instead of starting a new
-- statement. It crashed the whole client at startup once (nothing flags it), so no source
-- line may join a call straight to another parenthesis.
tests["no call is joined to the next statement"] = function()
	local files = {}
	sources(ROOT, files)
	for _, path in files do
		local number = 0
		for line in fs.readFile(path):gmatch("[^\n]*") do
			number += 1
			local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""')
			assert(
				not code:find("%)%("),
				`{path}:{number}: ")(" joins a call to a following parenthesis`
			)
		end
	end
end

return tests
