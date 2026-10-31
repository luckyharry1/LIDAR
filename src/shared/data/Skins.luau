--!strict
-- Scanner skins: a look for the dots and the gun, picked on the start screen and at the
-- workbench. Looks only, never power: every skin gives the same scanner, so a skinned player and
-- a plain one face the same dark (docs/MONETIZATION.md).
--
-- A skin is unlocked one of three ways:
--   free      always available (only the plain default, which is the empty id)
--   playtime  earned by time spent in the dark (profile.stats.playSeconds), nothing to buy
--   robux     a game pass. `pass` is a key of Config.Monetization.skinPassIds; the "pack" pass
--             unlocks every robux skin at once
--
-- Colours stay clear of the meaning colours: green is a friend, red is a monster, gold is an
-- objective, bright purple is a hazard. A skin only recolours white terrain dots (the wall tint)
-- and the gun housing.

export type SkinDef = {
	id: string,
	name: string,
	blurb: string,
	wall: { number }, -- RGB of the terrain dots
	gun: { number }, -- RGB of the gun housing
	kind: "playtime" | "robux",
	minutes: number?, -- playtime skins: minutes in the dark that unlock it
	pass: string?, -- robux skins: key into Config.Monetization.skinPassIds
}

local Skins = {}

Skins.packKey = "pack"

-- Order is the order on screen: earned skins first, in the order they arrive, then bought ones.
Skins.list = {
	{
		id = "tungsten",
		name = "Tungsten",
		blurb = "Cozy and glowy, like a night light.",
		wall = { 255, 226, 170 },
		gun = { 150, 118, 72 },
		kind = "playtime",
		minutes = 15,
	},
	{
		id = "glacier",
		name = "Glacier",
		blurb = "Chilly ice-blue dots!",
		wall = { 160, 235, 255 },
		gun = { 70, 112, 150 },
		kind = "playtime",
		minutes = 45,
	},
	{
		id = "orchid",
		name = "Orchid",
		blurb = "A dreamy pink-purple glow.",
		wall = { 222, 170, 255 },
		gun = { 112, 72, 150 },
		kind = "playtime",
		minutes = 90,
	},
	{
		id = "blueprint",
		name = "Blueprint",
		blurb = "Blue like a secret treasure map.",
		wall = { 112, 152, 255 },
		gun = { 52, 78, 150 },
		kind = "playtime",
		minutes = 180,
	},
	{
		id = "rose",
		name = "Rose Quartz",
		blurb = "Sparkly pink dots and a rose-gold gun.",
		wall = { 255, 165, 205 },
		gun = { 196, 112, 130 },
		kind = "robux",
		pass = "rose",
	},
	{
		id = "chrome",
		name = "Chrome",
		blurb = "Super shiny, with a mirror gun!",
		wall = { 245, 248, 255 },
		gun = { 205, 210, 222 },
		kind = "robux",
		pass = "chrome",
	},
	{
		id = "nightbloom",
		name = "Nightbloom",
		blurb = "Deep purple dots and a midnight gun.",
		wall = { 150, 124, 255 },
		gun = { 58, 44, 112 },
		kind = "robux",
		pass = "nightbloom",
	},
} :: { SkinDef }

Skins.byId = {} :: { [string]: SkinDef }
for _, def in Skins.list do
	Skins.byId[def.id] = def
end

return Skins
