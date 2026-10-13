--!strict
-- Creates every remote and is the only place client messages enter the server.
-- Each client-to-server remote has a validator (argument types and ranges) and a rate limit;
-- anything that fails either check is dropped before it reaches game code.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

type Validator = (...any) -> boolean
type Handler = (player: Player, ...any) -> ()

local MAX_STRING = 40
local MAX_COORDINATE = 100000
local BURST_SECONDS = 1 -- a bucket holds this many seconds of allowance

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = Net.folderName

local instances: { [string]: RemoteEvent | UnreliableRemoteEvent } = {}
for _, list in { Net.clientToServer, Net.serverToClient } do
	for _, name in list do
		local remote: Instance = if Net.unreliable[name]
			then Instance.new("UnreliableRemoteEvent")
			else Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		instances[name] = remote :: any
	end
end
folder.Parent = ReplicatedStorage

-- Token buckets: buckets[player][remoteName] = { tokens, lastRefill }
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

local function allow(player: Player, name: string): boolean
	local rate = Config.Net.rateLimits[name]
	local perPlayer = buckets[player]
	if perPlayer == nil then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[name]
	if bucket == nil then
		bucket = { tokens = rate * BURST_SECONDS, last = now }
		perPlayer[name] = bucket
	end
	bucket.tokens = math.min(rate * BURST_SECONDS, bucket.tokens + (now - bucket.last) * rate)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function isFiniteVector(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	return v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and math.abs(v.X) < MAX_COORDINATE
		and math.abs(v.Y) < MAX_COORDINATE
		and math.abs(v.Z) < MAX_COORDINATE
end

local function isShortString(value: any): boolean
	return type(value) == "string" and #value <= MAX_STRING
end

local function isInteger(value: any, min: number, max: number): boolean
	return type(value) == "number" and value == math.floor(value) and value >= min and value <= max
end

-- Argument validators. A remote with no entry here accepts no arguments at all.
local VALIDATORS: { [string]: Validator } = {
	ScanState = function(firing, focusing, look, origin)
		return type(firing) == "boolean"
			and type(focusing) == "boolean"
			and isFiniteVector(look)
			and isFiniteVector(origin)
	end,
	Ping = function(position)
		return isFiniteVector(position)
	end,
	Emote = function(index)
		return isInteger(index, 1, #Config.Coop.emotes)
	end,
	BuyUpgrade = function(id)
		return isShortString(id)
	end,
	EquipCosmetic = function(slot, id)
		return isShortString(slot) and isShortString(id)
	end,
	ToggleUpgrade = function(id, on)
		return isShortString(id) and type(on) == "boolean"
	end,
	SetSetting = function(key, value)
		return isShortString(key)
			and (type(value) == "boolean" or type(value) == "number" or isShortString(value))
	end,
	Start = function(mode)
		return mode == "continue" or mode == "new" or mode == "daily"
	end,
	Funnel = function(step)
		return isShortString(step)
	end,
}

-- Fail at startup, not at the first call, if a remote is missing its validator or limit.
for _, name in Net.clientToServer do
	assert(VALIDATORS[name] ~= nil, "remote " .. name .. " has no validator")
	assert(Config.Net.rateLimits[name] ~= nil, "remote " .. name .. " has no rate limit")
end

-- Registers the handler for a client-to-server remote. Invalid or over-rate calls are dropped.
function Remotes.on(name: string, handler: Handler)
	local remote = instances[name]
	local validate = VALIDATORS[name]
	assert(remote ~= nil and validate ~= nil, "unknown client remote " .. name)
	local function receive(player: Player, ...: any)
		if select("#", ...) > 8 or not allow(player, name) or not validate(...) then
			return
		end
		handler(player, ...)
	end
	if remote:IsA("UnreliableRemoteEvent") then
		remote.OnServerEvent:Connect(receive)
	else
		(remote :: RemoteEvent).OnServerEvent:Connect(receive)
	end
end

function Remotes.send(player: Player, name: string, ...: any)
	local remote = instances[name]
	if remote:IsA("UnreliableRemoteEvent") then
		remote:FireClient(player, ...)
	else
		(remote :: RemoteEvent):FireClient(player, ...)
	end
end

function Remotes.sendAll(name: string, ...: any)
	for _, player in Players:GetPlayers() do
		Remotes.send(player, name, ...)
	end
end

return Remotes
