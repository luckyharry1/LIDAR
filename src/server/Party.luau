--!strict
-- Optional lobby flow: when Config.Places.runPlaceId is set and this server is not that
-- place, this server is a lobby and pressing Play sends everyone in it to one reserved run
-- server, so a party of friends gets a private instance. With the id left at zero the game
-- runs entirely in one place and the server itself is the party.
--
-- This path needs a published experience with two places and cannot be exercised in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)

local Party = {}

local launching = false

function Party.isLobby(): boolean
	local runPlaceId = Config.Places.runPlaceId
	return runPlaceId ~= 0 and game.PlaceId ~= runPlaceId
end

function Party.launch(players: { Player })
	if launching then
		return
	end
	launching = true
	for _, player in players do
		Remotes.send(player, "Toast", "Opening a private survey for everyone here.", "info")
	end
	local ok, message = pcall(function()
		local code = TeleportService:ReserveServer(Config.Places.runPlaceId)
		TeleportService:TeleportToPrivateServer(Config.Places.runPlaceId, code, players)
	end)
	if not ok then
		warn("[Party] teleport failed: " .. tostring(message))
		for _, player in players do
			Remotes.send(
				player,
				"Toast",
				"Could not open a private survey. Please try again.",
				"warn"
			)
		end
	end
	launching = false
end

return Party
