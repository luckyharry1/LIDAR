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
--
-- The standard (default) dots are a cool grey-white, (196, 200, 210). The playtime skins are
-- muted on purpose: a faint tint, close to the default, a quiet reward. The Robux skins are fully
-- saturated and bright so they pop at a glance, for the player and for teammates.

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
		wall = { 214, 196, 160 },
		gun = { 112, 100, 80 },
		kind = "playtime",
		minutes = 15,
	},
	{
		id = "glacier",
		name = "Glacier",
		blurb = "Cool teal-blue, like glowing ice!",
		wall = { 105, 170, 190 },
		gun = { 62, 98, 112 },
		kind = "playtime",
		minutes = 45,
	},
	{
		id = "orchid",
		name = "Orchid",
		blurb = "A dreamy pink-purple glow.",
		wall = { 196, 176, 208 },
		gun = { 98, 84, 110 },
		kind = "playtime",
		minutes = 90,
	},
	{
		id = "blueprint",
		name = "Blueprint",
		blurb = "Royal blue dots with a golden gun. Fancy!",
		wall = { 100, 120, 210 },
		gun = { 205, 165, 70 },
		kind = "playtime",
		minutes = 180,
	},
	{
		id = "rose",
		name = "Rose Quartz",
		blurb = "Hot pink dots that really pop!",
		wall = { 255, 80, 170 },
		gun = { 230, 60, 140 },
		kind = "robux",
		pass = "rose",
	},
	{
		id = "aurora",
		name = "Aurora",
		blurb = "Electric cyan dots and a glowing gun!",
		wall = { 40, 225, 255 },
		gun = { 0, 170, 205 },
		kind = "robux",
		pass = "aurora",
	},
	{
		id = "nightbloom",
		name = "Nightbloom",
		blurb = "Bright indigo dots that glow in the dark!",
		wall = { 105, 70, 255 },
		gun = { 80, 40, 220 },
		kind = "robux",
		pass = "nightbloom",
	},
} :: { SkinDef }

Skins.byId = {} :: { [string]: SkinDef }
for _, def in Skins.list do
	Skins.byId[def.id] = def
end

return Skins
