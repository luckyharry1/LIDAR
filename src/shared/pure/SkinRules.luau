--!strict
-- Who may wear which Phosphor skin. Pure functions, shared by the server (which decides) and
-- the client (which only draws the buttons), so the two can never disagree about what a button
-- should say.

local SaveData = require("./SaveData")
local Skins = require("../data/Skins")

export type Passes = { [string]: boolean } -- Config.Monetization.skinPassIds keys the player owns

-- "owned" when the player may wear it; otherwise what is still needed.
export type Status = "owned" | "playtime" | "static" | "robux"

local SkinRules = {}

function SkinRules.requiredSeconds(def: Skins.SkinDef): number
	return (def.minutes or 0) * 60
end

function SkinRules.status(
	def: Skins.SkinDef,
	playSeconds: number,
	passes: Passes,
	ownedSkins: { [string]: boolean }
): Status
	if def.kind == "playtime" then
		return if playSeconds >= SkinRules.requiredSeconds(def) then "owned" else "playtime"
	end
	if def.kind == "static" then
		return if ownedSkins[def.id] then "owned" else "static"
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

-- The colour a player's terrain dots wear, as RGB: their skin's, else nil (the plain palette).
-- Shared by the player's own screen and what teammates see.
function SkinRules.wallTint(profile: SaveData.Profile): { number }?
	local skin = Skins.byId[profile.skin]
	return if skin ~= nil then skin.wall else nil
end

-- The skin colour for one kind of terrain dot: walls take the skin's colour as it is, floors a
-- little dimmer and ceilings dimmer still, so a skin reads on every surface while the three stay
-- apart. Other kinds (friend, enemy, water, objective, hazard) keep their meaning colours: nil.
function SkinRules.surfaceTint(wall: { number }, kind: string): { number }?
	local scale = if kind == "wall"
		then 1
		elseif kind == "floor" then 0.8
		elseif kind == "ceiling" then 0.6
		else nil
	if scale == nil then
		return nil
	end
	return {
		math.floor(wall[1] * scale + 0.5),
		math.floor(wall[2] * scale + 0.5),
		math.floor(wall[3] * scale + 0.5),
	}
end

-- Puts a skin on, or takes it off with an empty id. The server calls this; it refuses a skin the
-- player has not earned or bought, so a client cannot wear what it did not earn or buy. A Static
-- skin that is not owned yet is bought here (once) when the player can afford it, then worn.
function SkinRules.equip(profile: SaveData.Profile, id: string, passes: Passes): (boolean, string)
	if id == "" then
		profile.skin = ""
		return true, "Back to the classic look!"
	end
	local def = Skins.byId[id]
	if def == nil then
		return false, "Hmm, we do not know that skin."
	end
	local status = SkinRules.status(def, profile.stats.playSeconds, passes, profile.ownedSkins)
	if status == "static" then
		local cost = def.cost or 0
		if profile.static < cost then
			return false, "Not enough Static yet!"
		end
		profile.static -= cost
		profile.ownedSkins[id] = true
	elseif status ~= "owned" then
		return false, "Not unlocked yet. Keep exploring!"
	end
	profile.skin = id
	return true, def.name .. " is on!"
end

-- Drops an equipped skin the player no longer qualifies for (a pass that could not be
-- confirmed after a restore, say). Returns true if it changed anything.
function SkinRules.enforce(profile: SaveData.Profile, passes: Passes): boolean
	local def = Skins.byId[profile.skin]
	if
		def ~= nil
		and SkinRules.status(def, profile.stats.playSeconds, passes, profile.ownedSkins)
			~= "owned"
	then
		profile.skin = ""
		return true
	end
	return false
end

return SkinRules
