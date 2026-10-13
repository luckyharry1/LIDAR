--!strict
-- Client entry point: starts every controller in dependency order.

local StarterGui = game:GetService("StarterGui")

local Atmosphere = require(script.Parent.Atmosphere)
local Audio = require(script.Parent.Audio)
local Avatar = require(script.Parent.Avatar)
local Dots = require(script.Parent.Dots)
local Effects = require(script.Parent.Effects)
local Hud = require(script.Parent.Hud)
local Input = require(script.Parent.Input)
local Lidar = require(script.Parent.Lidar)
local Menus = require(script.Parent.Menus)
local State = require(script.Parent.State)
local Title = require(script.Parent.Title)
local Tutorial = require(script.Parent.Tutorial)
local Viewmodel = require(script.Parent.Viewmodel)

-- Core interface the game does not use; SetCoreGuiEnabled can fail while the core scripts
-- are still loading, so retry a few times.
local HIDDEN_CORE = {
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.EmotesMenu,
	Enum.CoreGuiType.PlayerList,
}
local CORE_RETRIES = 8

task.spawn(function()
	for _ = 1, CORE_RETRIES do
		local ok = pcall(function()
			for _, coreType in HIDDEN_CORE do
				StarterGui:SetCoreGuiEnabled(coreType, false)
			end
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

Dots.start()
Input.start()
Atmosphere.start()
Lidar.start()
Audio.start()
Hud.start()
Menus.start()
Avatar.start()
Viewmodel.start()
Effects.start()
Tutorial.start()
Title.start()

Atmosphere.onZone(function(zone)
	Audio.setLit(zone ~= nil)
	if zone then
		local title = zone:GetAttribute("Title")
		local subtitle = zone:GetAttribute("Subtitle")
		if type(title) == "string" and type(subtitle) == "string" then
			Hud.titleCard(title, subtitle)
		end
	end
end)

State.onState(function(server)
	Lidar.enabled = server.stage ~= "title"
end)

State.connect()
