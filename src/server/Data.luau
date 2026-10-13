--!strict
-- Player profiles: load, autosave and release, on top of DataStoreService.
--
-- Safety properties:
--  * Every call into the DataStore is wrapped in pcall and retried with exponential backoff.
--  * A session lock stored inside the save stops two servers writing the same profile. A lock
--    older than Config.Save.lockSeconds is treated as stale (its server crashed).
--  * Saves use UpdateAsync and are refused if another server has taken the lock.
--  * If DataStores are unavailable (Studio with API access off, or an outage) the profile
--    lives in memory for the session, the player is told, and nothing is written.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SaveData = require(ReplicatedStorage.Shared.pure.SaveData)

export type Profile = SaveData.Profile

type Session = {
	profile: Profile,
	persistent: boolean, -- false when running on the in-memory fallback
	dirty: boolean,
}

local LOCK_KEY = "sessionLock"
local SAVE_RETRIES = 3

local Data = {}

local sessions: { [Player]: Session } = {}
local store: DataStore? = nil
local storeChecked = false

local function getStore(): DataStore?
	if not storeChecked then
		storeChecked = true
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(Config.Save.storeName)
		end)
		if ok then
			store = result
		else
			warn("[Data] DataStore unavailable, using in-memory saves: " .. tostring(result))
		end
	end
	return store
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function retry<T>(attempts: number, action: () -> T): (boolean, T | string)
	local lastError = "no attempts made"
	for attempt = 1, attempts do
		local ok, result = pcall(action)
		if ok then
			return true, result
		end
		lastError = tostring(result)
		if attempt < attempts then
			task.wait(Config.Save.retryBaseSeconds * 2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

-- Loads (or creates) the profile for a player. Never fails: worst case is a fresh in-memory
-- profile. Returns the profile and whether it will be persisted.
function Data.load(player: Player): (Profile, boolean)
	local dataStore = getStore()
	local session: Session = { profile = SaveData.default(), persistent = false, dirty = false }
	if dataStore ~= nil then
		local lockedElsewhere = false
		-- In Studio a failure means API access is off; retrying would only delay the session.
		local attempts = if RunService:IsStudio() then 1 else Config.Save.loadRetries
		local ok, result = retry(attempts, function()
			lockedElsewhere = false
			local loaded: any = nil
			dataStore:UpdateAsync(keyFor(player), function(stored: any)
				local lock = if type(stored) == "table" then stored[LOCK_KEY] else nil
				local now = os.time()
				if
					type(lock) == "table"
					and lock.jobId ~= game.JobId
					and type(lock.time) == "number"
					and now - lock.time < Config.Save.lockSeconds
				then
					lockedElsewhere = true
					return nil -- leave the stored value untouched
				end
				local value = if type(stored) == "table" then stored else {}
				value[LOCK_KEY] = { jobId = game.JobId, time = now }
				loaded = value
				return value
			end)
			if lockedElsewhere then
				error("profile is locked by another server")
			end
			return loaded
		end)
		if ok then
			session.profile = SaveData.load(result)
			session.persistent = true
		else
			warn(
				`[Data] Could not load {player.Name}: {result}. Progress will not be saved this session.`
			)
		end
	end
	if not player:IsDescendantOf(Players) then
		-- The player left while we were loading: give the lock straight back.
		sessions[player] = session
		Data.release(player)
		return session.profile, false
	end
	sessions[player] = session
	return session.profile, session.persistent
end

function Data.get(player: Player): Profile?
	local session = sessions[player]
	return if session then session.profile else nil
end

function Data.isPersistent(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.persistent
end

-- Marks a profile as changed so the next autosave writes it.
function Data.touch(player: Player)
	local session = sessions[player]
	if session then
		session.dirty = true
	end
end

local function write(player: Player, session: Session, releaseLock: boolean): boolean
	local dataStore = getStore()
	if dataStore == nil or not session.persistent then
		return false
	end
	local refused = false
	local ok, result = retry(if RunService:IsStudio() then 1 else SAVE_RETRIES, function()
		refused = false
		dataStore:UpdateAsync(keyFor(player), function(stored: any)
			local lock = if type(stored) == "table" then stored[LOCK_KEY] else nil
			if type(lock) == "table" and lock.jobId ~= game.JobId then
				refused = true
				return nil -- another server owns this profile now: do not overwrite it
			end
			local value: { [string]: any } = table.clone(session.profile :: any)
			if not releaseLock then
				value[LOCK_KEY] = { jobId = game.JobId, time = os.time() }
			end
			return value
		end)
		return true
	end)
	if not ok then
		warn(`[Data] Save failed for {player.Name}: {result}`)
		return false
	end
	if refused then
		warn(`[Data] Save refused for {player.Name}: profile is owned by another server.`)
		session.persistent = false
		return false
	end
	session.dirty = false
	return true
end

-- Saves now if anything changed (used at lore rooms and by the autosave loop).
function Data.save(player: Player): boolean
	local session = sessions[player]
	if session == nil or not session.dirty then
		return false
	end
	return write(player, session, false)
end

-- Final save when a player leaves; also gives up the session lock.
function Data.release(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	sessions[player] = nil
	write(player, session, true)
end

function Data.start()
	task.spawn(function()
		while true do
			task.wait(Config.Save.autosaveSeconds)
			for player in sessions do
				task.spawn(Data.save, player)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and #Players:GetPlayers() == 0 then
			return
		end
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				Data.release(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)
end

return Data
