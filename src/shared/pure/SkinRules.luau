--!strict
-- Who may wear which skin. Pure functions, shared by the server (which decides) and the client
-- (which only draws the buttons), so the two can never disagree about what a button should say.

local SaveData = require("./SaveData")
local Skins = require("../data/Skins")

export type Passes = { [string]: boolean } -- Config.Monetization.skinPassIds keys the player owns

export type Status = "owned" | "playtime" | "robux"

local SkinRules = {}

function SkinRules.requiredSeconds(def: Skins.SkinDef): number
	return (def.minutes or 0) * 60
end

-- "owned" when the player may wear it; otherwise what is still needed ("playtime" or "robux").
function SkinRules.status(def: Skins.SkinDef, playSeconds: number, passes: Passes): Status
	if def.kind == "playtime" then
		return if playSeconds >= SkinRules.requiredSeconds(def) then "owned" else "playtime"
	end
	if passes[Skins.packKey] or (def.pass ~= nil and passes[def.pass]) then
		return "owned"
	end
	return "robux"
end

function SkinRules.secondsLeft(def: Skins.SkinDef, playSeconds: number): number
	return math.max(0, SkinRules.requiredSeconds(def) - playSeconds)
end

-- Playtime skins that a player crossed the line for between two readings of the clock.
function SkinRules.newlyEarned(before: number, after: number): { Skins.SkinDef }
	local earned = {}
	for _, def in Skins.list do
		if def.kind == "playtime" then
			local needed = SkinRules.requiredSeconds(def)
			if before < needed and after >= needed then
				table.insert(earned, def)
			end
		end
	end
	return earned
end

-- Puts a skin on, or takes it off with an empty id. The server calls this; it refuses a skin the
-- player has not unlocked, so a client cannot wear what it did not earn or buy.
function SkinRules.equip(profile: SaveData.Profile, id: string, passes: Passes): (boolean, string)
	if id == "" then
		profile.skin = ""
		return true, "Back to the classic look!"
	end
	local def = Skins.byId[id]
	if def == nil then
		return false, "Hmm, we do not know that skin."
	end
	if SkinRules.status(def, profile.stats.playSeconds, passes) ~= "owned" then
		return false, "Not unlocked yet. Keep exploring!"
	end
	profile.skin = id
	return true, def.name .. " is on!"
end

-- Drops an equipped skin the player no longer qualifies for (a pass that could not be
-- confirmed after a restore, say). Returns true if it changed anything.
function SkinRules.enforce(profile: SaveData.Profile, passes: Passes): boolean
	local def = Skins.byId[profile.skin]
	if def ~= nil and SkinRules.status(def, profile.stats.playSeconds, passes) ~= "owned" then
		profile.skin = ""
		return true
	end
	return false
end

return SkinRules
