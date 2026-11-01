--!strict
-- Roblox badges for the first few things a player does. Each badge id lives in Config.Badges;
-- an id of 0 means "not created yet" and awards nothing. Awarding is wrapped in pcall (the
-- badge service can fail or be throttled) and remembered per session so it is asked for once.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Badges = {}

local asked: { [Player]: { [string]: boolean } } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	asked[player] = nil
end)

-- Awards the badge named `key` in Config.Badges ("firstScan", "firstHaven", "levelCleared",
-- "hiddenFound"). Does nothing when its id is 0 or it was already asked for this session.
function Badges.award(player: Player, key: string)
	local id = (Config.Badges :: { [string]: number })[key]
	if id == nil or id == 0 then
		return
	end
	local done = asked[player]
	if done == nil then
		done = {}
		asked[player] = done
	end
	if done[key] then
		return
	end
	done[key] = true
	task.spawn(function()
		local ok, err = pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, id) then
				BadgeService:AwardBadge(player.UserId, id)
			end
		end)
		if not ok then
			done[key] = nil -- try again at the next chance
			warn("[Badges] " .. key .. " not awarded: " .. tostring(err))
		end
	end)
end

return Badges
