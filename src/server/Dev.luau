--!strict
-- Studio-only playtest commands, so a tester does not have to play through seven tiers to
-- look at the eighth. Does nothing at all outside Studio.
--
-- From the Studio command bar while playing (server side):
--   workspace:SetAttribute("DevCommand", "tier 6")      jump to a tier
--   workspace:SetAttribute("DevCommand", "lore office")  visit a lore room (office, breakroom,
--                                                        nursery, stairwell, landing)
--   workspace:SetAttribute("DevCommand", "clear")        finish the current level
--   workspace:SetAttribute("DevCommand", "static 500")   give everyone Static
--   workspace:SetAttribute("DevCommand", "lights on")    light the maze to inspect it ("lights off")

local RunService = game:GetService("RunService")

local Director = require(script.Parent.Director)

local COMMAND_ATTRIBUTE = "DevCommand"
local LIGHTS_ATTRIBUTE = "DevLit"

local Dev = {}

local function run(text: string)
	local words = string.split(text, " ")
	local command, argument = words[1], words[2]
	if command == "tier" and tonumber(argument) then
		Director.dev.jumpToTier(math.max(1, math.floor(tonumber(argument) :: number)))
	elseif command == "lore" and argument then
		Director.dev.enterLore(argument)
	elseif command == "clear" then
		Director.dev.clearLevel()
	elseif command == "static" and tonumber(argument) then
		Director.dev.grant(math.floor(tonumber(argument) :: number))
	elseif command == "lights" then
		workspace:SetAttribute(LIGHTS_ATTRIBUTE, argument == "on")
	else
		warn("[Dev] unknown command: " .. text)
	end
end

function Dev.start()
	if not RunService:IsStudio() then
		return
	end
	workspace:GetAttributeChangedSignal(COMMAND_ATTRIBUTE):Connect(function()
		local text = workspace:GetAttribute(COMMAND_ATTRIBUTE)
		if type(text) == "string" and text ~= "" then
			workspace:SetAttribute(COMMAND_ATTRIBUTE, "")
			run(text)
		end
	end)
end

return Dev
