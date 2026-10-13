--!strict
-- Daily challenge leaderboard: best clear time per player per day, in an OrderedDataStore
-- named for the date. Falls back to an in-memory board when DataStores are unavailable.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Daily = require(ReplicatedStorage.Shared.pure.Daily)

export type Entry = { name: string, ms: number, you: boolean }

local CACHE_SECONDS = 60
local UNKNOWN_NAME = "Surveyor"

local Leaderboard = {}

local memory: { [number]: { [number]: number } } = {} -- memory[day][userId] = ms
local names: { [number]: string } = {}
local cache: { [number]: { at: number, rows: { { userId: number, ms: number } } } } = {}

local function storeFor(day: number): OrderedDataStore?
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.Daily.storePrefix .. Daily.key(day))
	end)
	return if ok then result else nil
end

local function nameOf(userId: number): string
	if names[userId] == nil then
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		names[userId] = if ok then result else UNKNOWN_NAME
	end
	return names[userId]
end

-- Records a clear time. Only improves on the stored time; returns the player's best for the day.
function Leaderboard.submit(player: Player, day: number, ms: number): number
	names[player.UserId] = player.Name
	local time = math.max(1, math.floor(ms))
	local board = memory[day]
	if board == nil then
		board = {}
		memory[day] = board
	end
	local best = math.min(board[player.UserId] or math.huge, time)
	board[player.UserId] = best

	local store = storeFor(day)
	if store ~= nil then
		local ok, result = pcall(function()
			return store:UpdateAsync(tostring(player.UserId), function(previous: number?)
				if previous ~= nil and previous <= time then
					return nil
				end
				return time
			end)
		end)
		if ok and type(result) == "number" then
			best = math.min(best, result)
		elseif not ok then
			warn("[Leaderboard] submit failed: " .. tostring(result))
		end
	end
	cache[day] = nil
	return best
end

-- The fastest times for a day, fastest first.
function Leaderboard.top(day: number, viewer: Player): { Entry }
	local cached = cache[day]
	local rows: { { userId: number, ms: number } }
	if cached ~= nil and os.clock() - cached.at < CACHE_SECONDS then
		rows = cached.rows
	else
		rows = {}
		local store = storeFor(day)
		local ok = false
		if store ~= nil then
			ok = pcall(function()
				local pages = store:GetSortedAsync(true, Config.Daily.boardSize)
				for _, item in pages:GetCurrentPage() do
					table.insert(rows, { userId = tonumber(item.key) or 0, ms = item.value })
				end
			end)
		end
		if not ok then
			rows = {}
			for userId, ms in memory[day] or {} do
				table.insert(rows, { userId = userId, ms = ms })
			end
			table.sort(rows, function(a, b)
				return a.ms < b.ms
			end)
			while #rows > Config.Daily.boardSize do
				table.remove(rows)
			end
		end
		cache[day] = { at = os.clock(), rows = rows }
	end
	local entries: { Entry } = {}
	for _, row in rows do
		table.insert(
			entries,
			{ name = nameOf(row.userId), ms = row.ms, you = row.userId == viewer.UserId }
		)
	end
	return entries
end

return Leaderboard
