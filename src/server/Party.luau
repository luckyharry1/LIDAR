--!strict
-- Every party gets its own server. A public server is only a lobby: pressing Play there reserves
-- a fresh server (TeleportService:ReserveServer) and teleports the player, or the whole Play
-- Together crew, into it. A stranger can never land in someone else's run, and the lobby never
-- builds a level. The reserved server starts the arrivals together from the teleport data.
--
-- With Config.Places.runPlaceId at zero the reserved server is of this same place. Studio and
-- any server that is already reserved (including a VIP server) run the game directly, so this
-- path needs a published experience and cannot be exercised in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Handoff = require(ReplicatedStorage.Shared.pure.Handoff)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)

local Party = {}

local inFlight: { [Player]: string } = {} -- players with a teleport under way, and their mode

local function runPlaceId(): number
	local id = Config.Places.runPlaceId
	return if id ~= 0 then id else game.PlaceId
end

-- True on a server that only sends people to their own run.
function Party.isLobby(): boolean
	if RunService:IsStudio() or not Config.Places.reserveServers then
		return false
	end
	if Config.Places.runPlaceId ~= 0 and game.PlaceId ~= Config.Places.runPlaceId then
		return true -- the start place of a two-place setup
	end
	return game.PrivateServerId == ""
end

-- What the lobby told this player's server to do, or nil for an ordinary join.
function Party.arrival(player: Player): Handoff.Handoff?
	local ok, join = pcall(function()
		return player:GetJoinData()
	end)
	if not ok then
		return nil
	end
	return Handoff.decode(join.TeleportData, Config.Coop.maxPlayers)
end

-- Reserves one server and sends the crew (leader first) into it. Every profile is saved and
-- released first so the new server can load it. Returns false, after telling the players, if
-- nothing was sent: the caller then starts them in place, so nobody is stranded. A failure
-- after the teleport was accepted comes back through watchFailures.
function Party.launch(crew: { Player }, mode: string): boolean
	local going: { Player } = {}
	for _, player in crew do
		if player.Parent ~= nil and inFlight[player] == nil and #going < Config.Coop.maxPlayers then
			table.insert(going, player)
		end
	end
	if #going == 0 then
		return false
	end
	local function fail(reason: string)
		warn("[Party] could not open a server: " .. reason)
		for _, player in going do
			inFlight[player] = nil
			Data.reclaim(player)
			Remotes.send(
				player,
				"Toast",
				"No corner of the dark free. Starting here instead.",
				"warn"
			)
		end
	end
	for _, player in going do
		inFlight[player] = mode
		Remotes.send(player, "Toast", "Finding your own corner of the dark...", "info")
	end
	for _, player in going do
		if not Data.handOff(player) then
			fail("could not save " .. player.Name)
			return false
		end
	end
	local ok, message = pcall(function()
		local code = TeleportService:ReserveServer(runPlaceId())
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData(Handoff.encode(mode, #going))
		TeleportService:TeleportAsync(runPlaceId(), going, options)
	end)
	if not ok then
		fail(tostring(message))
		return false
	end
	return true
end

-- Calls back with the player and the mode they chose when a teleport fails after it was
-- accepted, so the caller can start them in place.
function Party.watchFailures(onFailed: (Player, string) -> ())
	TeleportService.TeleportInitFailed:Connect(function(player: Player, _result, message: string)
		local mode = inFlight[player]
		if mode == nil then
			return
		end
		warn(`[Party] teleport of {player.Name} failed: {message}`)
		inFlight[player] = nil
		Data.reclaim(player)
		Remotes.send(player, "Toast", "No corner of the dark free. Starting here instead.", "warn")
		onFailed(player, mode)
	end)
end

function Party.forget(player: Player)
	inFlight[player] = nil
end

return Party
